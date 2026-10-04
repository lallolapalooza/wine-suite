# apitrace — Windows-side API tracer (IAT hooking) for the Wine ↔ Windows diff

Goal of the project slice: make **Resolume Arena 7** run under the locally built Wine by
comparing the API calls it makes on Windows with the calls it makes under Wine. This directory
is the **Windows side** of that comparison: a first-party API tracer that runs *inside* a real
Windows process and writes a machine-comparable one-line-per-call log.

Everything here was built with `x86_64-w64-mingw32-gcc` (13-win32) on the Linux host, run in the
`win11` libvirt guest (Windows 11, build 10.0.26200) and, for fast iteration, under the host's
Wine 10.0. No Microsoft Detours and no MinHook — the tracer is an **Import Address Table (IAT)**
tracer, so no inline-hook engine is needed.

---

## 1. Deliverables

| path | what |
|---|---|
| `src/apihook.c` | `apihook.dll` — injected into the target process, patches IAT slots, logs calls |
| `src/hook_common.S` | the Win64 call-through trampoline (assembly; the only place that touches registers/stack) |
| `src/apitrace.c` | `apitrace.exe` — launcher/injector (`CreateProcess` suspended + remote `LoadLibraryW`, or `--pid`) |
| `src/selftest.c` | `selftest.exe` — calls known APIs with known arguments and prints what it saw |
| `tests/lateload.c` | `lateload.dll` — runtime-loaded DLL used to prove dynamic module hooking |
| `test.cfg` | config for the self-test (incl. an exclusion and a never-resolving pattern) |
| `guest.cfg` | config used for the Windows guest reference traces (37 patterns) |
| `dyn.cfg` | config for the dynamic-load proof |
| `build.sh` | builds all four PEs, reproducibly (`-Wl,--no-insert-timestamp`) |
| `evidence/` | every log quoted below, plus the full `objdump -p` dumps |
| `notes/apitrace.md` | this document |

Build (host, ~5 s):

```
$ cd tools/apitrace && ./build.sh
== apihook.dll
== apitrace.exe
== selftest.exe
== lateload.dll
== ok
-rwxrwxr-x 1 asdf asdf 109420 apihook.dll
-rwxrwxr-x 1 asdf asdf 280495 apitrace.exe
-rwxrwxr-x 1 asdf asdf  92849 lateload.dll
-rwxrwxr-x 1 asdf asdf 270848 selftest.exe
```

The build is reproducible — two consecutive runs give identical hashes:

```
$ ./build.sh >/dev/null && md5sum build/*
c76cf677ce4d2ae3891803a140626955  build/apihook.dll
21ef1a5cbba6bb4f12664abaf1d5729f  build/apitrace.exe
fa8e5ed1cbe5c91eed4a351d47424078  build/lateload.dll
88fc6ae021d5efbeb53fe355674c2bd9  build/selftest.exe
$ ./build.sh >/dev/null && md5sum build/*      # identical
c76cf677ce4d2ae3891803a140626955  build/apihook.dll
21ef1a5cbba6bb4f12664abaf1d5729f  build/apitrace.exe
fa8e5ed1cbe5c91eed4a351d47424078  build/lateload.dll
88fc6ae021d5efbeb53fe355674c2bd9  build/selftest.exe
```

The same four hashes were confirmed **inside the guest** after downloading them
(`Get-FileHash … -Algorithm MD5`), so the artifacts that produced the guest evidence below are
bit-identical to the ones in `build/`.

---

## 2. Usage

```
apitrace.exe [--cfg F] [--out L] [--poll MS] [--dll F] [--timeout S] [--nowait]
             [--pid N] -- <target.exe> [args...]
```

* **Launch mode** (default): the target is created with `CREATE_SUSPENDED`, `apihook.dll` is
  injected with a remote `CreateRemoteThread`→`LoadLibraryW`, the tracer waits for the DLL's
  *ready* event, and only then calls `ResumeThread`. Every IAT slot of every already-loaded
  module is therefore already patched before the first user-mode instruction of the target runs.
  `--timeout S` terminates the target after S seconds (handy for GUI programs);
  `--nowait` returns immediately.
* **Attach mode** (`--pid N`): injects into an already-running process; the launcher exits once the
  hooks are live.
* Defaults: `--cfg <exe dir>\apitrace.cfg`, `--out <exe dir>\apitrace.log`,
  `--dll <exe dir>\apihook.dll`, `--poll 200`.

Configuration handover between the two processes is a small job file written next to the DLL as
`apitrace_<pid>.job` (`cfg=`, `out=`, `ready=`, `poll=`); the DLL deletes it after reading it, so
two concurrent traces never collide.

Example (guest, `C:\apitrace`):

```
apitrace.exe --cfg C:\apitrace\guest.cfg --out C:\apitrace\charmap.log --timeout 15 -- C:\Windows\System32\charmap.exe
```

---

## 3. Log grammar (exact)

One line per call, **after** the callee returned (so nested calls appear *before* their caller):

```
<seq> <tid> <dll>!<func> (arg0=0x..., arg1=0x...) -> 0x...
```

| field | meaning |
|---|---|
| `<seq>` | decimal, starts at 1, strictly increasing in file order (assigned under the log lock) |
| `<tid>` | decimal `GetCurrentThreadId()` of the calling thread |
| `<dll>` | the DLL name exactly as spelled in the **importing module's import descriptor**, e.g. `KERNEL32.dll`, `ntdll.dll`, `USER32.dll` (case preserved; a pattern `kernel32` matches it case-insensitively) |
| `<func>` | the imported symbol name, e.g. `CreateFileW` |
| `(argN=0x…)` | `arg0..arg3` are the Win64 argument registers `RCX,RDX,R8,R9`; `arg4..` are read from the caller's stack at `[rsp+0x28+8·(N-4)]`. Number of arguments and per-argument width come from the config (`@N`, `/…`), default 4 arguments at full register width. |
| `-> 0x…` | the return value in `RAX`, truncated to the configured return width (default full 64-bit) |

Examples (verbatim, from `evidence/selftest.guest.log`):

```
3 988 KERNEL32.dll!CreateFileW (arg0=0x7ff66790a0ce, arg1=0x40000000, arg2=0x0, arg3=0x0, arg4=0x2, arg5=0x80, arg6=0x0) -> 0xc0
4 988 KERNEL32.dll!WriteFile (arg0=0xc0, arg1=0x7ff66790a1ba, arg2=0xb, arg3=0x22fa9ffab8, arg4=0x0) -> 0x1
10 988 KERNEL32.dll!MulDiv (arg0=0x7, arg1=0x3, arg2=0x2) -> 0xb
```

`#`-prefixed lines are **header/metadata** lines, never call lines:

```
# apitrace apihook.dll win64 pid=<pid> tid=<tid>      first line of every run
# apihook=<path> # cfg=<path> # out=<path>
# patterns=N exclusions=N modules=N loader_notify=0|1 poll_ms=N cfg_error=…
# unresolved_patterns=N                               how many include patterns matched nothing
# pattern: <raw> -> dll=… func=… argc=… mask=… retw=… [(unresolved)]
# unresolved: <raw>                                   one line per unresolved include pattern
# exclude: <raw>                                      one line per exclusion pattern
# resolved: <raw>  (first match Dll!Func)             emitted when a late module resolves a pattern
# process exit                                        footer written from DLL_PROCESS_DETACH
```

**"Unresolved hooks are logged in the header"**: at injection time the tracer scans all loaded
modules and lists every *include* pattern that matched no import at all (`# unresolved: …`).
Patterns that only resolve later (module loaded at runtime) get a `# resolved: …` line when the
loader notification/poll sees them — see §6.5.

---

## 4. Config grammar

```
[~]dll!func[@argc[/argwidths][:retwidth]]     # comment
```

* `dll` matches the import descriptor's DLL name, with or without the `.dll` suffix, and may be
  `*`; `func` may be `*`. Matching is case-insensitive.
* `~` (before the DLL) marks an **exclusion**; exclusions are evaluated first and always win.
* `@argc` — how many arguments to log, `0..16` (default 4). `@0` prints `()` for void functions.
* `/argwidths` — one digit per argument giving the number of **architecturally defined** bytes
  (`1/2/4/8`; default 8 = the whole register). A 32-bit DWORD parameter only has a defined low
  half — the upper half of the register is *undefined by the Win64 ABI* and differs between
  Windows and Wine for the very same binary (`0x7ff600000002` vs `0x100000002` in an early run).
  Masking makes the Windows and Wine logs directly diffable.
* `:retwidth` — how many bytes of `RAX` to print (`4` or `8`, default 8), same rationale.
* Blank lines and `#…` comments are ignored; malformed lines are ignored (but count as patterns).

Example (from `guest.cfg`):

```
kernel32!CreateFileW@7/8448448:8     # lpFileName, dwDesiredAccess, dwShareMode, lpSA,
                                     # dwCreationDisposition, dwFlagsAndAttributes, hTemplate
ntdll!NtCreateFile@11/84888444484:4  # all 11 args, incl. 7 stack args; NTSTATUS return
user32!CreateWindowExW@12/488444448888:8
~kernel32!DeleteFileW                # never log this import
```

---

## 5. How it works

1. **Injection.** `apitrace.exe` writes the job file, resolves `kernel32!LoadLibraryW` in its own
   address space (system DLLs share one base address across processes on the same boot), and runs
   it as a remote thread inside the target. In launch mode the target is still `CREATE_SUSPENDED`,
   and by the time it is resumed all of its modules have been scanned and patched.
2. **Scanning.** `apihook.dll` walks every loaded module (`CreateToolhelp32Snapshot` +
   `Module32First/Next`), parses its PE headers, and iterates `IMAGE_DIRECTORY_ENTRY_IMPORT`.
   For every *named* import (`OriginalFirstThunk`), the `(descriptor dll, function)` pair is
   matched against the config. Ordinal-only imports are skipped. Delay-loaded import tables are
   not touched (their slots are filled lazily *after* a patch would be installed).
3. **Patching.** For each selected slot a 29-byte stub is generated in a 1 MiB
   `PAGE_EXECUTE_READWRITE` pool:

   ```
   68 <idx32>              push imm32 idx           ; hook index
   49 BB <orig64>          mov  r11, orig           ; real target
   FF 25 00 00 00 00       jmp  qword ptr [rip+0]   ; -> hook_common
   <&hook_common>
   ```

   The slot itself is made writable with `VirtualProtect` for the 8-byte store only, and the old
   protect is restored. No register is clobbered before the trampoline (important: `AL` carries
   the vector-argument count for varargs calls), so `push imm32` is the only pre-trampoline code.
4. **Trampoline** (`hook_common.S`). `hook_common` saves `RAX,RCX,RDX,R8,R9`, `xmm0-3` and the
   original target pointer in its own frame, then builds a **fresh callee frame below its own
   frame** containing the caller's shadow space and a copy of 16 stack-argument slots
   (`[S+0x28 … S+0xA8]`), restores every argument register, and tail-jumps to the real function.
   Because the copy lives *below* the trampoline's frame, the callee's own stack usage cannot
   clobber the saved state — this is what makes >4-argument APIs (`NtCreateFile`, 11 args;
   `CreateWindowExW`, 12 args) call through correctly. Control returns to the `.Lpost` label
   inside the copied frame, where `trace_emit(idx, a0..a3, retval, S)` is called and `RAX`, `RBP`
   and `RSP` are restored so the hooked caller sees a perfectly normal return.
5. **Late modules.** `ntdll!LdrRegisterDllNotification` is registered (the header records
   `loader_notify=1`); every `DLL_LOADED` notification scans the new module immediately. A
   background poll thread (default 200 ms, `--poll`) covers the case where the notification API is
   missing (e.g. old Wine) and re-scans modules whose IAT slots were still zero at injection time.
   Both paths are idempotent (a slot already pointing into the stub pool is skipped).
6. **Thread safety.** All log writes are serialised by an `SRWLOCK`; `seq` comes from
   `InterlockedIncrement64`; the hook index is reserved with `InterlockedIncrement`; the stub pool
   and slot tables are static (no heap allocation from the loader-notification callback, which runs
   under the loader lock); `trace_emit` re-entry is blocked per thread via a `TlsAlloc` flag, so
   the tracer's *own* `WriteFile` calls can never recurse. Nested calls made by the *target* are
   still logged.
7. **`apitrace.exe`** contains no tracing logic at all; it only parses the command line, resolves
   paths, writes the job file, injects, waits for the ready event, optionally resumes/kills/waits.
   `GetFullPathNameW` is called with distinct in/out buffers (passing the same buffer produced a
   `C:\apitrace\C:\apitrace\C:\apitrace` path on Windows but worked under Wine — found by the
   first guest run of the launcher).

---

## 6. Acceptance evidence

All guest commands were run through `tools/vm/vmcmd.sh` (PowerShell in `win11`); logs were copied
back with `curl.exe -T` into the host's `vmshare/` and are stored verbatim under `evidence/`.
Artifacts on both sides have MD5
`c76cf677ce4d2ae3891803a140626955` (`apihook.dll`),
`21ef1a5cbba6bb4f12664abaf1d5729f` (`apitrace.exe`),
`88fc6ae021d5efbeb53fe355674c2bd9` (`selftest.exe`),
`fa8e5ed1cbe5c91eed4a351d47424078` (`lateload.dll`).

### 6.1 `objdump -p` for both PEs

Full, unmodified output is appended at **Appendix A** (`apihook.dll`) and **Appendix B**
(`apitrace.exe`); the files are also kept as
`evidence/objdump-apihook.dll.txt` and `evidence/objdump-apitrace.exe.txt`.

### 6.2 Self-test: 3 known APIs, arguments and return values reproduced exactly

`selftest.exe` (`evidence/selftest.guest.log`, guest run; console output and log from the same
process, pid 10472 / tid 988 = 0x28e8 / 0x3dc):

```
apitrace: started pid 10472 (suspended): C:\apitrace\selftest.exe
apitrace: hooks installed (ready event signalled)
== selftest ==
pid=10472 tid=988
buf_wrote                    0x22fa9ffab8
buf_data                     0x22fa9ffac0
buf_got                      0x22fa9ffabc
k32name                      0x7ff66790a174
path_selftest_tmp            0x7ff66790a0ce
CreateFileW#1_ret            0xc0
WriteFile_ret                0x1
WriteFile_wrote              0xb
CloseHandle#1_ret            0x0
CreateFileW#2_ret            0xbc
ReadFile_ret                 0x1
ReadFile_got                 0xb
ReadFile_data               "hello-trace"
GetModuleHandleW_ret         0x7ffc462d0000
MulDiv_ret                   0xb
lstrlenA_ret                 0x5
GetCurrentProcessId_ret      0x28e8
GetCurrentThreadId_ret       0x3dc
== selftest done ==
apitrace: pid 10472 exited with 0
```

The log (`evidence/selftest.guest.log`, call lines only; the header is in the file):

```
1 988 KERNEL32.dll!GetCurrentThreadId () -> 0x3dc
2 988 KERNEL32.dll!GetCurrentProcessId () -> 0x28e8
3 988 KERNEL32.dll!CreateFileW (arg0=0x7ff66790a0ce, arg1=0x40000000, arg2=0x0, arg3=0x0, arg4=0x2, arg5=0x80, arg6=0x0) -> 0xc0
4 988 KERNEL32.dll!WriteFile (arg0=0xc0, arg1=0x7ff66790a1ba, arg2=0xb, arg3=0x22fa9ffab8, arg4=0x0) -> 0x1
5 988 KERNEL32.dll!CloseHandle (arg0=0xc0) -> 0x1
6 988 KERNEL32.dll!CreateFileW (arg0=0x7ff66790a0ce, arg1=0x80000000, arg2=0x1, arg3=0x0, arg4=0x3, arg5=0x80, arg6=0x0) -> 0xbc
7 988 KERNEL32.dll!ReadFile (arg0=0xbc, arg1=0x22fa9ffac0, arg2=0xb, arg3=0x22fa9ffabc, arg4=0x0) -> 0x1
8 988 KERNEL32.dll!CloseHandle (arg0=0xbc) -> 0x1
9 988 KERNEL32.dll!GetModuleHandleW (arg0=0x7ff66790a174) -> 0x7ffc462d0000
10 988 KERNEL32.dll!MulDiv (arg0=0x7, arg1=0x3, arg2=0x2) -> 0xb
11 988 KERNEL32.dll!lstrlenA (arg0=0x7ff66790a26a) -> 0x5
12 988 KERNEL32.dll!GetCurrentProcessId () -> 0x28e8
13 988 KERNEL32.dll!GetCurrentThreadId () -> 0x3dc
# process exit
```

Cross-check (every value matches what the process itself printed):

| API (import) | arguments in the log | printed by selftest | return in the log | printed by selftest |
|---|---|---|---|---|
| `KERNEL32.dll!CreateFileW` (7 args, 3 of them on the stack) | `arg0=0x7ff66790a0ce` `arg1=0x40000000` `arg2=0x0` `arg3=0x0` `arg4=0x2` `arg5=0x80` `arg6=0x0` | `path_selftest_tmp=0x7ff66790a0ce`, GENERIC_WRITE, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL | `0xc0` | `CreateFileW#1_ret=0xc0` |
| `KERNEL32.dll!WriteFile` (5 args) | `arg0=0xc0` `arg1=0x7ff66790a1ba` `arg2=0xb` `arg3=0x22fa9ffab8` `arg4=0x0` | handle from above, `"hello-trace"`, 11, `&wrote=buf_wrote=0x22fa9ffab8` | `0x1` | `WriteFile_ret=0x1`, `WriteFile_wrote=0xb` |
| `KERNEL32.dll!ReadFile` (5 args) | `arg0=0xbc` `arg1=0x22fa9ffac0` `arg2=0xb` `arg3=0x22fa9ffabc` `arg4=0x0` | handle, `data=buf_data=0x22fa9ffac0`, 11, `&got=buf_got=0x22fa9ffabc` | `0x1` | `ReadFile_ret=0x1`, `ReadFile_got=0xb`, data `"hello-trace"` |
| `KERNEL32.dll!GetModuleHandleW` | `arg0=0x7ff66790a174` | `k32name=0x7ff66790a174` | `0x7ffc462d0000` | `GetModuleHandleW_ret=0x7ffc462d0000` |
| `KERNEL32.dll!MulDiv` | `arg0=0x7 arg1=0x3 arg2=0x2` | `MulDiv(7,3,2)` | `0xb` | `MulDiv_ret=0xb` |
| `KERNEL32.dll!lstrlenA` | `arg0=0x7ff66790a26a` | string literal (in `.rdata`) | `0x5` | `lstrlenA_ret=0x5` |
| `KERNEL32.dll!GetCurrentProcessId` / `GetCurrentThreadId` | — | pid=10472, tid=988 | `0x28e8` / `0x3dc` | same |

Also visible in the header of that log:

```
# unresolved_patterns=1
# unresolved: ntdll!ThisDoesNotExist
# exclude: ~kernel32!DeleteFileW
```

* `ntdll!ThisDoesNotExist` is reported as unresolved (it matches no import) ✔
* `kernel32!DeleteFileW` is included *and* excluded: the exclusion wins, the selftest calls
  `DeleteFileW` twice, and **no** `DeleteFileW` line exists in the log ✔
* the same self-test also runs on the host under Wine (`evidence/selftest.wine.log`, 755 lines
  because Wine's msvcrt writes stdout one byte at a time through the hooked `WriteFile`) with the
  same 13 selftest lines and identical values.

### 6.3 End-to-end in the guest on a real Windows program: `notepad.exe`

```
apitrace: started pid 1704 (suspended): C:\Windows\System32\notepad.exe
apitrace: dll=C:\apitrace\apihook.dll
apitrace: hooks installed (ready event signalled)
apitrace: timeout 20s, terminating pid 1704
apitrace: pid 1704 exited with 1
```

Header + first lines copied back from the guest (`evidence/notepad.guest.log`, 229 lines):

```
# apitrace apihook.dll win64 pid=1704 tid=10756
# apihook=C:\apitrace\apihook.dll
# cfg=C:\apitrace\guest.cfg
# out=C:\apitrace\notepad.log
# patterns=37 exclusions=1 modules=53 loader_notify=1 poll_ms=200 cfg_error=-
# unresolved_patterns=8
...
1 6608 KERNEL32.dll!LoadLibraryExW (arg0=0x7ff7703d49f0, arg1=0x0, arg2=0x1000) -> 0x7ffc44d20000
2 6608 KERNEL32.dll!GetProcAddress (arg0=0x7ffc44d20000, arg1=0x7ff7703d49d8) -> 0x7ffc44da2760
3 6608 ntdll.dll!NtQueryValueKey (arg0=0x2b4, arg1=0xd65a72e598, arg2=0x2, arg3=0xd65a72e2c0, arg4=0x10, arg5=0x5a72e244) -> 0x0
4 6608 ntdll.dll!NtOpenKey (arg0=0xd65a72f360, arg1=0x2000000, arg2=0xd65a72f218) -> 0x0
...
```

Tail of the same log:

```
171 8896 ntdll.dll!NtCreateFile (arg0=0x153a2fec60, arg1=0x100080, arg2=0x153a2fece8, arg3=0x153a2fec90, arg4=0x0, arg5=0x0, arg6=0x7, arg7=0x1, arg8=0x24020, arg9=0x0, arg10=0x0) -> 0x0
172 8896 KERNEL32.dll!CreateFileW (arg0=0x1c373130d70, arg1=0x80, arg2=0x7, arg3=0x0, arg4=0x3, arg5=0x2000000, arg6=0x0) -> 0x358
175 8896 KERNEL32.dll!CloseHandle (arg0=0x368) -> 0x1
```

Notes: on Windows 11 `%SystemRoot%\System32\notepad.exe` is the Store-app launcher; it loads 53
modules, does registry/filesystem probing and spawns the packaged Notepad as a *child* process
(process trees are not followed — attach to that child instead). The trace is still a genuine
end-to-end trace of a real Windows program started by the tracer.

### 6.4 End-to-end: `charmap.exe` (classic Win32, richer trace)

```
apitrace: started pid 4124 (suspended): C:\Windows\System32\charmap.exe
apitrace: hooks installed (ready event signalled)
apitrace: timeout 15s, terminating pid 4124
charmap lines: 5201
```

`evidence/charmap.guest.log` (511 952 bytes; 5147 call lines) — function histogram computed from
that file on the host:

```
   3315 USER32.dll!DefWindowProcW          27 GDI32.dll!CreateCompatibleDC
    925 USER32.dll!GetSystemMetrics        18 ntdll.dll!NtOpenKey
    382 USER32.dll!LoadStringW             12 KERNEL32.dll!GetProcAddress
    272 ntdll.dll!NtQueryValueKey          11 ntdll.dll!NtCreateFile
    139 ntdll.dll!NtQueryAttributesFile    11 GDI32.dll!CreateCompatibleBitmap
                                          10 USER32.dll!CreateWindowExW
                                           8 KERNEL32.dll!CreateFileW
```

Selected lines (11- and 12-argument calls, i.e. 7–8 arguments passed on the stack):

```
65 11068 GDI32.dll!CreateCompatibleDC (arg0=0x0) -> 0x5d010a7c
71 11068 ntdll.dll!NtCreateFile (arg0=0x340e5ade80, arg1=0x80100080, arg2=0x340e5adf08, arg3=0x340e5adeb0, arg4=0x0, arg5=0x80, arg6=0x1, arg7=0x1, arg8=0x60, arg9=0x0, arg10=0x0) -> 0x0
```

This is the trace shape the Wine↔Windows diff needs: `ntdll` status codes on the wire
(`0xc0000034` = `STATUS_OBJECT_NAME_NOT_FOUND`, `0x80000005` = `STATUS_BUFFER_OVERFLOW`), the
`CreateWindowExW`/`DefWindowProcW` UI sequence, GDI handle creation and the registry probes.

### 6.5 Dynamic module hooking (a pattern that is unresolved at injection)

`dyn.cfg` selects `winmm!timeGetTime` — no module of the suspended process imports `winmm`.
`selftest.exe dyn` then `LoadLibraryW("lateload.dll")`, which statically imports
`winmm!timeGetTime`. Guest result (`evidence/dyn.guest.log`, complete file):

```
# apitrace apihook.dll win64 pid=7660 tid=6692
# apihook=C:\apitrace\apihook.dll
# cfg=C:\apitrace\dyn.cfg
# out=C:\apitrace\dyn.log
# patterns=1 exclusions=0 modules=6 loader_notify=1 poll_ms=200 cfg_error=-
# unresolved_patterns=1
# pattern: winmm!timeGetTime@0:4 -> dll=winmm func=timeGetTime argc=0 mask=8888888888888888 retw=4 (unresolved)
# unresolved: winmm!timeGetTime@0:4
# resolved: winmm!timeGetTime@0:4  (first match WINMM.dll!timeGetTime)
1 1276 WINMM.dll!timeGetTime () -> 0xc85774d
# process exit
```

and the program's own console, same process/run:

```
LoadLibraryW(lateload.dll) -> 0x7ffc28610000
GetProcAddress(lateload_ping) -> 0x7ffc28611310
lateload_ping() -> 0xc85774d
```

`0xc85774d` appears in both — the hook was installed on the IAT of a module that did not exist
when the tracer attached. The identical test under Wine gives the same three lines
(`evidence/dyn.wine.log`).

### 6.6 Attach mode (`--pid`)

```
apitrace: attaching to pid 6540
apitrace: apihook.dll@0xb47e0000 loaded in pid 6540
apitrace: hooks installed (ready event signalled)
attach lines: 26
```

`evidence/attach.guest.log`:

```
1 5568 KERNEL32.dll!CreateFileW (arg0=0x7ff66790a0ce, arg1=0x40000000, arg2=0x0, arg3=0x0, arg4=0x2, arg5=0x80, arg6=0x0) -> 0xb4
2 5568 KERNEL32.dll!WriteFile (arg0=0xb4, arg1=0x7ff66790a09b, arg2=0x4, arg3=0x18275ffc50, arg4=0x0) -> 0x1
3 5568 KERNEL32.dll!CloseHandle (arg0=0xb4) -> 0x1
4 5568 KERNEL32.dll!CreateFileW (arg0=0x7ff66790a0ce, arg1=0x40000000, arg2=0x0, arg3=0x0, arg4=0x2, arg5=0x80, arg6=0x0) -> 0xcc
...
```

The target was a `selftest.exe loop` process already running for 3 s; the calls it made after the
attach were captured. Attaching to an arbitrary long-running process (Arena under Windows) works
the same way.

### 6.7 Host Wine sanity check

The whole pipeline also runs under the host's Wine 10.0 (`state/tmp/prefix-apitrace`), which is
what made the iteration loop fast:

```
$ TMPDIR=…/state/tmp WINEPREFIX=…/prefix-apitrace wine apitrace.exe \
      --cfg ../test.cfg --out selftest.log -- ./selftest.exe
apitrace: started pid 284 (suspended): Z:\…\selftest.exe
apitrace: apihook.dll@0xfb480000 loaded in pid 284
apitrace: hooks installed (ready event signalled)
apitrace: pid 284 exited with 0
```

`evidence/selftest.wine.log` contains the same 13 calls with the same arguments/returns as the
Windows run (addresses differ, of course). This is useful on its own: the same config can be run
against a Wine-hosted copy of a program to produce a first diff without touching the guest.

---

## 7. Known limitations

* **Ordinal imports** are skipped (no name to match against).
* **Delay-loaded imports** are not patched: the delay-load helper writes the resolved address into
  the slot *after* the DLL starts, which would overwrite the stub. (static analysis of Arena.exe in the
  project's `notes/arena-pe.md` found no delay imports.)
* **Process trees are not followed.** A child process (e.g. the packaged Notepad spawned by
  Win11's `System32\notepad.exe`) must be traced with a separate attach.
* **32-bit (WOW64) targets** are not supported; the trampoline is Win64 only.
* **Argument *types* are not known.** `@argc`/`/argwidths` describe them, and by default the four
  register arguments are printed at full width; for 32-bit-typed parameters the upper 32 bits are
  undefined by the ABI, so configure `/4` masks when diffing.
* **Exception unwinding through a hooked call** is not supported by the trampoline (it carries no
  `.pdata`); the hooked function's own unwind data is untouched, and none of the programs traced
  here needed it.
* Calls made *by the tracer itself* while it is formatting/writing a log line are deliberately not
  logged (per-thread re-entry guard) — otherwise `WriteFile` would recurse forever.
* `CreateFileA` is used for the job file, config and log, so those paths must be ANSI.
* Log writes are unbuffered (one `WriteFile` per call). That survives a crash and is what the
  diff wants, but it is slower than buffering.

---

## 8. Reproducing the evidence

```sh
# host: build
cd tools/apitrace && ./build.sh

# host: stage artifacts for the guest (vmserv.py is already serving vmshare/ on :8000)
cp build/{apihook.dll,apitrace.exe,selftest.exe,lateload.dll} test.cfg guest.cfg dyn.cfg \
   ../../vmshare/apitrace/

# guest: self-test
tools/vm/vmcmd.sh '$d="C:\apitrace"; Set-Location $d;
  foreach($f in "apihook.dll","apitrace.exe","selftest.exe","lateload.dll","test.cfg","guest.cfg","dyn.cfg"){
    & curl.exe -sS -o "$d\$f" "http://192.168.122.1:8000/apitrace/$f" };
  & .\apitrace.exe --cfg $d\test.cfg --out $d\selftest.log -- $d\selftest.exe; Get-Content $d\selftest.log'

# guest: notepad / charmap / dynamic-load / attach
tools/vm/vmcmd.sh '& C:\apitrace\apitrace.exe --cfg C:\apitrace\guest.cfg --out C:\apitrace\notepad.log --timeout 20 -- C:\Windows\System32\notepad.exe'
tools/vm/vmcmd.sh '& C:\apitrace\apitrace.exe --cfg C:\apitrace\guest.cfg --out C:\apitrace\charmap.log --timeout 15 -- C:\Windows\System32\charmap.exe'
tools/vm/vmcmd.sh '& C:\apitrace\apitrace.exe --cfg C:\apitrace\dyn.cfg  --out C:\apitrace\dyn.log -- C:\apitrace\selftest.exe dyn'
tools/vm/vmcmd.sh 'C:\apitrace\apitrace.exe --pid (Get-Process notepad).Id --cfg C:\apitrace\guest.cfg --out C:\apitrace\attach.log'

# copy logs back (guest) and read the objdump dumps (host)
#   curl.exe -T C:\apitrace\<log> http://192.168.122.1:8000/guest-<log>
objdump -p build/apihook.dll  | less
objdump -p build/apitrace.exe | less
```

---

## Appendix A — `objdump -p build/apihook.dll` (verbatim)


```text

build/apihook.dll:     file format pei-x86-64

Characteristics 0x2026
	executable
	line numbers stripped
	large address aware
	DLL

Time/Date		Wed Dec 31 19:00:00 1969
Magic			020b	(PE32+)
MajorLinkerVersion	2
MinorLinkerVersion	45
SizeOfCode		0000000000003400
SizeOfInitializedData	0000000000002400
SizeOfUninitializedData	000000000088e000
AddressOfEntryPoint	0000000000001200
BaseOfCode		0000000000001000
ImageBase		000000024fd50000
SectionAlignment	00001000
FileAlignment		00000200
MajorOSystemVersion	4
MinorOSystemVersion	0
MajorImageVersion	0
MinorImageVersion	0
MajorSubsystemVersion	5
MinorSubsystemVersion	2
Win32Version		00000000
SizeOfImage		008ae000
SizeOfHeaders		00000600
CheckSum		0001c094
Subsystem		00000003	(Windows CUI)
DllCharacteristics	00000160
					HIGH_ENTROPY_VA
					DYNAMIC_BASE
					NX_COMPAT
SizeOfStackReserve	0000000000200000
SizeOfStackCommit	0000000000001000
SizeOfHeapReserve	0000000000100000
SizeOfHeapCommit	0000000000001000
LoaderFlags		00000000
NumberOfRvaAndSizes	00000010

The Data Directory
Entry 0 0000000000897000 0000005f Export Directory [.edata (or where ever we found it)]
Entry 1 0000000000898000 00000864 Import Directory [parts of .idata]
Entry 2 0000000000000000 00000000 Resource Directory [.rsrc]
Entry 3 0000000000007000 00000234 Exception Directory [.pdata]
Entry 4 0000000000000000 00000000 Security Directory
Entry 5 000000000089a000 0000004c Base Relocation Directory [.reloc]
Entry 6 0000000000000000 00000000 Debug Directory
Entry 7 0000000000000000 00000000 Description Directory
Entry 8 0000000000000000 00000000 Special Directory
Entry 9 00000000000062c0 00000028 Thread Storage Directory [.tls]
Entry a 0000000000000000 00000000 Load Configuration Directory
Entry b 0000000000000000 00000000 Bound Import Directory
Entry c 0000000000898218 000001d8 Import Address Table Directory
Entry d 0000000000000000 00000000 Delay Import Directory
Entry e 0000000000000000 00000000 CLR Runtime Header
Entry f 0000000000000000 00000000 Reserved

There is an import table in .idata at 0x2505e8000

The Import Tables (interpreted .idata section contents)
 vma:            Hint    Time      Forward  DLL       First
                 Table   Stamp     Chain    Name      Thunk
 00898000	00898040 00000000 00000000 008987f4 00898218

	DLL Name: KERNEL32.dll
	vma:     Ordinal  Hint  Member-Name  Bound-To
	00898218  <none>  0000  AcquireSRWLockExclusive
	00898220  <none>  0097  CloseHandle
	00898228  <none>  00d7  CreateFileA
	00898230  <none>  0107  CreateThread
	00898238  <none>  0110  CreateToolhelp32Snapshot
	00898240  <none>  0127  DeleteCriticalSection
	00898248  <none>  0129  DeleteFileA
	00898250  <none>  0138  DisableThreadLibraryCalls
	00898258  <none>  014d  EnterCriticalSection
	00898260  <none>  01bf  FlushInstructionCache
	00898268  <none>  0238  GetCurrentProcess
	00898270  <none>  0239  GetCurrentProcessId
	00898278  <none>  023d  GetCurrentThreadId
	00898280  <none>  0288  GetLastError
	00898288  <none>  029d  GetModuleFileNameW
	00898290  <none>  029e  GetModuleHandleA
	00898298  <none>  02da  GetProcAddress
	008982a0  <none>  02e1  GetProcessHeap
	008982a8  <none>  0379  HeapAlloc
	008982b0  <none>  0396  InitializeCriticalSection
	008982b8  <none>  03f4  LeaveCriticalSection
	008982c0  <none>  041c  Module32FirstW
	008982c8  <none>  041e  Module32NextW
	008982d0  <none>  043c  OpenEventA
	008982d8  <none>  04b1  ReadFile
	008982e0  <none>  04cb  ReleaseSRWLockExclusive
	008982e8  <none>  053d  SetEvent
	008982f0  <none>  05a9  Sleep
	008982f8  <none>  05cb  TlsAlloc
	00898300  <none>  05cd  TlsGetValue
	00898308  <none>  05cf  TlsSetValue
	00898310  <none>  05f7  VirtualAlloc
	00898318  <none>  05fd  VirtualProtect
	00898320  <none>  05ff  VirtualQuery
	00898328  <none>  0634  WideCharToMultiByte
	00898330  <none>  0648  WriteFile

 00898014	00898168 00000000 00000000 00898858 00898340

	DLL Name: msvcrt.dll
	vma:     Ordinal  Hint  Member-Name  Bound-To
	00898340  <none>  0081  __iob_func
	00898348  <none>  00bf  _amsg_exit
	00898350  <none>  017b  _initterm
	00898358  <none>  01e2  _lock
	00898360  <none>  02c3  _snprintf
	00898368  <none>  0334  _unlock
	00898370  <none>  0352  _vsnprintf
	00898378  <none>  03f8  abort
	00898380  <none>  0405  atoi
	00898388  <none>  0409  calloc
	00898390  <none>  0429  fprintf
	00898398  <none>  0430  free
	008983a0  <none>  0473  memcpy
	008983a8  <none>  0487  realloc
	008983b0  <none>  049e  strchr
	008983b8  <none>  04a6  strlen
	008983c0  <none>  04a9  strncmp
	008983c8  <none>  04aa  strncpy
	008983d0  <none>  04ac  strpbrk
	008983d8  <none>  04ad  strrchr
	008983e0  <none>  04c8  vfprintf

 00898028	00000000 00000000 00000000 00000000 00000000

There is an export table in .edata at 0x2505e7000

The Export Tables (interpreted .edata section contents)

Export Flags 			0
Time/Date stamp 		0
Major/Minor 			0/0
Name 				000000000089703c apihook.dll
Ordinal Base 			1
Number in:
	Export Address Table 		00000002
	[Name Pointer/Ordinal] Table	00000002
Table Addresses
	Export Address Table 		0000000000897028
	Name Pointer Table 		0000000000897030
	Ordinal Table 			0000000000897038

Export Address Table -- Ordinal Base 1
	          Ordinal  Address  Type
	[   0] +base[   1] 00003070 Export RVA
	[   1] +base[   2] 00002c30 Export RVA

[Ordinal/Name Pointer] Table -- Ordinal Base 1
	          Ordinal   Hint Name
	[   0] +base[   1]  0000 hook_common
	[   1] +base[   2]  0001 trace_emit

The Function Table (interpreted .pdata section contents)
vma:			BeginAddress	 EndAddress	  UnwindData
 000000024fd57000:	000000024fd51000 000000024fd511fa 000000024fd58000
 000000024fd5700c:	000000024fd51200 000000024fd512e0 000000024fd58014
 000000024fd57018:	000000024fd512e0 000000024fd512ef 000000024fd58024
 000000024fd57024:	000000024fd512f0 000000024fd512fc 000000024fd58028
 000000024fd57030:	000000024fd51300 000000024fd51301 000000024fd5802c
 000000024fd5703c:	000000024fd51310 000000024fd51363 000000024fd58030
 000000024fd57048:	000000024fd51370 000000024fd513d4 000000024fd58034
 000000024fd57054:	000000024fd513e0 000000024fd5171f 000000024fd58040
 000000024fd57060:	000000024fd51720 000000024fd5176c 000000024fd58054
 000000024fd5706c:	000000024fd51770 000000024fd51a0b 000000024fd5805c
 000000024fd57078:	000000024fd51a10 000000024fd51a9b 000000024fd58074
 000000024fd57084:	000000024fd51aa0 000000024fd5206b 000000024fd58080
 000000024fd57090:	000000024fd52070 000000024fd52162 000000024fd580a0
 000000024fd5709c:	000000024fd52170 000000024fd5235f 000000024fd580b0
 000000024fd570a8:	000000024fd52360 000000024fd52be8 000000024fd580c8
 000000024fd570b4:	000000024fd52bf0 000000024fd52c28 000000024fd580e8
 000000024fd570c0:	000000024fd52c30 000000024fd52f99 000000024fd580f0
 000000024fd570cc:	000000024fd52fa0 000000024fd5306b 000000024fd58108
 000000024fd570d8:	000000024fd53190 000000024fd531d3 000000024fd58110
 000000024fd570e4:	000000024fd531e0 000000024fd53262 000000024fd5811c
 000000024fd570f0:	000000024fd53270 000000024fd5328f 000000024fd5812c
 000000024fd570fc:	000000024fd53290 000000024fd532a5 000000024fd58130
 000000024fd57108:	000000024fd532b0 000000024fd5332c 000000024fd58134
 000000024fd57114:	000000024fd53330 000000024fd53333 000000024fd58144
 000000024fd57120:	000000024fd53340 000000024fd5339e 000000024fd58148
 000000024fd5712c:	000000024fd533a0 000000024fd53502 000000024fd58158
 000000024fd57138:	000000024fd53510 000000024fd538a0 000000024fd58168
 000000024fd57144:	000000024fd538a0 000000024fd5391d 000000024fd58180
 000000024fd57150:	000000024fd53920 000000024fd539a8 000000024fd58194
 000000024fd5715c:	000000024fd539b0 000000024fd53a49 000000024fd581a0
 000000024fd57168:	000000024fd53a50 000000024fd53b52 000000024fd581ac
 000000024fd57174:	000000024fd53b60 000000024fd53b63 000000024fd581b8
 000000024fd57180:	000000024fd53b70 000000024fd53b9c 000000024fd581bc
 000000024fd5718c:	000000024fd53ba0 000000024fd53bf0 000000024fd581c0
 000000024fd57198:	000000024fd53bf0 000000024fd53c98 000000024fd581c4
 000000024fd571a4:	000000024fd53ca0 000000024fd53d20 000000024fd581d8
 000000024fd571b0:	000000024fd53d20 000000024fd53d57 000000024fd581dc
 000000024fd571bc:	000000024fd53d60 000000024fd53ddb 000000024fd581e0
 000000024fd571c8:	000000024fd53de0 000000024fd53e16 000000024fd581e4
 000000024fd571d4:	000000024fd53e20 000000024fd53ea9 000000024fd581e8
 000000024fd571e0:	000000024fd53eb0 000000024fd53f66 000000024fd581ec
 000000024fd571ec:	000000024fd53fb0 000000024fd53ff1 000000024fd581f0
 000000024fd571f8:	000000024fd54000 000000024fd54026 000000024fd58200
 000000024fd57204:	000000024fd54030 000000024fd5404d 000000024fd5820c
 000000024fd57210:	000000024fd54050 000000024fd5412a 000000024fd58210
 000000024fd5721c:	000000024fd54130 000000024fd5419e 000000024fd58220
 000000024fd57228:	000000024fd54370 000000024fd54375 000000024fd58230

Dump of .xdata
 000000024fd58000 (rva: 00008000): 000000024fd51000 - 000000024fd511fa
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x30
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000024fd58014 (rva: 00008014): 000000024fd51200 - 000000024fd512e0
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x38
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000024fd58024 (rva: 00008024): 000000024fd512e0 - 000000024fd512ef
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58028 (rva: 00008028): 000000024fd512f0 - 000000024fd512fc
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd5802c (rva: 0000802c): 000000024fd51300 - 000000024fd51301
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58030 (rva: 00008030): 000000024fd51310 - 000000024fd51363
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58034 (rva: 00008034): 000000024fd51370 - 000000024fd513d4
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x06, Frame offset: 0x0, Frame reg: none
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rsi
 000000024fd58040 (rva: 00008040): 000000024fd513e0 - 000000024fd5171f
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x13, Frame offset: 0x0, Frame reg: none
	  pc+0x13: alloc large area: rsp = rsp - 0x2490
	  pc+0x0b: push rbx
	  pc+0x0a: push rsi
	  pc+0x09: push rdi
	  pc+0x08: push rbp
	  pc+0x02: push r12
 000000024fd58054 (rva: 00008054): 000000024fd51720 - 000000024fd5176c
	Version: 1, Flags: none
	Nbr codes: 2, Prologue size: 0x05, Frame offset: 0x0, Frame reg: none
	  pc+0x05: alloc small area: rsp = rsp - 0x30
	  pc+0x01: push rbx
 000000024fd5805c (rva: 0000805c): 000000024fd51770 - 000000024fd51a0b
	Version: 1, Flags: none
	Nbr codes: 9, Prologue size: 0x10, Frame offset: 0x0, Frame reg: none
	  pc+0x10: alloc small area: rsp = rsp - 0x38
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push rbp
	  pc+0x08: push r12
	  pc+0x06: push r13
	  pc+0x04: push r14
	  pc+0x02: push r15
 000000024fd58074 (rva: 00008074): 000000024fd51a10 - 000000024fd51a9b
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: none
	  pc+0x08: alloc large area: rsp = rsp - 0x240
	  pc+0x01: push rbx
 000000024fd58080 (rva: 00008080): 000000024fd51aa0 - 000000024fd5206b
	Version: 1, Flags: none
	Nbr codes: 14, Prologue size: 0x23, Frame offset: 0x0, Frame reg: none
	  pc+0x23: save xmm7 at rsp + 0xd0
	  pc+0x1b: save xmm6 at rsp + 0xc0
	  pc+0x13: alloc large area: rsp = rsp - 0xe8
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push rbp
	  pc+0x08: push r12
	  pc+0x06: push r13
	  pc+0x04: push r14
	  pc+0x02: push r15
 000000024fd580a0 (rva: 000080a0): 000000024fd52070 - 000000024fd52162
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0b, Frame offset: 0x0, Frame reg: none
	  pc+0x0b: alloc large area: rsp = rsp - 0x88
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000024fd580b0 (rva: 000080b0): 000000024fd52170 - 000000024fd5235f
	Version: 1, Flags: none
	Nbr codes: 9, Prologue size: 0x11, Frame offset: 0x0, Frame reg: none
	  pc+0x11: alloc large area: rsp = rsp - 0x4c0
	  pc+0x0a: push rbx
	  pc+0x09: push rsi
	  pc+0x08: push rdi
	  pc+0x07: push rbp
	  pc+0x06: push r12
	  pc+0x04: push r13
	  pc+0x02: push r14
 000000024fd580c8 (rva: 000080c8): 000000024fd52360 - 000000024fd52be8
	Version: 1, Flags: none
	Nbr codes: 14, Prologue size: 0x23, Frame offset: 0x0, Frame reg: none
	  pc+0x23: save xmm7 at rsp + 0x140
	  pc+0x1b: save xmm6 at rsp + 0x130
	  pc+0x13: alloc large area: rsp = rsp - 0x158
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push rbp
	  pc+0x08: push r12
	  pc+0x06: push r13
	  pc+0x04: push r14
	  pc+0x02: push r15
 000000024fd580e8 (rva: 000080e8): 000000024fd52bf0 - 000000024fd52c28
	Version: 1, Flags: none
	Nbr codes: 2, Prologue size: 0x05, Frame offset: 0x0, Frame reg: none
	  pc+0x05: alloc small area: rsp = rsp - 0x20
	  pc+0x01: push rbx
 000000024fd580f0 (rva: 000080f0): 000000024fd52c30 - 000000024fd52f99
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x13, Frame offset: 0x0, Frame reg: none
	  pc+0x13: alloc large area: rsp = rsp - 0x3f8
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push rbp
	  pc+0x08: push r12
	  pc+0x06: push r13
	  pc+0x04: push r14
	  pc+0x02: push r15
 000000024fd58108 (rva: 00008108): 000000024fd52fa0 - 000000024fd5306b
	Version: 1, Flags: none
	Nbr codes: 2, Prologue size: 0x05, Frame offset: 0x0, Frame reg: none
	  pc+0x05: alloc small area: rsp = rsp - 0x40
	  pc+0x01: push rbx
 000000024fd58110 (rva: 00008110): 000000024fd53190 - 000000024fd531d3
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000024fd5811c (rva: 0000811c): 000000024fd531e0 - 000000024fd53262
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000024fd5812c (rva: 0000812c): 000000024fd53270 - 000000024fd5328f
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58130 (rva: 00008130): 000000024fd53290 - 000000024fd532a5
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58134 (rva: 00008134): 000000024fd532b0 - 000000024fd5332c
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000024fd58144 (rva: 00008144): 000000024fd53330 - 000000024fd53333
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58148 (rva: 00008148): 000000024fd53340 - 000000024fd5339e
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x30
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000024fd58158 (rva: 00008158): 000000024fd533a0 - 000000024fd53502
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x5, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x58
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000024fd58168 (rva: 00008168): 000000024fd53510 - 000000024fd538a0
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x4, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x48
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000024fd58180 (rva: 00008180): 000000024fd538a0 - 000000024fd5391d
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x20
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000024fd58194 (rva: 00008194): 000000024fd53920 - 000000024fd539a8
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000024fd581a0 (rva: 000081a0): 000000024fd539b0 - 000000024fd53a49
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000024fd581ac (rva: 000081ac): 000000024fd53a50 - 000000024fd53b52
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000024fd581b8 (rva: 000081b8): 000000024fd53b60 - 000000024fd53b63
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581bc (rva: 000081bc): 000000024fd53b70 - 000000024fd53b9c
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581c0 (rva: 000081c0): 000000024fd53ba0 - 000000024fd53bf0
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581c4 (rva: 000081c4): 000000024fd53bf0 - 000000024fd53c98
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x20
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000024fd581d8 (rva: 000081d8): 000000024fd53ca0 - 000000024fd53d20
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581dc (rva: 000081dc): 000000024fd53d20 - 000000024fd53d57
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581e0 (rva: 000081e0): 000000024fd53d60 - 000000024fd53ddb
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581e4 (rva: 000081e4): 000000024fd53de0 - 000000024fd53e16
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581e8 (rva: 000081e8): 000000024fd53e20 - 000000024fd53ea9
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581ec (rva: 000081ec): 000000024fd53eb0 - 000000024fd53f66
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd581f0 (rva: 000081f0): 000000024fd53fb0 - 000000024fd53ff1
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000024fd58200 (rva: 00008200): 000000024fd54000 - 000000024fd54026
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000024fd5820c (rva: 0000820c): 000000024fd54030 - 000000024fd5404d
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000024fd58210 (rva: 00008210): 000000024fd54050 - 000000024fd5412a
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x30
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000024fd58220 (rva: 00008220): 000000024fd54130 - 000000024fd5419e
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x28
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000024fd58230 (rva: 00008230): 000000024fd54370 - 000000024fd54375
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none


PE File Base Relocations (interpreted .reloc section contents)

Virtual Address: 00005000 Chunk size 20 (0x14) Number of fixups 6
	reloc    0 offset   20 [5020] DIR64
	reloc    1 offset   50 [5050] DIR64
	reloc    2 offset   60 [5060] DIR64
	reloc    3 offset   70 [5070] DIR64
	reloc    4 offset   78 [5078] DIR64
	reloc    5 offset   80 [5080] DIR64

Virtual Address: 00006000 Chunk size 56 (0x38) Number of fixups 24
	reloc    0 offset  2a0 [62a0] DIR64
	reloc    1 offset  2c0 [62c0] DIR64
	reloc    2 offset  2c8 [62c8] DIR64
	reloc    3 offset  2d0 [62d0] DIR64
	reloc    4 offset  2d8 [62d8] DIR64
	reloc    5 offset  460 [6460] DIR64
	reloc    6 offset  470 [6470] DIR64
	reloc    7 offset  480 [6480] DIR64
	reloc    8 offset  490 [6490] DIR64
	reloc    9 offset  4a0 [64a0] DIR64
	reloc   10 offset  4b0 [64b0] DIR64
	reloc   11 offset  4c0 [64c0] DIR64
	reloc   12 offset  4d0 [64d0] DIR64
	reloc   13 offset  4e0 [64e0] DIR64
	reloc   14 offset  4f0 [64f0] DIR64
	reloc   15 offset  500 [6500] DIR64
	reloc   16 offset  510 [6510] DIR64
	reloc   17 offset  520 [6520] DIR64
	reloc   18 offset  530 [6530] DIR64
	reloc   19 offset  540 [6540] DIR64
	reloc   20 offset  7b8 [67b8] DIR64
	reloc   21 offset  800 [6800] DIR64
	reloc   22 offset  808 [6808] DIR64
	reloc   23 offset    0 [6000] ABSOLUTE

```

---

## Appendix B — `objdump -p build/apitrace.exe` (verbatim)

```text

build/apitrace.exe:     file format pei-x86-64

Characteristics 0x26
	executable
	line numbers stripped
	large address aware

Time/Date		Wed Dec 31 19:00:00 1969
Magic			020b	(PE32+)
MajorLinkerVersion	2
MinorLinkerVersion	45
SizeOfCode		0000000000008800
SizeOfInitializedData	0000000000003200
SizeOfUninitializedData	0000000000000c00
AddressOfEntryPoint	0000000000001420
BaseOfCode		0000000000001000
ImageBase		0000000140000000
SectionAlignment	00001000
FileAlignment		00000200
MajorOSystemVersion	4
MinorOSystemVersion	0
MajorImageVersion	0
MinorImageVersion	0
MajorSubsystemVersion	5
MinorSubsystemVersion	2
Win32Version		00000000
SizeOfImage		00045000
SizeOfHeaders		00000600
CheckSum		0004ff7c
Subsystem		00000003	(Windows CUI)
DllCharacteristics	00000160
					HIGH_ENTROPY_VA
					DYNAMIC_BASE
					NX_COMPAT
SizeOfStackReserve	0000000000200000
SizeOfStackCommit	0000000000001000
SizeOfHeapReserve	0000000000100000
SizeOfHeapCommit	0000000000001000
LoaderFlags		00000000
NumberOfRvaAndSizes	00000010

The Data Directory
Entry 0 0000000000000000 00000000 Export Directory [.edata (or where ever we found it)]
Entry 1 0000000000010000 00000b38 Import Directory [parts of .idata]
Entry 2 0000000000000000 00000000 Resource Directory [.rsrc]
Entry 3 000000000000d000 00000498 Exception Directory [.pdata]
Entry 4 0000000000000000 00000000 Security Directory
Entry 5 0000000000012000 0000007c Base Relocation Directory [.reloc]
Entry 6 0000000000000000 00000000 Debug Directory
Entry 7 0000000000000000 00000000 Description Directory
Entry 8 0000000000000000 00000000 Special Directory
Entry 9 000000000000b520 00000028 Thread Storage Directory [.tls]
Entry a 0000000000000000 00000000 Load Configuration Directory
Entry b 0000000000000000 00000000 Bound Import Directory
Entry c 00000000000102d0 00000280 Import Address Table Directory
Entry d 0000000000000000 00000000 Delay Import Directory
Entry e 0000000000000000 00000000 CLR Runtime Header
Entry f 0000000000000000 00000000 Reserved

There is an import table in .idata at 0x140010000

The Import Tables (interpreted .idata section contents)
 vma:            Hint    Time      Forward  DLL       First
                 Table   Stamp     Chain    Name      Thunk
 00010000	00010050 00000000 00000000 00010a5c 000102d0

	DLL Name: KERNEL32.dll
	vma:     Ordinal  Hint  Member-Name  Bound-To
	000102d0  <none>  0097  CloseHandle
	000102d8  <none>  00d3  CreateEventW
	000102e0  <none>  00fa  CreateProcessW
	000102e8  <none>  00fc  CreateRemoteThread
	000102f0  <none>  0127  DeleteCriticalSection
	000102f8  <none>  014d  EnterCriticalSection
	00010300  <none>  01f7  GetCommandLineW
	00010308  <none>  0260  GetExitCodeProcess
	00010310  <none>  0261  GetExitCodeThread
	00010318  <none>  026b  GetFileAttributesW
	00010320  <none>  0280  GetFullPathNameW
	00010328  <none>  0288  GetLastError
	00010330  <none>  029d  GetModuleFileNameW
	00010338  <none>  02a1  GetModuleHandleW
	00010340  <none>  02da  GetProcAddress
	00010348  <none>  0396  InitializeCriticalSection
	00010350  <none>  03b1  IsDBCSLeadByteEx
	00010358  <none>  03f4  LeaveCriticalSection
	00010360  <none>  0428  MultiByteToWideChar
	00010368  <none>  0449  OpenProcess
	00010370  <none>  04e6  ResumeThread
	00010378  <none>  0599  SetUnhandledExceptionFilter
	00010380  <none>  05a9  Sleep
	00010388  <none>  05b9  TerminateProcess
	00010390  <none>  05cd  TlsGetValue
	00010398  <none>  05f8  VirtualAllocEx
	000103a0  <none>  05fb  VirtualFreeEx
	000103a8  <none>  05fd  VirtualProtect
	000103b0  <none>  05ff  VirtualQuery
	000103b8  <none>  0608  WaitForSingleObject
	000103c0  <none>  0634  WideCharToMultiByte
	000103c8  <none>  0651  WriteProcessMemory

 00010014	00010158 00000000 00000000 00010b1c 000103d8

	DLL Name: msvcrt.dll
	vma:     Ordinal  Hint  Member-Name  Bound-To
	000103d8  <none>  0059  __C_specific_handler
	000103e0  <none>  006d  ___lc_codepage_func
	000103e8  <none>  0070  ___mb_cur_max_func
	000103f0  <none>  007f  __getmainargs
	000103f8  <none>  0080  __initenv
	00010400  <none>  0081  __iob_func
	00010408  <none>  00a0  __set_app_type
	00010410  <none>  00a2  __setusermatherr
	00010418  <none>  00bf  _amsg_exit
	00010420  <none>  00d2  _cexit
	00010428  <none>  00e0  _commode
	00010430  <none>  010a  _errno
	00010438  <none>  012c  _fmode
	00010440  <none>  017b  _initterm
	00010448  <none>  01e2  _lock
	00010450  <none>  02c3  _snprintf
	00010458  <none>  02cd  _snwprintf
	00010460  <none>  0334  _unlock
	00010468  <none>  03eb  _wtoi
	00010470  <none>  03f8  abort
	00010478  <none>  03ff  atexit
	00010480  <none>  0409  calloc
	00010488  <none>  0416  exit
	00010490  <none>  041a  fclose
	00010498  <none>  0427  fopen
	000104a0  <none>  0429  fprintf
	000104a8  <none>  042b  fputc
	000104b0  <none>  0430  free
	000104b8  <none>  043b  fwrite
	000104c0  <none>  0463  localeconv
	000104c8  <none>  046a  malloc
	000104d0  <none>  0473  memcpy
	000104d8  <none>  0475  memset
	000104e0  <none>  0480  puts
	000104e8  <none>  0491  signal
	000104f0  <none>  04a4  strerror
	000104f8  <none>  04a6  strlen
	00010500  <none>  04a9  strncmp
	00010508  <none>  04c8  vfprintf
	00010510  <none>  04d6  wcscmp
	00010518  <none>  04dc  wcslen
	00010520  <none>  04e0  wcsncpy
	00010528  <none>  04e2  wcspbrk
	00010530  <none>  04e3  wcsrchr

 00010028	000102c0 00000000 00000000 00010b2c 00010540

	DLL Name: SHELL32.dll
	vma:     Ordinal  Hint  Member-Name  Bound-To
	00010540  <none>  000a  CommandLineToArgvW

 0001003c	00000000 00000000 00000000 00000000 00000000

The Function Table (interpreted .pdata section contents)
vma:			BeginAddress	 EndAddress	  UnwindData
 000000014000d000:	0000000140001000 0000000140001001 000000014000e000
 000000014000d00c:	0000000140001010 00000001400013ea 000000014000e004
 000000014000d018:	00000001400013f0 0000000140001412 000000014000e01c
 000000014000d024:	0000000140001420 0000000140001442 000000014000e040
 000000014000d030:	0000000140001450 0000000140001455 000000014000e064
 000000014000d03c:	0000000140001460 000000014000146c 000000014000e068
 000000014000d048:	0000000140001470 0000000140001471 000000014000e06c
 000000014000d054:	0000000140001480 00000001400014bc 000000014000e070
 000000014000d060:	00000001400014c0 00000001400016c4 000000014000e07c
 000000014000d06c:	00000001400016d0 000000014000171a 000000014000e08c
 000000014000d078:	0000000140001730 0000000140001773 000000014000e0b4
 000000014000d084:	0000000140001780 0000000140001802 000000014000e0c0
 000000014000d090:	0000000140001810 000000014000182f 000000014000e0d0
 000000014000d09c:	0000000140001830 0000000140001833 000000014000e0d4
 000000014000d0a8:	0000000140001840 0000000140001855 000000014000e0d8
 000000014000d0b4:	0000000140001860 00000001400018dc 000000014000e0dc
 000000014000d0c0:	00000001400018e0 00000001400018e3 000000014000e0ec
 000000014000d0cc:	00000001400018f0 00000001400019e8 000000014000e0f0
 000000014000d0d8:	00000001400019f0 0000000140001a4e 000000014000e10c
 000000014000d0e4:	0000000140001a50 0000000140001bb2 000000014000e11c
 000000014000d0f0:	0000000140001bc0 0000000140001f50 000000014000e12c
 000000014000d0fc:	0000000140001f50 0000000140001f8a 000000014000e144
 000000014000d108:	0000000140001f90 0000000140001f9c 000000014000e150
 000000014000d114:	0000000140001fa0 000000014000215d 000000014000e154
 000000014000d120:	0000000140002160 00000001400021dd 000000014000e160
 000000014000d12c:	00000001400021e0 0000000140002268 000000014000e174
 000000014000d138:	0000000140002270 0000000140002309 000000014000e180
 000000014000d144:	0000000140002310 0000000140002412 000000014000e18c
 000000014000d150:	0000000140002420 0000000140002423 000000014000e198
 000000014000d15c:	0000000140002430 000000014000245c 000000014000e19c
 000000014000d168:	0000000140002460 00000001400024b0 000000014000e1a0
 000000014000d174:	00000001400024b0 0000000140002558 000000014000e1a4
 000000014000d180:	0000000140002560 00000001400025e0 000000014000e1b8
 000000014000d18c:	00000001400025e0 0000000140002617 000000014000e1bc
 000000014000d198:	0000000140002620 000000014000269b 000000014000e1c0
 000000014000d1a4:	00000001400026a0 00000001400026d6 000000014000e1c4
 000000014000d1b0:	00000001400026e0 0000000140002769 000000014000e1c8
 000000014000d1bc:	0000000140002770 0000000140002826 000000014000e1cc
 000000014000d1c8:	0000000140002870 00000001400028c7 000000014000e1d0
 000000014000d1d4:	0000000140002900 00000001400029fc 000000014000e1e0
 000000014000d1e0:	0000000140002a00 0000000140002a61 000000014000e1ec
 000000014000d1ec:	0000000140002a70 0000000140002bfc 000000014000e1f8
 000000014000d1f8:	0000000140002c00 0000000140002d42 000000014000e210
 000000014000d204:	0000000140002d50 0000000140002d9f 000000014000e220
 000000014000d210:	0000000140002da0 0000000140002e29 000000014000e230
 000000014000d21c:	0000000140002e30 0000000140003518 000000014000e23c
 000000014000d228:	0000000140003520 00000001400039e7 000000014000e254
 000000014000d234:	00000001400039f0 0000000140003b3e 000000014000e26c
 000000014000d240:	0000000140003b40 0000000140003fa0 000000014000e280
 000000014000d24c:	0000000140003fa0 000000014000407f 000000014000e294
 000000014000d258:	0000000140004080 000000014000411c 000000014000e2a4
 000000014000d264:	0000000140004120 00000001400041fc 000000014000e2b4
 000000014000d270:	0000000140004200 0000000140004395 000000014000e2c4
 000000014000d27c:	00000001400043a0 0000000140004863 000000014000e2d4
 000000014000d288:	0000000140004870 0000000140005320 000000014000e2ec
 000000014000d294:	0000000140005340 00000001400053b9 000000014000e308
 000000014000d2a0:	00000001400053c0 0000000140005400 000000014000e318
 000000014000d2ac:	0000000140005400 0000000140005495 000000014000e324
 000000014000d2b8:	00000001400054a0 00000001400054c7 000000014000e334
 000000014000d2c4:	00000001400054d0 000000014000566d 000000014000e338
 000000014000d2d0:	0000000140005680 0000000140006f54 000000014000e350
 000000014000d2dc:	0000000140006f80 0000000140007092 000000014000e36c
 000000014000d2e8:	00000001400070a0 00000001400070e2 000000014000e380
 000000014000d2f4:	0000000140007100 00000001400071e9 000000014000e384
 000000014000d300:	00000001400071f0 0000000140007237 000000014000e394
 000000014000d30c:	0000000140007240 0000000140007349 000000014000e3a0
 000000014000d318:	0000000140007350 00000001400073bb 000000014000e3b0
 000000014000d324:	00000001400073c0 00000001400074a3 000000014000e3bc
 000000014000d330:	00000001400074b0 000000014000756d 000000014000e3c8
 000000014000d33c:	0000000140007570 0000000140007737 000000014000e3d4
 000000014000d348:	0000000140007740 00000001400078cf 000000014000e3ec
 000000014000d354:	00000001400078d0 0000000140007a3e 000000014000e400
 000000014000d360:	0000000140007a40 0000000140007aa0 000000014000e418
 000000014000d36c:	0000000140007aa0 0000000140007c96 000000014000e41c
 000000014000d378:	0000000140007ca0 0000000140007daf 000000014000e434
 000000014000d384:	0000000140007db0 0000000140007f78 000000014000e444
 000000014000d390:	0000000140007f80 0000000140007fb2 000000014000e454
 000000014000d39c:	0000000140007fc0 0000000140007ff5 000000014000e458
 000000014000d3a8:	0000000140008000 0000000140008086 000000014000e45c
 000000014000d3b4:	0000000140008090 00000001400080d2 000000014000e468
 000000014000d3c0:	00000001400080e0 00000001400081c6 000000014000e478
 000000014000d3cc:	00000001400081e0 0000000140008218 000000014000e490
 000000014000d3d8:	0000000140008220 0000000140008368 000000014000e494
 000000014000d3e4:	0000000140008370 00000001400083df 000000014000e4a0
 000000014000d3f0:	00000001400083e0 00000001400084ed 000000014000e4b4
 000000014000d3fc:	00000001400084f0 0000000140008551 000000014000e4cc
 000000014000d408:	0000000140008560 00000001400085a1 000000014000e4e0
 000000014000d414:	00000001400085b0 00000001400085bb 000000014000e4f0
 000000014000d420:	00000001400085c0 00000001400085cb 000000014000e4f4
 000000014000d42c:	00000001400085d0 00000001400085db 000000014000e4f8
 000000014000d438:	00000001400085e0 0000000140008650 000000014000e4fc
 000000014000d444:	0000000140008650 00000001400086b9 000000014000e508
 000000014000d450:	00000001400086c0 00000001400086c8 000000014000e514
 000000014000d45c:	00000001400086d0 00000001400086db 000000014000e518
 000000014000d468:	00000001400086e0 00000001400086f6 000000014000e51c
 000000014000d474:	0000000140008700 0000000140008726 000000014000e520
 000000014000d480:	0000000140008980 00000001400097c5 000000014000e098
 000000014000d48c:	00000001400097d0 00000001400097d5 000000014000e52c

Dump of .xdata
 000000014000e000 (rva: 0000e000): 0000000140001000 - 0000000140001001
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e004 (rva: 0000e004): 0000000140001010 - 00000001400013ea
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x5, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x58
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e01c (rva: 0000e01c): 00000001400013f0 - 0000000140001412
	Version: 1, Flags: UNW_FLAG_EHANDLER
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
	Handler: 0000000140008730.
	User data:
	  000: 01 00 00 00 f8 13 00 00 0b 14 00 00 a0 1f 00 00
	  010: 0b 14 00 00
 000000014000e040 (rva: 0000e040): 0000000140001420 - 0000000140001442
	Version: 1, Flags: UNW_FLAG_EHANDLER
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
	Handler: 0000000140008730.
	User data:
	  000: 01 00 00 00 28 14 00 00 3b 14 00 00 a0 1f 00 00
	  010: 3b 14 00 00
 000000014000e064 (rva: 0000e064): 0000000140001450 - 0000000140001455
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e068 (rva: 0000e068): 0000000140001460 - 000000014000146c
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e06c (rva: 0000e06c): 0000000140001470 - 0000000140001471
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e070 (rva: 0000e070): 0000000140001480 - 00000001400014bc
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x06, Frame offset: 0x0, Frame reg: none
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rsi
 000000014000e07c (rva: 0000e07c): 00000001400014c0 - 00000001400016c4
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x08, Frame offset: 0x0, Frame reg: none
	  pc+0x08: alloc small area: rsp = rsp - 0x28
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e08c (rva: 0000e08c): 00000001400016d0 - 000000014000171a
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x06, Frame offset: 0x0, Frame reg: none
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rsi
 000000014000e0b4 (rva: 0000e0b4): 0000000140001730 - 0000000140001773
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e0c0 (rva: 0000e0c0): 0000000140001780 - 0000000140001802
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e0d0 (rva: 0000e0d0): 0000000140001810 - 000000014000182f
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e0d4 (rva: 0000e0d4): 0000000140001830 - 0000000140001833
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e0d8 (rva: 0000e0d8): 0000000140001840 - 0000000140001855
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e0dc (rva: 0000e0dc): 0000000140001860 - 00000001400018dc
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e0ec (rva: 0000e0ec): 00000001400018e0 - 00000001400018e3
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e0f0 (rva: 0000e0f0): 00000001400018f0 - 00000001400019e8
	Version: 1, Flags: none
	Nbr codes: 11, Prologue size: 0x19, Frame offset: 0x4, Frame reg: rbp
	  pc+0x19: save xmm8 at rsp + 0x60
	  pc+0x14: save xmm7 at rsp + 0x50
	  pc+0x10: save xmm6 at rsp + 0x40
	  pc+0x0c: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x70
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e10c (rva: 0000e10c): 00000001400019f0 - 0000000140001a4e
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x30
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e11c (rva: 0000e11c): 0000000140001a50 - 0000000140001bb2
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x5, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x58
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e12c (rva: 0000e12c): 0000000140001bc0 - 0000000140001f50
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x4, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x48
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e144 (rva: 0000e144): 0000000140001f50 - 0000000140001f8a
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x50
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e150 (rva: 0000e150): 0000000140001f90 - 0000000140001f9c
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e154 (rva: 0000e154): 0000000140001fa0 - 000000014000215d
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e160 (rva: 0000e160): 0000000140002160 - 00000001400021dd
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x20
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000014000e174 (rva: 0000e174): 00000001400021e0 - 0000000140002268
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e180 (rva: 0000e180): 0000000140002270 - 0000000140002309
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e18c (rva: 0000e18c): 0000000140002310 - 0000000140002412
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e198 (rva: 0000e198): 0000000140002420 - 0000000140002423
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e19c (rva: 0000e19c): 0000000140002430 - 000000014000245c
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1a0 (rva: 0000e1a0): 0000000140002460 - 00000001400024b0
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1a4 (rva: 0000e1a4): 00000001400024b0 - 0000000140002558
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x20
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000014000e1b8 (rva: 0000e1b8): 0000000140002560 - 00000001400025e0
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1bc (rva: 0000e1bc): 00000001400025e0 - 0000000140002617
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1c0 (rva: 0000e1c0): 0000000140002620 - 000000014000269b
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1c4 (rva: 0000e1c4): 00000001400026a0 - 00000001400026d6
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1c8 (rva: 0000e1c8): 00000001400026e0 - 0000000140002769
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1cc (rva: 0000e1cc): 0000000140002770 - 0000000140002826
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e1d0 (rva: 0000e1d0): 0000000140002870 - 00000001400028c7
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x4, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x40
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e1e0 (rva: 0000e1e0): 0000000140002900 - 00000001400029fc
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x70
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e1ec (rva: 0000e1ec): 0000000140002a00 - 0000000140002a61
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x20
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e1f8 (rva: 0000e1f8): 0000000140002a70 - 0000000140002bfc
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x5, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x58
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e210 (rva: 0000e210): 0000000140002c00 - 0000000140002d42
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x28
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e220 (rva: 0000e220): 0000000140002d50 - 0000000140002d9f
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e230 (rva: 0000e230): 0000000140002da0 - 0000000140002e29
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e23c (rva: 0000e23c): 0000000140002e30 - 0000000140003518
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x3, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x38
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e254 (rva: 0000e254): 0000000140003520 - 00000001400039e7
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x2, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x28
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e26c (rva: 0000e26c): 00000001400039f0 - 0000000140003b3e
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x30
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r14
	  pc+0x01: push rbp
 000000014000e280 (rva: 0000e280): 0000000140003b40 - 0000000140003fa0
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x20
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000014000e294 (rva: 0000e294): 0000000140003fa0 - 000000014000407f
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x28
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e2a4 (rva: 0000e2a4): 0000000140004080 - 000000014000411c
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x5, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x50
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e2b4 (rva: 0000e2b4): 0000000140004120 - 00000001400041fc
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x5, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x50
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e2c4 (rva: 0000e2c4): 0000000140004200 - 0000000140004395
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x6, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x60 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x60
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e2d4 (rva: 0000e2d4): 00000001400043a0 - 0000000140004863
	Version: 1, Flags: none
	Nbr codes: 9, Prologue size: 0x13, Frame offset: 0x5, Frame reg: rbp
	  pc+0x13: FPReg: rbp = rsp + 0x50 (info = 0x0)
	  pc+0x0e: alloc small area: rsp = rsp - 0x50
	  pc+0x0a: push rbx
	  pc+0x09: push rsi
	  pc+0x08: push rdi
	  pc+0x07: push r12
	  pc+0x05: push r13
	  pc+0x03: push r14
	  pc+0x01: push rbp
 000000014000e2ec (rva: 0000e2ec): 0000000140004870 - 0000000140005320
	Version: 1, Flags: none
	Nbr codes: 11, Prologue size: 0x1b, Frame offset: 0xa, Frame reg: rbp
	  pc+0x1b: FPReg: rbp = rsp + 0xa0 (info = 0x0)
	  pc+0x13: alloc large area: rsp = rsp - 0xa8
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e308 (rva: 0000e308): 0000000140005340 - 00000001400053b9
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x4, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x40
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e318 (rva: 0000e318): 00000001400053c0 - 0000000140005400
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e324 (rva: 0000e324): 0000000140005400 - 0000000140005495
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x28
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e334 (rva: 0000e334): 00000001400054a0 - 00000001400054c7
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e338 (rva: 0000e338): 00000001400054d0 - 000000014000566d
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x3, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x38
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e350 (rva: 0000e350): 0000000140005680 - 0000000140006f54
	Version: 1, Flags: none
	Nbr codes: 11, Prologue size: 0x1b, Frame offset: 0xb, Frame reg: rbp
	  pc+0x1b: FPReg: rbp = rsp + 0xb0 (info = 0x0)
	  pc+0x13: alloc large area: rsp = rsp - 0xb8
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e36c (rva: 0000e36c): 0000000140006f80 - 0000000140007092
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0c, Frame offset: 0x0, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x08: push rbx
	  pc+0x07: push rsi
	  pc+0x06: push rdi
	  pc+0x05: push r12
	  pc+0x03: push r13
	  pc+0x01: push rbp
 000000014000e380 (rva: 0000e380): 00000001400070a0 - 00000001400070e2
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e384 (rva: 0000e384): 0000000140007100 - 00000001400071e9
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x30
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e394 (rva: 0000e394): 00000001400071f0 - 0000000140007237
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e3a0 (rva: 0000e3a0): 0000000140007240 - 0000000140007349
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x30
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e3b0 (rva: 0000e3b0): 0000000140007350 - 00000001400073bb
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x30
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e3bc (rva: 0000e3bc): 00000001400073c0 - 00000001400074a3
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x38
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e3c8 (rva: 0000e3c8): 00000001400074b0 - 000000014000756d
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x38
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e3d4 (rva: 0000e3d4): 0000000140007570 - 0000000140007737
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x4, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x48
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e3ec (rva: 0000e3ec): 0000000140007740 - 00000001400078cf
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x20
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000014000e400 (rva: 0000e400): 00000001400078d0 - 0000000140007a3e
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x2, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x28
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e418 (rva: 0000e418): 0000000140007a40 - 0000000140007aa0
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e41c (rva: 0000e41c): 0000000140007aa0 - 0000000140007c96
	Version: 1, Flags: none
	Nbr codes: 9, Prologue size: 0x13, Frame offset: 0x2, Frame reg: rbp
	  pc+0x13: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x0e: alloc small area: rsp = rsp - 0x20
	  pc+0x0a: push rbx
	  pc+0x09: push rsi
	  pc+0x08: push rdi
	  pc+0x07: push r12
	  pc+0x05: push r13
	  pc+0x03: push r14
	  pc+0x01: push rbp
 000000014000e434 (rva: 0000e434): 0000000140007ca0 - 0000000140007daf
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e444 (rva: 0000e444): 0000000140007db0 - 0000000140007f78
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e454 (rva: 0000e454): 0000000140007f80 - 0000000140007fb2
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e458 (rva: 0000e458): 0000000140007fc0 - 0000000140007ff5
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e45c (rva: 0000e45c): 0000000140008000 - 0000000140008086
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x50
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e468 (rva: 0000e468): 0000000140008090 - 00000001400080d2
	Version: 1, Flags: none
	Nbr codes: 6, Prologue size: 0x0d, Frame offset: 0x3, Frame reg: rbp
	  pc+0x0d: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x08: alloc small area: rsp = rsp - 0x38
	  pc+0x04: push rbx
	  pc+0x03: push rsi
	  pc+0x02: push rdi
	  pc+0x01: push rbp
 000000014000e478 (rva: 0000e478): 00000001400080e0 - 00000001400081c6
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x3, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x30 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x38
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e490 (rva: 0000e490): 00000001400081e0 - 0000000140008218
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e494 (rva: 0000e494): 0000000140008220 - 0000000140008368
	Version: 1, Flags: none
	Nbr codes: 3, Prologue size: 0x08, Frame offset: 0x0, Frame reg: rbp
	  pc+0x08: alloc small area: rsp = rsp - 0x40
	  pc+0x04: FPReg: rbp = rsp + 0x0 (info = 0x0)
	  pc+0x01: push rbp
 000000014000e4a0 (rva: 0000e4a0): 0000000140008370 - 00000001400083df
	Version: 1, Flags: none
	Nbr codes: 8, Prologue size: 0x11, Frame offset: 0x4, Frame reg: rbp
	  pc+0x11: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x0c: alloc small area: rsp = rsp - 0x48
	  pc+0x08: push rbx
	  pc+0x07: push rsi
	  pc+0x06: push rdi
	  pc+0x05: push r12
	  pc+0x03: push r13
	  pc+0x01: push rbp
 000000014000e4b4 (rva: 0000e4b4): 00000001400083e0 - 00000001400084ed
	Version: 1, Flags: none
	Nbr codes: 10, Prologue size: 0x15, Frame offset: 0x4, Frame reg: rbp
	  pc+0x15: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x10: alloc small area: rsp = rsp - 0x48
	  pc+0x0c: push rbx
	  pc+0x0b: push rsi
	  pc+0x0a: push rdi
	  pc+0x09: push r12
	  pc+0x07: push r13
	  pc+0x05: push r14
	  pc+0x03: push r15
	  pc+0x01: push rbp
 000000014000e4cc (rva: 0000e4cc): 00000001400084f0 - 0000000140008551
	Version: 1, Flags: none
	Nbr codes: 7, Prologue size: 0x0f, Frame offset: 0x4, Frame reg: rbp
	  pc+0x0f: FPReg: rbp = rsp + 0x40 (info = 0x0)
	  pc+0x0a: alloc small area: rsp = rsp - 0x40
	  pc+0x06: push rbx
	  pc+0x05: push rsi
	  pc+0x04: push rdi
	  pc+0x03: push r12
	  pc+0x01: push rbp
 000000014000e4e0 (rva: 0000e4e0): 0000000140008560 - 00000001400085a1
	Version: 1, Flags: none
	Nbr codes: 5, Prologue size: 0x0c, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0c: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x07: alloc small area: rsp = rsp - 0x20
	  pc+0x03: push rbx
	  pc+0x02: push rsi
	  pc+0x01: push rbp
 000000014000e4f0 (rva: 0000e4f0): 00000001400085b0 - 00000001400085bb
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e4f4 (rva: 0000e4f4): 00000001400085c0 - 00000001400085cb
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e4f8 (rva: 0000e4f8): 00000001400085d0 - 00000001400085db
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e4fc (rva: 0000e4fc): 00000001400085e0 - 0000000140008650
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e508 (rva: 0000e508): 0000000140008650 - 00000001400086b9
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e514 (rva: 0000e514): 00000001400086c0 - 00000001400086c8
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e518 (rva: 0000e518): 00000001400086d0 - 00000001400086db
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e51c (rva: 0000e51c): 00000001400086e0 - 00000001400086f6
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none
 000000014000e520 (rva: 0000e520): 0000000140008700 - 0000000140008726
	Version: 1, Flags: none
	Nbr codes: 4, Prologue size: 0x0b, Frame offset: 0x2, Frame reg: rbp
	  pc+0x0b: FPReg: rbp = rsp + 0x20 (info = 0x0)
	  pc+0x06: alloc small area: rsp = rsp - 0x28
	  pc+0x02: push rbx
	  pc+0x01: push rbp
 000000014000e098 (rva: 0000e098): 0000000140008980 - 00000001400097c5
	Version: 1, Flags: none
	Nbr codes: 12, Prologue size: 0x21, Frame offset: 0x0, Frame reg: none
	  pc+0x21: save xmm6 at rsp + 0x114f0
	  pc+0x19: alloc large area: rsp = rsp - 0x11508
	  pc+0x11: push rbx
	  pc+0x10: push rsi
	  pc+0x0f: push rdi
	  pc+0x0e: push rbp
	  pc+0x0d: push r12
	  pc+0x0b: push r13
	  pc+0x09: push r14
	  pc+0x02: push r15
 000000014000e52c (rva: 0000e52c): 00000001400097d0 - 00000001400097d5
	Version: 1, Flags: none
	Nbr codes: 0, Prologue size: 0x00, Frame offset: 0x0, Frame reg: none


PE File Base Relocations (interpreted .reloc section contents)

Virtual Address: 0000a000 Chunk size 32 (0x20) Number of fixups 12
	reloc    0 offset    0 [a000] DIR64
	reloc    1 offset   70 [a070] DIR64
	reloc    2 offset   80 [a080] DIR64
	reloc    3 offset   90 [a090] DIR64
	reloc    4 offset   a0 [a0a0] DIR64
	reloc    5 offset   b0 [a0b0] DIR64
	reloc    6 offset   c0 [a0c0] DIR64
	reloc    7 offset   c8 [a0c8] DIR64
	reloc    8 offset   d0 [a0d0] DIR64
	reloc    9 offset   d8 [a0d8] DIR64
	reloc   10 offset   e0 [a0e0] DIR64
	reloc   11 offset   f0 [a0f0] DIR64

Virtual Address: 0000b000 Chunk size 76 (0x4c) Number of fixups 34
	reloc    0 offset  500 [b500] DIR64
	reloc    1 offset  520 [b520] DIR64
	reloc    2 offset  528 [b528] DIR64
	reloc    3 offset  530 [b530] DIR64
	reloc    4 offset  538 [b538] DIR64
	reloc    5 offset  bc0 [bbc0] DIR64
	reloc    6 offset  bd0 [bbd0] DIR64
	reloc    7 offset  be0 [bbe0] DIR64
	reloc    8 offset  bf0 [bbf0] DIR64
	reloc    9 offset  c00 [bc00] DIR64
	reloc   10 offset  c10 [bc10] DIR64
	reloc   11 offset  c20 [bc20] DIR64
	reloc   12 offset  c30 [bc30] DIR64
	reloc   13 offset  c40 [bc40] DIR64
	reloc   14 offset  c50 [bc50] DIR64
	reloc   15 offset  c60 [bc60] DIR64
	reloc   16 offset  c70 [bc70] DIR64
	reloc   17 offset  c80 [bc80] DIR64
	reloc   18 offset  c90 [bc90] DIR64
	reloc   19 offset  ca0 [bca0] DIR64
	reloc   20 offset  cb0 [bcb0] DIR64
	reloc   21 offset  cc0 [bcc0] DIR64
	reloc   22 offset  cd0 [bcd0] DIR64
	reloc   23 offset  ce0 [bce0] DIR64
	reloc   24 offset  cf0 [bcf0] DIR64
	reloc   25 offset  d00 [bd00] DIR64
	reloc   26 offset  d10 [bd10] DIR64
	reloc   27 offset  d20 [bd20] DIR64
	reloc   28 offset  d30 [bd30] DIR64
	reloc   29 offset  d40 [bd40] DIR64
	reloc   30 offset  d50 [bd50] DIR64
	reloc   31 offset  d60 [bd60] DIR64
	reloc   32 offset  d70 [bd70] DIR64
	reloc   33 offset  d80 [bd80] DIR64

Virtual Address: 0000c000 Chunk size 16 (0x10) Number of fixups 4
	reloc    0 offset  338 [c338] DIR64
	reloc    1 offset  380 [c380] DIR64
	reloc    2 offset  388 [c388] DIR64
	reloc    3 offset    0 [c000] ABSOLUTE

```

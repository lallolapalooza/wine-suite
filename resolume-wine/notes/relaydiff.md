# relaydiff.py — Windows-side log normaliser/differ

`tools/relaydiff.py` turns two very different Win32 API call logs into one
canonical grammar and diffs them.  Its job in this project: run Resolume Arena
7 on Windows and under Wine, capture the API calls on both sides, and let the
diff point at the calls Wine gets wrong.

Two log grammars are understood:

* Wine `WINEDEBUG=+relay` (+ optionally `+timestamp`, `+pid`), e.g.
  `12345.678:0009:Call KERNEL32.CreateFileW(...) ret=...`
* the Windows-side ApiTracer format, e.g.
  `12 3484 KERNEL32!CreateFileW (arg0=0x12ab30, arg1="C:\\x") -> 0x40`

The parsers stream line by line, so a multi-GB relay log is scanned without
loading it into memory.  `diff` is the only sub-command that accumulates a
token stream, and that is bounded by `--max-calls` (default 5,000,000).

## Deviations / notes for the integrator

* `wine-log --errors` keeps a per-thread stack of *unreturned* calls only; a
  well-formed relay log pushes and pops immediately, so memory stays flat.
* `--tail N` buffers only the last N emitted lines (a `deque`), so it too is
  O(N) regardless of log size.
* `diff` normalises both formats onto the same token; in particular Wine's
  `<ptr> "string"` argument is split into two positional args during parsing
  and then the leading `PTR` is dropped in diff mode so it lines up with
  apitrace's single string argument.

## Normalisation rules (exact)

Parsing / autodetection:

1. A non-blank line whose first 13 characters contain `:` is tried as a Wine
   `+relay` line.  Otherwise, and on failure, it is tried as apitrace
   (`<seq> <tid> <dll>!<func> (<args>) -> <retval>`), then as
   already-normalised `wineout` (`<tid> <dll>!<func>(<args>)`).
2. Any exception while parsing a line, or a line that matches nothing, is
   silently skipped.  A malformed log can never abort the scan.
3. Wine header: optional `<digits>.<digits>:` timestamp, then one or more
   `hex:` fields (the last is the tid).  Leading `\x01`/whitespace and nested
   indentation are stripped.  Both `dll.func` and `dll!func` spellings map to
   display form `DLL!Func` (and to lower-case key `dll!func` for comparison).

Argument normalisation (`normalize_arg`):

4. `name=value` prefixes are dropped when normalising for `diff` (so apitrace
   `arg0=0x40` becomes `0x40`).
5. Quoted strings `"..."` / `L"..."` are decoded (`\\`, `\"`, `\n`, `\r`,
   `\t`, `\xNN`) and re-emitted with `\` → `\\` and `"` → `\"`; the `L` wide
   prefix is preserved, unless `drop_wide` (diff mode) folds it away.
6. `{ ... }` composite values are recursively normalised and rejoined with
   commas.
7. A Wine `<pointer> "string"` argument is split into two positional args.
8. `0x`/`0X` hex with optional sign → canonical lower-case `0x<hex>`.
9. Signed decimal digits → canonical decimal (e.g. `+12` → `12`).
10. A bare run of `[0-9a-fA-F]` is read as **hex** (Wine prints integer args
    with `%08lx`), and canonicalised to `0x<lowercase-hex>`.
11. Pointer-looking values: any value with magnitude `>= 0x10000`
    (`POINTER_MIN`) becomes the literal `PTR`.  The test is strict `<`, so
    `0x10000` itself is `PTR`.
12. Consequence of 8 + 10: `0x40`, `00000040` and bare `40` all canonicalise
    to `0x40`; `0x10000`, `10000` all become `PTR`.

Diff mode:

13. Function names are lower-cased for keys; display keeps `DLL!Func`.
14. Consecutive identical tokens are collapsed to `token xN`.
15. Reports call sequences in A-not-B and B-not-A (via `difflib.SequenceMatcher`
    over the collapsed token lists), then a per-function table with A, B and
    delta counts.

`wine-log`:

16. Each `Call` is rendered `<tid> DLL!Func(<normalised args>)`.
17. `--errors` pairs each `Ret` with the most recent open `Call` of the same
    function on the same thread, and emits only failing returns: NTSTATUS
    (`>= 0x80000000`, symbol looked up in a table) or known Win32 error codes
    (`!= 0`, in a table).  `--include-zero` additionally treats `0` as failure.
    It then prints a summary of `err:`/`fixme:` messages, keyed by
    `class:channel:func <message>` with hex runs, 8+ hex runs and decimal runs
    replaced by `#`.
18. `--tail N` emits only the last N call/failure lines before end of input
    (the crash/hang tail).  Combining `--tail N --errors` keeps the last N
    failing calls.
19. `--modules a,b,c` restricts call and return processing to those DLL module
    names (case-insensitive; `kernel32` matches `KERNEL32`).  The
    `err:`/`fixme:` message summary is not module-filtered.

---

## Commands run and their observed output

All commands run from `/home/asdf/projects/resolume-wine`.
Fixture logs live in `tools/apitrace/samples/`.

### 0. Compile + help

```
$ python3 -m py_compile tools/relaydiff.py && echo COMPILE_OK
COMPILE_OK

$ python3 tools/relaydiff.py --help
usage: relaydiff.py [-h] {wine-log,diff} ...

Normalise and diff Wine +relay logs against ApiTracer logs.

positional arguments:
  {wine-log,diff}
    wine-log       normalise a WINEDEBUG=+relay log
    diff           normalise and diff two logs

options:
  -h, --help       show this help message and exit

$ python3 tools/relaydiff.py wine-log --help
usage: relaydiff.py wine-log [-h] [--errors] [--include-zero] [--top TOP]
                             [--tail N] [--modules a,b,c] [--out OUT]
                             file

positional arguments:
  file             relay log file ('-' for stdin)

options:
  -h, --help       show this help message and exit
  --errors         emit only failing calls + err/fixme summary
  --include-zero   treat a zero return value as a failure
  --top TOP        how many err:/fixme: entries to show (default 25)
  --tail N         emit only the last N calls before the end of the log
                   (crash/hang tail)
  --modules a,b,c  only include calls whose DLL module is listed (comma-
                   separated, case-insensitive)
  --out OUT        output file (default stdout)
```

### a. `wine-log`

Input `tools/apitrace/samples/relay_a.log` (relay grammar).

```
$ python3 tools/relaydiff.py wine-log tools/apitrace/samples/relay_a.log
0009 KERNEL32!CreateFileW(PTR,"C:\\Users\\Public\\arena.cfg",PTR,0x3,0x0,0x3,0x80,0x0)
0009 ntdll!RtlDosPathNameToNtPathName_U_WithStatus(PTR,"C:\\Users\\Public\\arena.cfg",PTR,0x0,0x0)
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)
0009 ntdll!NtQueryValueKey(0x48,PTR,PTR,PTR,0x100,PTR)
000a user32!MessageBoxW(0x0,PTR,L"Arena",PTR,L"hello, world",0x10)
```

Note the pointer args (e.g. `0012ab30`, `0061fe00`) became `PTR`, small bare
hex integers were canonicalised (`00000040` → `0x40`, `00000100` → `0x100`),
and the quoted strings were preserved (including `L"..."`).

### b. `wine-log --errors`

```
$ python3 tools/relaydiff.py wine-log --errors tools/apitrace/samples/relay_a.log
0009 ntdll!NtQueryValueKey(0x48,PTR,PTR,PTR,0x100,PTR) -> 0xc0000034 [NTSTATUS STATUS_OBJECT_NAME_NOT_FOUND]

== err:/fixme: message summary (1 distinct, 1 total) ==
      1  fixme:heap:RtlSetHeapInformation # # # # stub
# total failing calls: 1
```

(`ReadFile` returning `0`/`1` is not an error and is not listed; the one
`c0000034` return is classified by symbol.)

### b2. `--tail` and `--modules`

```
$ python3 tools/relaydiff.py wine-log --tail 3 tools/apitrace/samples/relay_a.log
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)
0009 ntdll!NtQueryValueKey(0x48,PTR,PTR,PTR,0x100,PTR)
000a user32!MessageBoxW(0x0,PTR,L"Arena",PTR,L"hello, world",0x10)

$ python3 tools/relaydiff.py wine-log --modules kernel32 tools/apitrace/samples/relay_a.log
0009 KERNEL32!CreateFileW(PTR,"C:\\Users\\Public\\arena.cfg",PTR,0x3,0x0,0x3,0x80,0x0)
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)
0009 KERNEL32!ReadFile(0x40,PTR,0x400,PTR,0x0)

$ python3 tools/relaydiff.py wine-log --modules ntdll,user32 tools/apitrace/samples/relay_a.log
0009 ntdll!RtlDosPathNameToNtPathName_U_WithStatus(PTR,"C:\\Users\\Public\\arena.cfg",PTR,0x0,0x0)
0009 ntdll!NtQueryValueKey(0x48,PTR,PTR,PTR,0x100,PTR)
000a user32!MessageBoxW(0x0,PTR,L"Arena",PTR,L"hello, world",0x10)

$ python3 tools/relaydiff.py wine-log --errors --tail 2 tools/apitrace/samples/relay_a.log
0009 ntdll!NtQueryValueKey(0x48,PTR,PTR,PTR,0x100,PTR) -> 0xc0000034 [NTSTATUS STATUS_OBJECT_NAME_NOT_FOUND]

== err:/fixme: message summary (1 distinct, 1 total) ==
      1  fixme:heap:RtlSetHeapInformation # # # # stub
# total failing calls: 1
```

### c. `diff` of two synthetic logs differing in 3 places

`tools/apitrace/samples/diff_a.log` and `diff_b.log`.  They differ in exactly
three places: B has a second consecutive `ReadFile`, B calls `GetLastError`
where A calls `CloseHandle`, and B's `MessageBoxW` text is `"bye"` vs `"hello"`.
A writes its integers bare-hex, B writes them `0x`-prefixed — to prove the
canonicalisation, `CreateFileW` must not show up as a difference.

```
$ python3 tools/relaydiff.py diff tools/apitrace/samples/diff_a.log tools/apitrace/samples/diff_b.log
# A = tools/apitrace/samples/diff_a.log  (4 calls)
# B = tools/apitrace/samples/diff_b.log  (5 calls)

== call sequences in A not in B (3) ==
  kernel32!readfile(0x40,PTR,0x400,PTR,0x0)
  kernel32!closehandle(0x40)
  user32!messageboxw(0x0,"Arena","hello",0x10)

== call sequences in B not in A (3) ==
  kernel32!readfile(0x40,PTR,0x400,PTR,0x0) x2
  kernel32!getlasterror()
  user32!messageboxw(0x0,"Arena","bye",0x10)

== per-function call counts ==
function                    A       B   delta
kernel32!readfile           1       2      +1
kernel32!createfilew        1       1      +0
user32!messageboxw          1       1      +0
kernel32!closehandle        1       0      -1
kernel32!getlasterror       0       1      +1
```

`kernel32!createfilew` appears only in the count table with delta `+0`, i.e.
the bare-hex vs `0x`-prefixed spellings matched exactly after normalisation.

### c2. Cross-format diff (relay vs apitrace)

```
$ python3 tools/relaydiff.py diff tools/apitrace/samples/relay_a.log tools/apitrace/samples/apitrace_a.log
# A = tools/apitrace/samples/relay_a.log  (7 calls)
# B = tools/apitrace/samples/apitrace_a.log  (5 calls)

== call sequences in A not in B (2) ==
  kernel32!readfile(0x40,PTR,0x400,PTR,0x0) x3
  ntdll!ntqueryvaluekey(0x48,PTR,PTR,PTR,0x100,PTR)

== call sequences in B not in A (2) ==
  kernel32!readfile(0x40,PTR,0x400,PTR,0x0)
  kernel32!getlasterror()

== per-function call counts ==
function                                            A       B   delta
kernel32!readfile                                   3       1      -2
kernel32!createfilew                                1       1      +0
ntdll!rtldospathnametontpathname_u_withstatus       1       1      +0
user32!messageboxw                                  1       1      +0
kernel32!getlasterror                               0       1      +1
ntdll!ntqueryvaluekey                               1       0      -1
```

`CreateFileW`, `RtlDosPathNameToNtPathName_U_WithStatus` and `MessageBoxW`
matched even though one side is Wine grammar and the other apitrace grammar
(including the wide/narrow string fold and the dropped `PTR` in front of each
Wine string).

### c3. `0x` vs bare hex canonicalise identically

`hex_a.log` uses `0x`-prefixed values, `hex_b.log` uses bare hex / different
padding.

```
$ python3 tools/relaydiff.py wine-log tools/apitrace/samples/hex_a.log
0009 KERNEL32!CreateFileW(0x40,"x",PTR,0x3)

$ python3 tools/relaydiff.py wine-log tools/apitrace/samples/hex_b.log
0009 KERNEL32!CreateFileW(0x40,"x",PTR,0x3)

$ python3 tools/relaydiff.py diff tools/apitrace/samples/hex_a.log tools/apitrace/samples/hex_b.log
# A = tools/apitrace/samples/hex_a.log  (1 calls)
# B = tools/apitrace/samples/hex_b.log  (1 calls)

== call sequences in A not in B (0) ==
  (none)

== call sequences in B not in A (0) ==
  (none)

== per-function call counts ==
function                   A       B   delta
kernel32!createfilew       1       1      +0
```

`0x40` ≡ `00000040` → `0x40`, `0x10000` ≡ `10000` → `PTR`, `3` ≡ `0x3` → `0x3`.

### d. Malformed input does not crash

Fixture `tools/apitrace/samples/malformed.log` (unterminated call, binary
bytes, bare `0x`, `0xZZZZ`, `::::::`, HTML, truncated apitrace line, plus two
well-formed lines at the end).

```
$ python3 tools/relaydiff.py wine-log tools/apitrace/samples/malformed.log
9 KERNEL32!ReadFile(arg0=0x40 -)
0009 KERNEL32!ReadFile(0x40,PTR)
EXIT=0

$ python3 tools/relaydiff.py wine-log --errors tools/apitrace/samples/malformed.log

== err:/fixme: message summary (0 distinct, 0 total) ==
# total failing calls: 0
EXIT=0

$ python3 tools/relaydiff.py diff tools/apitrace/samples/malformed.log tools/apitrace/samples/malformed.log
# A = tools/apitrace/samples/malformed.log  (2 calls)
# B = tools/apitrace/samples/malformed.log  (2 calls)

== call sequences in A not in B (0) ==
  (none)

== call sequences in B not in A (0) ==
  (none)

== per-function call counts ==
function                A       B   delta
kernel32!readfile       2       2      +0
EXIT=0
```

The only surviving "garbage" record is one deliberately malformed apitrace
line that happens to parse; it is emitted harmlessly.  A harsher fuzz test:
300,000 random lines over a punctuation-heavy alphabet, run through all three
modes:

```
$ wc -l state/tmp/fuzz.log
300000 state/tmp/fuzz.log
$ python3 tools/relaydiff.py wine-log state/tmp/fuzz.log >/dev/null;  echo "wine-log rc=$?"
wine-log rc=0
$ python3 tools/relaydiff.py wine-log --errors state/tmp/fuzz.log >/dev/null;  echo "errors rc=$?"
errors rc=0
$ python3 tools/relaydiff.py diff state/tmp/fuzz.log state/tmp/fuzz.log >/dev/null;  echo "diff rc=$?"
diff rc=0
```

No output on stderr, exit 0 in every mode.

### e. Streaming check on a large synthesised file

`state/tmp/big_relay.log` was synthesised by concatenating
`tools/apitrace/samples/relay_a.log` (1.4 KB, 15 lines) 1,818,669 times:

```
$ python3 ... (generator)
wrote /home/asdf/projects/resolume-wine/state/tmp/big_relay.log: 2684355444 bytes (2.50 GiB) from 1818669 blocks in 2.1s
```

Peak RSS stays flat as the input grows from 100 MB to 2.5 GiB, which is the
streaming property:

```
$ /usr/bin/time -v python3 tools/relaydiff.py wine-log state/tmp/slice100m.log >/dev/null
	Elapsed (wall clock) time (h:mm:ss or m:ss): 0:34.25
	Maximum resident set size (kbytes): 16852

$ /usr/bin/time -v python3 tools/relaydiff.py wine-log --errors state/tmp/slice100m.log >.../err100.out
	Elapsed (wall clock) time (h:mm:ss or m:ss): 0:31.90
	Maximum resident set size (kbytes): 17076
--- last lines of err100.out ---
== err:/fixme: message summary (1 distinct, 67750 total) ==
  67750  fixme:heap:RtlSetHeapInformation # # # # stub
# total failing calls: 67750

$ /usr/bin/time -v python3 tools/relaydiff.py wine-log state/tmp/big_relay.log >/dev/null
	Elapsed (wall clock) time (h:mm:ss or m:ss): 16:10.22
	Maximum resident set size (kbytes): 17112
```

The plain 2.5 GiB run peaks at the same ~17 MB as the 100 MB run: the whole
file is never resident.  (Throughput is roughly 3 MB/s because every argument
is regex-normalised; that is an offline analysis tool, not a hot path.)

The large file and its slice were deleted afterwards:

```
$ rm -f state/tmp/big_relay.log state/tmp/slice100m.log
$ ls state/tmp/big_relay.log state/tmp/slice100m.log 2>&1
ls: cannot access 'state/tmp/big_relay.log': No such file or directory
ls: cannot access 'state/tmp/slice100m.log': No such file or directory
```

(The 300,000-line fuzz log and the `/usr/bin/time` scratch reports were also
removed from `state/tmp/`; other files there belong to sibling agents and were
left untouched.)

## Fixtures kept

`tools/apitrace/samples/`:

* `relay_a.log`, `apitrace_a.log` — the original cross-format pair.
* `diff_a.log`, `diff_b.log` — 3-way differing pair for the `diff` test.
* `hex_a.log`, `hex_b.log` — `0x` vs bare-hex canonicalisation pair.
* `malformed.log` — garbage-line hardening fixture.

## Suggested checks for the integrator

* `python3 tools/relaydiff.py wine-log --tail 200 --modules kernel32,ntdll <real relay log>`
  against the Arena crash/hang tail.
* `python3 tools/relaydiff.py diff <wine relay log> <apitrace log>` and read the
  A-not-B section as "calls Wine did not make / got wrong".

## Performance note

Normalisation is regex-bound at roughly 3 MB/s single-threaded (~16 min for a
2.5 GiB relay log).  That is acceptable for offline analysis; if it ever needs
to be faster, cache canonicalisations of repeated argument strings (the big
benchmark had ~1.8M identical blocks) or skip `+relay` args with a cheaper
split.

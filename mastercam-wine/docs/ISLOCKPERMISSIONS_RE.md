# `ISLockPermissionsInstall` — root cause of `E_NOINTERFACE` (0x80004002)

Target: `Mastercam_Installer.msi` custom action
`[...\Flags|Registry|...|Everyone|983103|...]ISLockPermissionsInstall`

**Verdict (one line).** The CA is fine. The failing symbol is the COM class factory for
**`PSDispatch`, `CLSID_PSDispatch = {00020420-0000-0000-C000-000000000046}`** — the OLE Automation
proxy/stub factory implemented by **`oleaut32`** (`dlls/oleaut32/oleaut.c:1182`
`DllGetClassObject` → `OLEAUTPS_DllGetClassObject`, generated from
`dlls/oleaut32/oleaut32_ocidl.idl:56`). In the **64-bit helper process** Wine's
`marshal_object()` cannot create it because the **64-bit registry view is missing
`HKCR\CLSID\{00020420-...}`** (the key existed only under `Wow6432Node`), so Wine returns
`E_NOINTERFACE`, which is what the CA reports. Wine code to fix:
`dlls/combase/marshal.c:marshal_object()`/`get_ps_clsid()` and
`dlls/combase/combase.c:com_get_class_object()` (no built-in fallback for the Automation PS
classes), plus the 64-bit-view registration of oleaut32's PS coclasses
(`loader/wine.inf.in [RegisterDllsSection]` / `programs/wineboot/wineboot.c:update_prefix()`).

---

## 1. Artefacts

Extracted from the MSI `Binary` table (`7z x Mastercam_Installer.msi 'Binary.ISLockPermissions.dll' …`):

| stream | file | size | sha256 |
|---|---|---|---|
| `Binary.ISLockPermissions.dll` | `ISLockPermissions.dll` | 869 720 | `9f6088540e20d8e180eb7d40505ac4c2202b704966208a3cd4bc1dc4b47bb25d` |
| (embedded in `.rsrc` at file off `0x942c8` +) | `ISBEW64_x64.exe` — *"InstallShield (R) 64-bit Setup Engine"*, PE32+ AMD64, `CHARACTERISTICS 0x22` (**EXE**, not DLL) | 262 800 | `b29cb5406178c799b30955767cd5a58d3dce194e3caf4f6a464d81166aa96d2f` |

`ISLockPermissions.dll` is **PE32 / i386** (exports `ISLockPermissionsCostAction`,
`ISLockPermissionsInstallAction`). It links no 64-bit code; the x64 helper is a resource
(`FindResourceW(L"ISBEW64EXE")` → `"Extracted ISBEW64.exe to '%s'"`, UTF-16 strings at
`0x100771f4` / `0x1007720c`). The helper extracted by `ISSetup.dll`'s support-file mechanism is
called `ISBEWX64.exe` and lands as `%TEMP%\{…}\_isA774.exe` (see the trace in §4).

Reproduction scratch (NTFS, no `/` cost):

```sh
D=/run/media/asdf/Windows/mc-scratch/dll
7z x -o$D Mastercam_Installer.msi 'Binary.ISLockPermissions.dll'
python3 -c "d=open('$D/Binary.ISLockPermissions.dll','rb').read(); open('$D/ISBEW64_x64.exe','wb').write(d[0x942c8:])"
G=/run/media/asdf/Windows/mc-scratch/ghidra/ghidra_12.1.4_PUBLIC
"$G/support/analyzeHeadless" /run/media/asdf/Windows/mc-scratch/ghidra-proj mcx \
    -import $D/Binary.ISLockPermissions.dll \
    -scriptPath /run/media/asdf/Windows/mc-scratch/ghidra-scripts \
    -postScript McDecomp.java "64-bit helper|64-bit util helper|64-bit permissions|apply permissions|Error creating instance" \
                                "CoCreateInstance|CoGetClassObject|CoLoadLibrary|CLSIDFromProgID|GetRunningObjectTable|CreateItemMoniker" 30000
```

Build metadata confirms provenance:
`C:\CodeBases\isdev\Redist\Language Independent\i386\IsLockPermissions.pdb` and
`C:\CodeBases\isdev\Src\Runtime\InstallScript\ISBEW64\x64\Release\ISBEW64.pdb`.
C++ RTTI in both DLLs: `CComObject<C64BitUtilsHelper>`, `CComCoClass<CISBEW64Utils, &CLSID_ISBEW64Utils>`,
`IDispatchImpl<IISBEW64Utils, &IID_IISBEW64Utils, &LIBID_ISENG64Lib, …>`, and
`C:\CodeBases\isdev\Src\inc\CoCreate.cpp`.

## 2. Decompiled control flow (32-bit `ISLockPermissions.dll`)

Ghidra 12.1.4 headless (`analyzeHeadless mcx -import Binary.ISLockPermissions.dll`,
script `McDecomp.java` matching the helper error strings and `CoCreateInstance|CoLoadLibrary|…`).

| addr | role |
|---|---|
| `FUN_1000c270` | iterates the `ISLockPermissions` rows; reports `"Failed to apply permissions for object '%s', error 0x%08x"` (`0x10076e50`) |
| `FUN_10009930` | `C64BitUtilsHelper::Get/Init` — checks 64-bit OS (`FUN_10023c60`), else logs `"Attempting to set 64-bit permissions on a non-64bit machine"` (`0x10077020`) and returns `0x80070032` |
| `FUN_10008c50` | `new CComObject<C64BitUtilsHelper>` (vtable `0x10076fc4`, RTTI COL → `CComObject<C64BitUtilsHelper>`); on failure → `"Error creating instance of 64-bit util helper: %x"` (`0x10077098`) |
| `FUN_10002c30` | thunk: calls `FUN_10003760` with `rclsid=0x10076484`, `riid=0x1007b0b0`, `ppv=&this+8`, `GUID=NULL`; **its HRESULT is the one reported as `"Failed to initialize 64-bit helper, error %x"` (`0x10077100`)** |
| `FUN_10003760` | the real handshake (below) |
| `FUN_10003b70` | `CoCreate.cpp` loader: `GetModuleHandleW`→`LoadLibraryW("%s\\%s")`→`CoLoadLibrary`→`GetProcAddress(h,"DllGetClassObject")` |
| `FUN_1000eb80` | per-item work: `"Failed to obtain 64-bit helper process for permission item '%s', error '%x'"` (`0x10077750`), `"Processing registry object '%s' in 64-bit outproc"` |

`FUN_10003760` reconstructed from the decompiler (arguments: `name`, `rclsid`, `riid`, `ppv`, `GUID*`):

```c
wsprintfW(cmdline, L"%s %s:%s", name, CLSID_string_upper, GUID_string_upper);
if (GUID == NULL) {                 /* launcher side */
    CoCreateGuid(&guid);
    CreateProcessW(NULL, cmdline, …, &si, &pi);   /* ISBEW64.exe <CLSID>:<GUID> */
    WaitForInputIdle(pi.hProcess, 20000); CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
}
for (i = 100; i--; ) {              /* poll the ROT for 100 x 300 ms */
    CreateItemMoniker(L"!", GUID_string, &moniker);
    GetRunningObjectTable(0, &rot);
    if (SUCCEEDED(rot->lpVtbl->GetObject(rot, moniker, &punk)))
        { hr = punk->lpVtbl->QueryInterface(punk, riid, ppv); break; }   /* <<< E_NOINTERFACE */
    Sleep(300);
}
```

So the "64-bit helper" is **not** a `CoCreateInstance` local server: the CA spawns
`ISBEW64.exe` with `CreateProcessW`, the helper registers itself in the **Running Object Table**
under the item moniker `!{GUID}`, and the CA unmarshals it and **`QueryInterface`s it for
`riid`**. The only `CoCreateInstance` calls in this DLL are ATL's GlobalInterfaceTable
(`{00000323-…}`) and mlang (`CLSID_CMultiLanguage {275C23E2-…}` / `IID_IMultiLanguage {275C23E1-…}`).

GUIDs recovered from `.rdata`:

* `param_2` (`0x10076484`) = `{EFB7539B-24F3-46B6-AF6E-3B021B51EFEF}`
  → `CLSID_ISBEW64Utils` (matches the RTTI symbol and the `CreateProcessW` command line in the trace).
* `param_3` (`0x1007b0b0`) = `{00020400-0000-0000-C000-000000000046}` = **`IID_IDispatch`**.

## 3. Wine side — what actually returns `E_NOINTERFACE`

Wine debug log `logs/exp/mcinstall/winedbg_min_trace.log` (`WINEDEBUG=+ole,+msi,+process`), pid `013c` =
i386 `msiexec`, pid `0154…` = the extracted 64-bit helper:

```
32401 …:013c:trace:process:CreateProcessInternalW app (null)
      cmdline L"C:\users\asdf\AppData\Local\Temp\{AF345415-…}\_isA774.exe {EFB7539B-24F3-46B6-AF6E-3B021B51EFEF}:{CE8495E2-683C-428E-9EB1-5AAC22E4D125}"
32724 013c:trace:ole:CoUnmarshalInterface 009A7088, {00000000-0000-0000-c000-000000000046}, 00F0EB38
32883 013c:trace:ole:CoUnmarshalInterface completed with hr 0
33007 0154:trace:ole:NdrBaseTypeMarshall value: 0x80004002
33064 013c:warn:ole:ClientIdentity_QueryMultipleInterfaces IRemUnknown_RemQueryInterface failed with error 0x80004002
```

Inside the **64-bit** helper process (`0154`) the failing sequence is:

```
221686.990:0154:trace:ole:Rundown_RemQueryInterface … {00000001-0154-0150-…}
221686.990:0154:trace:ole:CoGetPSClsid {00020400-0000-0000-c000-000000000046}, …
221686.992:0154:trace:ole:guid_from_string L"{00020420-0000-0000-C000-000000000046}" -> …
221686.992:0154:trace:ole:CoGetPSClsid () Returning CLSID {00020420-0000-0000-C000-000000000046}
221686.992:0154:trace:ole:CoGetClassObject {00020420-0000-0000-C000-000000000046}, 0x80000001, {d5f569d0-593b-101a-b569-08002b2dbf7a}
221686.993:0154:err:ole:com_get_class_object class {00020420-0000-0000-c000-000000000046} not registered
221686.993:0154:err:ole:com_get_class_object no class object {00020420-0000-0000-c000-000000000046} could be created for context 0x80000001
221686.993:0154:warn:ole:marshal_object couldn't get IPSFactory buffer for interface {00020400-0000-0000-c000-000000000046}
221686.993:0154:trace:ole:NdrBaseTypeMarshall value: 0x80004002        <-- E_NOINTERFACE
```

Call chain mapped onto Wine 11.18 (`wine-11.18/`):

| trace line | Wine source |
|---|---|
| `Rundown_RemQueryInterface` | `dlls/combase/stubmanager.c:707` |
| `CoGetPSClsid` (reads `HKCR\Interface\{IID}\ProxyStubClsid32`) | `dlls/combase/combase.c` (`CoGetPSClsid`) |
| `CoGetClassObject(…, CLSCTX_INPROC_SERVER|CLSCTX_PS_DLL=0x80000001, IID_IPSFactoryBuffer)` | `dlls/combase/marshal.c:855` (`get_ps_clsid()`), **`0x80000001` = `CLSCTX_INPROC_SERVER|CLSCTX_PS_DLL`** |
| `err:ole:com_get_class_object class … not registered` | `dlls/combase/combase.c:1806` / `:1841` (`com_get_class_object`) |
| `marshal_object couldn't get IPSFactory buffer for interface {00020400-…}` → `E_NOINTERFACE` | `dlls/combase/marshal.c:862` `marshal_object()`, WARN at `:907` |
| client-side `ClientIdentity_QueryMultipleInterfaces` → `IRemUnknown_RemQueryInterface failed with error 0x80004002` | `dlls/combase/marshal.c:990`, `:1043` |
| ROT fetch (`CreateItemMoniker`/`GetRunningObjectTable`/`GetObject`) | `dlls/ole32/moniker.c:407` (`InternalIrotRegister`), `:~546` `RunningObjectTableImpl_GetObject`, `:561` (`InternalIrotGetObject`) |
| factory that should have been found | `dlls/oleaut32/oleaut.c:1182` (`DllGetClassObject` → `CLSID_PSDispatch`/`CLSID_PSOAInterface`), `:1209` (`DllRegisterServer` → `OLEAUTPS_DllRegisterServer`), classes declared in `dlls/oleaut32/oleaut32_ocidl.idl:56` |

**The exact Wine symbol that returns `E_NOINTERFACE` is `com_get_class_object()`'s
`CLSID_PSDispatch` class-object creation** (`dlls/combase/combase.c:1806`, requested from
`marshal_object()`/`get_ps_clsid()` in `dlls/combase/marshal.c:855`). It fails because the
64-bit view of `HKCR\CLSID\{00020420-0000-0000-C000-000000000046}` is absent, so Wine cannot see
the factory that `oleaut32` implements.

## 4. Why the key was absent — registry evidence

Prefix `state/exp/mcinstall/prefix/system.reg`. Immediately after the failing runs
(11:19) the key set was:

```
[Software\Classes\CLSID\{00020420-…}]                       <-- ABSENT
[Software\Classes\Interface\{00020400-…}\ProxyStubClsid32]  @="{00020420-…}"   (present)
[Software\Classes\Wow6432Node\CLSID\{00020420-…}]
    @="PSDispatch" , InprocServer32 = C:\windows\system32\oleaut32.dll , ThreadingModel=Both
```

i.e. the 32-bit view had the class, the 64-bit view had the *interface → PS CLSID* mapping but
**not the CLSID 64-bit registration**. That asymmetry is exactly what the trace shows
(`CoGetPSClsid` succeeds, `CoGetClassObject` says "not registered").

Sibling prefixes created ~1 min earlier by the same tooling are complete:

| prefix | `CLSID\{00020420}` native | Wow6432Node |
|---|---|---|
| `DotnetProbe` (10:55:58 / 10:56:33) | present | present |
| `CodeMeterProbe` | present | present |
| `mcinstall` (created 10:57:40) | **missing at failure time**; appeared 11:22:19 | present (10:57:40) |

The native key re-appeared **after** a later prefix update (registry mtime 11:22:19, i.e. minutes
after the failing run). Wine only writes these keys by calling
`oleaut32!DllRegisterServer` → `OLEAUTPS_DllRegisterServer()` (widl output of
`oleaut32_ocidl.idl`) in a process of the matching bitness; the registration pass is driven by
`[RegisterDllsSection]` in `loader/wine.inf.in` via
`dlls/setupapi/install.c:register_dlls_callback()`/`do_register_dll()` (`FLG_REGSVR_DLLREGISTER = 0x1`),
started from `programs/wineboot/wineboot.c:update_prefix()` → `start_rundll32(inf, L"DefaultInstall",
IMAGE_FILE_MACHINE_TARGET_HOST)` for 64-bit and `L"Wow64Install"` for the 32-bit view.
**`oleaut32.dll` is not listed in `[RegisterDllsSection]`** (verified in both
`loader/wine.inf.in` and the generated `wine/wine-11.18/loader/wine.inf`), so nothing guarantees
the 64-bit view gets these keys — a prefix whose 64-bit registration pass is partial/skipped
silently loses the Automation proxy/stub factories.

## 5. Proposed change

**Immediate (environment, fixes this install run).** Make sure the 64-bit view has the PS
factories before running the MSI, i.e. force the prefix update with the 64-bit `wineboot`
(or query first):

```sh
$WINEBUILD wineboot -u                       # re-runs DefaultInstall (64-bit) + WowInstall
"$WINEBUILD" reg query 'HKCR\CLSID\{00020420-0000-0000-C000-000000000046}'
```

This is confirmed to reproduce the needed key: the prefix update at 11:22:19 created it, whereas
the failing runs (11:08 and 11:15) ran without it.

**Permanent (Wine).** The minimal change that removes the failure mode outright is (A);
(B) is the belt-and-braces variant to use if the prefix-registration path must stay untouched.

**A. Do not depend on the registry for the built-in Automation PS classes.**
In `dlls/combase/combase.c`, `com_get_class_object()` already special-cases built-in classes
(`CLSID_InProcFreeMarshaler`, `CLSID_GlobalOptions`, `CLSID_ManualResetEvent`,
`CLSID_StdGlobalInterfaceTable` → `Ole32DllGetClassObject`). Extend that block: when
`clscontext & CLSCTX_PS_DLL` and `rclsid` is one of the standard Automation PS CLSIDs
(`CLSID_PSDispatch {00020420-…}`, `PSEnumVariant {00020421-…}`, `PSTypeInfo {00020422-…}`,
`PSTypeLib {00020423-…}`, `PSOAInterface {00020424-…}`, `PSTypeComp {00020425-…}`,
`PSSupportErrorInfo {df0b3d60-…}`, `CLSID_RecordInfo {0000002f-…}` — declared in
`dlls/oleaut32/oleaut32_ocidl.idl`), route the request to the built-in `oleaut32` factory
(`LoadLibraryW(L"oleaut32.dll")` + `DllGetClassObject`, as done for the built-ins above) instead of
returning `E_NOINTERFACE` (`dlls/combase/combase.c:1806`). Then `marshal_object()` /
`get_ps_clsid()` (`dlls/combase/marshal.c:855-907`) always obtain an `IPSFactoryBuffer` for
`IID_IDispatch` and `Rundown_RemQueryInterface` returns an interface pointer instead of
`0x80004002`. This is confined to one function and cannot regress registered classes.

**B. Guarantee both regviews get the keys at prefix creation.** Add oleaut32 to the
prefix-time registration list so `oleaut32!DllRegisterServer`
(`dlls/oleaut32/oleaut.c:1209` → `OLEAUTPS_DllRegisterServer()`, widl output of
`dlls/oleaut32/oleaut32_ocidl.idl`) runs in **both** the `DefaultInstall` (native/64-bit) and
`Wow64Install` (32-bit) passes of `programs/wineboot/wineboot.c:update_prefix()`
(`dlls/setupapi/install.c:register_dlls_callback()` / `do_register_dll()`,
`FLG_REGSVR_DLLREGISTER = 0x1`):

`loader/wine.inf.in`, `[RegisterDllsSection]`, add
```
11,,oleaut32.dll,1
```
This is the change that matches Windows (where the Automation PS factories are registered in both
regviews). Caveat: `[RegisterDllsSection]` in `loader/wine.inf.in` does **not** list oleaut32 today,
and the 32-bit view nevertheless had the keys, so the exact path that currently writes them in this
tree was not positively identified; patch B should therefore be treated as "make it explicit and
bidirectional" and validated with the §6 registry check rather than assumed sufficient on its own.

## 6. Verification

* Reproduce the failing action with `WINEDEBUG=+ole` and confirm the absence/presence of
  `err:ole:com_get_class_object class {00020420-…} not registered` in the 64-bit helper process
  (pid whose addresses are `0x7F…`).
* After the fix, expect in the CA path: no `marshal_object couldn't get IPS factory buffer for
  interface {00020400-…}`, `ClientIdentity_QueryMultipleInterfaces 1/1 successfully queried`, and
  the CA to return 1 — i.e. the install log no longer shows
  `[...|Registry|…]ISLockPermissionsInstall returned 1603`; the `InstallFinalize` action proceeds.
* Registry check inside the prefix (must be non-empty):
  `wine reg query 'HKCR\CLSID\{00020420-0000-0000-C000-000000000046}'` executed from a **64-bit**
  process, and the same under `HKCR\Wow6432Node\CLSID\{00020420-…}` from a 32-bit one.

## 7. Notes / limits

* Proven: CA control flow and GUIDs (static + decompiler), the exact Wine calls that produce
  0x80004002 (live `+ole` trace), and the registry asymmetry (prefix `system.reg`).
* Proven: `oleaut32` implements `CLSID_PSDispatch` and `wine.inf` does not list `oleaut32.dll` in
  `[RegisterDllsSection]`.
* [INFERENCE] The precise *reason the 64-bit registration pass was incomplete only in the
  `mcinstall` prefix* (prefix creation ordering / a skipped or partial `DefaultInstall` run) is not
  fully determined; the sibling prefixes are complete. This does not change the verdict — the CA
  fails exactly when that key is missing, and it proceeds once it exists.

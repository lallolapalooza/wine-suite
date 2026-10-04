/*
 * roprobe - black-box behaviour probe for the Windows Runtime metadata resolution APIs that .NET Framework
 * uses to bind WinRT types: the same binary runs on Windows (the reference) and under Wine (our
 * implementation) and the two outputs are compared line by line.
 *
 * Why this exists: Power BI's StoragePropertiesProvider type initialiser asks .NET for
 * Windows.Storage.StorageFile, .NET asks the OS where that type's metadata lives, and under Wine the answer was
 * "nowhere". Instead of trusting our reading of Wine's source, this measures the real contract: which .winmd
 * file each namespace/typename resolves to, what TypeDef token comes back, and which HRESULT each documented
 * edge case returns (empty name, trailing dot, leading dot, a namespace instead of a typename, an unknown
 * typename).
 *
 * HRESULTs are printed as raw hex on purpose. Their *names* differ between platforms in Wine's tables and the
 * numeric values are what a caller compares, so the hex is the datum; the doc-derived names are only a legend
 * printed at the top for the reader.
 *
 * Everything is resolved with GetProcAddress: mingw-w64's import libraries need not carry these exports, and a
 * dynamic load also lets the probe report *which DLL answered* - which is the thing worth knowing when the same
 * name lives in WinTypes.dll on Windows (verified: MS docs list `WinTypes.dll`) and in wintypes.dll under Wine.
 *
 * usage: roprobe.exe [logfile]
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <unknwn.h>
#include <stdio.h>
#include <stdarg.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

typedef void *HSTRING_HANDLE;
#define MDTYPEDEF_NIL 0x02000000

typedef HRESULT (WINAPI *pWindowsCreateString)(const WCHAR *, UINT32, HSTRING_HANDLE *);
typedef const WCHAR *(WINAPI *pWindowsGetStringRawBuffer)(HSTRING_HANDLE, UINT32 *);
typedef HRESULT (WINAPI *pWindowsDeleteString)(HSTRING_HANDLE);
typedef HRESULT (WINAPI *pRoResolveNamespace)(HSTRING_HANDLE, HSTRING_HANDLE, DWORD, const HSTRING_HANDLE *,
                                              DWORD *, HSTRING_HANDLE **, DWORD *, HSTRING_HANDLE **);
typedef HRESULT (WINAPI *pRoGetMetaDataFile)(HSTRING_HANDLE, void *, HSTRING_HANDLE *, void **, UINT32 *);
typedef LONG (WINAPI *pRtlGetVersion)(PRTL_OSVERSIONINFOW);

static FILE *g_log;

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    if (g_log) vfprintf(g_log, fmt, ap);
    va_end(ap);
    fflush(stdout);
    if (g_log) fflush(g_log);
}

static HSTRING_HANDLE mkstr(pWindowsCreateString create, const WCHAR *s)
{
    HSTRING_HANDLE h = NULL;
    if (!create) return NULL;
    if (FAILED(create(s, (UINT32)wcslen(s), &h))) return NULL;
    return h;
}

static void print_strings(pWindowsGetStringRawBuffer raw, HSTRING_HANDLE *arr, DWORD count, const char *label)
{
    DWORD i;
    say("    %s: %lu\n", label, count);
    for (i = 0; i < count && i < 12; i++)
    {
        const WCHAR *s = (raw && arr) ? raw(arr[i], NULL) : NULL;
        say("      [%lu] %ls\n", i, s ? s : L"(null)");
    }
    if (count > 12) say("      ... %lu more\n", count - 12);
}

int main(int argc, char **argv)
{
    HMODULE res_mod = NULL, str_mod = NULL;
    pWindowsCreateString create = NULL;
    pWindowsGetStringRawBuffer raw = NULL;
    pWindowsDeleteString del = NULL;
    pRoResolveNamespace resolve = NULL;
    pRoGetMetaDataFile getfile = NULL;
    static const WCHAR *const mod_names[] = {
        L"api-ms-win-ro-typeresolution-l1-1-1.dll",
        L"api-ms-win-ro-typeresolution-l1-1-0.dll",
        L"ext-ms-win-ro-typeresolution-l1-1-0.dll",
        L"WinTypes.dll",
        L"wintypes.dll",
    };
    static const WCHAR *const str_mod_names[] = {
        L"api-ms-win-core-winrt-string-l1-1-0.dll",
        L"combase.dll",
        L"WinTypes.dll",
    };
    RTL_OSVERSIONINFOW vi;
    pRtlGetVersion rtlver;
    char mod_path[MAX_PATH];
    unsigned int i;

    if (argc > 1) g_log = fopen(argv[1], "w");

    say("roprobe: Windows Runtime metadata resolution, measured\n");
    memset(&vi, 0, sizeof(vi));
    vi.dwOSVersionInfoSize = sizeof(vi);
    rtlver = (pRtlGetVersion)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion");
    if (rtlver && rtlver(&vi) == 0)
        say("  os: %lu.%lu build %lu\n", vi.dwMajorVersion, vi.dwMinorVersion, vi.dwBuildNumber);
    say("  legend: 0x80073b17=RO_E_METADATA_NAME_NOT_FOUND 0x80073b18=RO_E_METADATA_NAME_IS_NAMESPACE "
        "0x80070057=E_INVALIDARG 0x00000000=S_OK\n");

    for (i = 0; i < ARRAY_SIZE(mod_names) && !res_mod; i++)
    {
        res_mod = LoadLibraryW(mod_names[i]);
        if (res_mod)
        {
            GetModuleFileNameA(res_mod, mod_path, sizeof(mod_path));
            say("  module: %ls -> %s\n", mod_names[i], mod_path);
        }
    }
    for (i = 0; i < ARRAY_SIZE(str_mod_names) && !str_mod; i++)
        str_mod = LoadLibraryW(str_mod_names[i]);

    if (!res_mod) { say("  FATAL: no type-resolution module could be loaded\n"); return 2; }
    create = (pWindowsCreateString)GetProcAddress(str_mod ? str_mod : res_mod, "WindowsCreateString");
    raw = (pWindowsGetStringRawBuffer)GetProcAddress(str_mod ? str_mod : res_mod, "WindowsGetStringRawBuffer");
    del = (pWindowsDeleteString)GetProcAddress(str_mod ? str_mod : res_mod, "WindowsDeleteString");
    resolve = (pRoResolveNamespace)GetProcAddress(res_mod, "RoResolveNamespace");
    getfile = (pRoGetMetaDataFile)GetProcAddress(res_mod, "RoGetMetaDataFile");
    say("  exports: RoResolveNamespace=%s RoGetMetaDataFile=%s WindowsCreateString=%s\n",
        resolve ? "yes" : "NO", getfile ? "yes" : "NO", create ? "yes" : "NO");
    if (!resolve || !getfile || !create || !raw) { say("  FATAL: required exports missing\n"); return 2; }

    /* ---- RoResolveNamespace ---------------------------------------------------------------- */
    {
        static const WCHAR *const names[] = { L"Windows.Storage", L"Windows.Foundation", L"Windows", L"" };
        for (i = 0; i < ARRAY_SIZE(names); i++)
        {
            HSTRING_HANDLE nm = mkstr(create, names[i]);
            DWORD files_count = 0, subs_count = 0;
            HSTRING_HANDLE *files = NULL, *subs = NULL;
            HRESULT hr = resolve(nm, NULL, 0, NULL, &files_count, &files, &subs_count, &subs);
            say("RoResolveNamespace(\"%ls\") -> hr=0x%08x\n", names[i], (unsigned int)hr);
            if (SUCCEEDED(hr))
            {
                print_strings(raw, files, files_count, "metadata files");
                print_strings(raw, subs, subs_count, "sub-namespaces");
            }
            if (nm) del(nm);
        }
    }

    /* ---- RoGetMetaDataFile ------------------------------------------------------------------ */
    {
        static const WCHAR *const types[] = {
            L"Windows.Storage.StorageFile",
            L"Windows.Storage.StorageFolder",
            L"Windows.Storage.FileProperties.BasicProperties",
            L"Windows.Foundation.Metadata.ApiInformation",
            L"Windows.Storage",              /* namespace, not a typename */
            L"Windows.Nonexistent.Type",     /* unknown typename        */
            L"",                             /* empty                   */
            L"Windows.Storage.",             /* trailing dot            */
            L".StorageFile",                 /* leading dot             */
        };
        for (i = 0; i < ARRAY_SIZE(types); i++)
        {
            HSTRING_HANDLE nm = mkstr(create, types[i]);
            HSTRING_HANDLE path = NULL;
            void *import = NULL;
            UINT32 token = 0;
            HRESULT hr = getfile(nm, NULL, &path, &import, &token);
            const WCHAR *p = path ? raw(path, NULL) : NULL;
            say("RoGetMetaDataFile(\"%ls\") -> hr=0x%08x path=%ls token=0x%08x import=%s\n",
                types[i], (unsigned int)hr, p ? p : L"(null)", token, import ? "set" : "null");
            if (FAILED(hr) && (path || import || token != MDTYPEDEF_NIL))
                say("    NOTE: outputs not reset on failure (spec: nullptr / mdTypeDefNil)\n");
            if (path) del(path);
            if (import) ((IUnknown *)import)->lpVtbl->Release((IUnknown *)import);
            if (nm) del(nm);
        }
    }

    say("roprobe: done\n");
    if (g_log) fclose(g_log);
    return 0;
}

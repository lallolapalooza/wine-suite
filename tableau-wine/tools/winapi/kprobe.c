/*
 * kprobe.c — the small set of kernel32/ole32 probes Power BI's MSOLAP provider runs while it initialises,
 * measured the same way on both platforms so the two behaviours can be diffed instead of guessed (same method as
 * tools/winapi/roprobe.c / glpie.exe / tokprobe.exe).
 *
 * The calls and their order come from WINEDEBUG=+relay on the provider's own module-init path
 * (`RelayFromInclude=msolap.dll`): the provider probes GetLogicalProcessorInformationEx for a size, calls
 * GetNumaProcessorNodeEx/HeapSetInformation/GetComputerNameExW/GetProcessAffinityMask/GlobalMemoryStatusEx, and
 * reads GetLastError() at msolap.dll+0xb9c67 and +0x107066 — so what those calls leave in the last error is part
 * of the contract it observes.  Each call is preceded by SetLastError(0) so the value printed afterwards is
 * attributable to that call rather than to a previous one.
 *
 * Build: x86_64-w64-mingw32-gcc -O1 -o bin/kprobe.exe kprobe.c -lole32 -ladvapi32
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdio.h>
#include <stdlib.h>

typedef BOOL (WINAPI *pGetLogicalProcessorInformationEx)(LOGICAL_PROCESSOR_RELATIONSHIP, void *, PDWORD);
typedef BOOL (WINAPI *pHeapSetInformation)(HANDLE, HEAP_INFORMATION_CLASS, PVOID, SIZE_T);
typedef BOOL (WINAPI *pGetComputerNameExW)(COMPUTER_NAME_FORMAT, LPWSTR, LPDWORD);
typedef BOOL (WINAPI *pGetNumaProcessorNodeEx)(PPROCESSOR_NUMBER, PUSHORT);
typedef BOOL (WINAPI *pGetProcessAffinityMask)(HANDLE, PDWORD_PTR, PDWORD_PTR);
typedef BOOL (WINAPI *pGlobalMemoryStatusEx)(LPMEMORYSTATUSEX);
typedef int  (WINAPI *pGetUserDefaultLocaleName)(LPWSTR, int);

static void row(const char *api, long long ok, long long value)
{
    DWORD err = GetLastError();      /* read before printf so nothing else can disturb it */
    printf("  %-34s ok=%-6lld value=%-12lld lastError=%lu\n", api, ok, value, (unsigned long)err);
    fflush(stdout);
}

int main(void)
{
    HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
    pGetLogicalProcessorInformationEx glpie = (void *)GetProcAddress(k32, "GetLogicalProcessorInformationEx");
    pHeapSetInformation hsi = (void *)GetProcAddress(k32, "HeapSetInformation");
    pGetComputerNameExW gcne = (void *)GetProcAddress(k32, "GetComputerNameExW");
    pGetNumaProcessorNodeEx gnpe = (void *)GetProcAddress(k32, "GetNumaProcessorNodeEx");
    pGetProcessAffinityMask gpam = (void *)GetProcAddress(k32, "GetProcessAffinityMask");
    pGlobalMemoryStatusEx gms = (void *)GetProcAddress(k32, "GlobalMemoryStatusEx");
    pGetUserDefaultLocaleName gudln = (void *)GetProcAddress(k32, "GetUserDefaultLocaleName");
    /* Called directly (the import the provider uses): Wine resolves `CLSIDFromProgID` through combase, so
     * GetProcAddress on ole32 is not the same lookup on both platforms. */
    BOOL ok;
    DWORD len;
    DWORD_PTR mask = 0, sysmask = 0;
    WCHAR name[256], loc[LOCALE_NAME_MAX_LENGTH];
    USHORT node = 0xFFFF;
    PROCESSOR_NUMBER pn;
    MEMORYSTATUSEX ms;
    CLSID clsid;
    const WCHAR *progids[] = { L"MSOLAP.2", L"MSOLAP.8", L"MSOLAP", L"MSOLAP.5" };
    unsigned i;

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("kernel32/ole32 probes on the MSOLAP provider's module-init path (value = the call's out parameter)\n");

    /* 1. the size probe the provider requires to fail with exactly 122 */
    len = 0;
    SetLastError(0);
    ok = glpie ? glpie(RelationAll, NULL, &len) : -1;
    {   DWORD err = GetLastError(); DWORD n = len;
        printf("  %-34s ok=%-6d value=%-12lu lastError=%lu\n", "GetLogicalProcessorInformationEx(NULL)", ok, n, err); }
    if (glpie && len) {
        void *buf = malloc(len);
        SetLastError(0);
        ok = glpie(RelationAll, buf, &len);
        row("GetLogicalProcessorInformationEx(buf)", ok, len);
        free(buf);
    }

    /* 2. msolap reads GetLastError() right after these two (msolap+0x107066) */
    memset(&pn, 0, sizeof pn);
    SetLastError(0);
    ok = gnpe ? gnpe(&pn, &node) : -1;
    row("GetNumaProcessorNodeEx", ok, node);
    SetLastError(0);
    ok = hsi ? hsi(GetProcessHeap(), HeapEnableTerminationOnCorruption, NULL, 0) : -1;
    row("HeapSetInformation(class 1)", ok, 0);

    /* 3. the name/locale/affinity probes from the same path */
    len = 0;
    SetLastError(0);
    ok = gcne ? gcne(ComputerNameDnsHostname, NULL, &len) : -1;
    row("GetComputerNameExW(NULL,0)", ok, len);
    if (gcne) {
        len = 256; name[0] = 0;
        SetLastError(0);
        ok = gcne(ComputerNameDnsHostname, name, &len);
        row("GetComputerNameExW(buf)", ok, len);
    }
    memset(loc, 0, sizeof loc);
    SetLastError(0);
    ok = gudln ? gudln(loc, LOCALE_NAME_MAX_LENGTH) : -1;
    row("GetUserDefaultLocaleName", ok, 0);
    SetLastError(0);
    ok = gpam ? gpam(GetCurrentProcess(), &mask, &sysmask) : -1;
    row("GetProcessAffinityMask", ok, mask);
    memset(&ms, 0, sizeof ms); ms.dwLength = sizeof ms;
    SetLastError(0);
    ok = gms ? gms(&ms) : -1;
    row("GlobalMemoryStatusEx", ok, (long long)ms.ullTotalPhys);

    /* 4. the ProgID lookup the provider performs while it formats its error */
    for (i = 0; i < sizeof progids / sizeof progids[0]; i++) {
        char line[64];
        HRESULT hr;
        sprintf(line, "CLSIDFromProgID(%ls)", progids[i]);
        memset(&clsid, 0, sizeof clsid);
        SetLastError(0);
        hr = CLSIDFromProgID(progids[i], &clsid);
        row(line, (long long)hr, (long long)clsid.Data1);
    }
    /* 5. and the class the provider is registered under, resolved from its string form */
    memset(&clsid, 0, sizeof clsid);
    SetLastError(0);
    row("CLSIDFromString({DBC724B0-...})", (long long)CLSIDFromString(L"{DBC724B0-DD86-4772-BB5A-FCC6CAB2FC1A}", &clsid),
        (long long)clsid.Data1);
    printf("done\n");
    return 0;
}

#include <windows.h>
#include <stdio.h>

#ifndef LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
#define LOAD_LIBRARY_SEARCH_DEFAULT_DIRS 0x00001000
#endif
#ifndef LOAD_LIBRARY_SEARCH_USER_DIRS
#define LOAD_LIBRARY_SEARCH_USER_DIRS 0x00000400
#endif

typedef BOOL (WINAPI *pAddDllDirectory)(PCWSTR, PDLL_DIRECTORY_COOKIE *);
typedef BOOL (WINAPI *pSetDefaultDllDirectories)(DWORD);
typedef DLL_DIRECTORY_COOKIE (WINAPI *pAddDllDirectory2)(PCWSTR);
typedef BOOL (WINAPI *pRemoveDllDirectory)(DLL_DIRECTORY_COOKIE);

int main(void)
{
    HMODULE k = GetModuleHandleW(L"kernel32.dll");
    pAddDllDirectory addDll = (pAddDllDirectory)GetProcAddress(k, "AddDllDirectory");
    pSetDefaultDllDirectories setDef = (pSetDefaultDllDirectories)GetProcAddress(k, "SetDefaultDllDirectories");
    HMODULE h;
    DLL_DIRECTORY_COOKIE cookie = NULL;
    WCHAR dir[512];
    DWORD len;

    printf("AddDllDirectory=%p SetDefaultDllDirectories=%p\n", (void *)addDll, (void *)setDef);

    len = GetModuleFileNameW(NULL, dir, 512);
    if (len)
    {
        WCHAR *p = wcsrchr(dir, L'\\');
        if (p) *p = 0;
    }
    wcscat(dir, L"\\VEAngle");
    printf("user dir: %ls\n", dir);

    if (addDll)
    {
        SetLastError(0);
        cookie = (DLL_DIRECTORY_COOKIE)addDll(dir, NULL);
        if (!cookie) cookie = ((pAddDllDirectory2)addDll)(dir);
        printf("AddDllDirectory -> %p err=%lu\n", (void *)cookie, GetLastError());
    }
    if (setDef)
    {
        SetLastError(0);
        printf("SetDefaultDllDirectories(USER|DEFAULT) -> %d err=%lu\n",
               setDef(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS), GetLastError());
    }

    SetLastError(0);
    h = LoadLibraryExW(L"libEGL.dll", NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
    printf("LoadLibraryExW(libEGL.dll, DEFAULT|USER) -> %p err=%lu\n", (void *)h, GetLastError());

    SetLastError(0);
    h = LoadLibraryExW(L"libGLESv2.dll", NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
    printf("LoadLibraryExW(libGLESv2.dll, DEFAULT|USER) -> %p err=%lu\n", (void *)h, GetLastError());

    SetLastError(0);
    h = LoadLibraryExW(L"VEAngle\\libEGL.dll", NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
    printf("LoadLibraryExW(VEAngle\\libEGL.dll, DEFAULT|USER) -> %p err=%lu\n", (void *)h, GetLastError());

    return 0;
}

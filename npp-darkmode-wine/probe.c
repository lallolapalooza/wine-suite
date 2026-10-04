#include <windows.h>
#include <stdio.h>

typedef void (WINAPI *fnRtlGetNtVersionNumbers)(LPDWORD,LPDWORD,LPDWORD);
typedef BOOL (WINAPI *fnAllowDarkModeForWindow)(HWND,BOOL);
typedef int  (WINAPI *fnSetPreferredAppMode)(int);
typedef BOOL (WINAPI *fnIsDarkModeAllowedForWindow)(HWND);
typedef BOOL (WINAPI *fnIsDarkModeAllowedForApp)(void);

static int g_menumsgs = 0;

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case 0x0091: printf("  >>> GOT WM_UAHDRAWMENU\n"); g_menumsgs |= 1; break;
    case 0x0092: g_menumsgs |= 2; break;
    case 0x0093: printf("  >>> GOT WM_UAHINITMENU\n"); break;
    case 0x0094: g_menumsgs |= 4; break;
    }
    return DefWindowProcW(h, m, w, l);
}

int main(void)
{
    DWORD maj=0, min=0, bld=0;
    HMODULE nt = GetModuleHandleW(L"ntdll.dll");
    fnRtlGetNtVersionNumbers f = (fnRtlGetNtVersionNumbers)GetProcAddress(nt, "RtlGetNtVersionNumbers");
    if (f) { f(&maj,&min,&bld); bld &= ~0xF0000000u; printf("RtlGetNtVersionNumbers : %lu.%lu build %lu\n", maj, min, bld); }
    else printf("RtlGetNtVersionNumbers : MISSING\n");

    HMODULE ux = LoadLibraryExW(L"uxtheme.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    printf("uxtheme loaded         : %p\n", (void*)ux);

    int ords[] = {49,104,106,133,135,136,137,138,139};
    for (int i = 0; i < 9; i++) {
        FARPROC p = GetProcAddress(ux, MAKEINTRESOURCEA(ords[i]));
        printf("uxtheme ordinal %-3d    : %p\n", ords[i], (void*)p);
    }
    printf("uxtheme name SetPreferredAppMode : %p\n", (void*)GetProcAddress(ux, "SetPreferredAppMode"));
    printf("uxtheme name AllowDarkModeForWindow : %p\n", (void*)GetProcAddress(ux, "AllowDarkModeForWindow"));

    HMODULE u32 = GetModuleHandleW(L"user32.dll");
    printf("user32 SetWindowCompositionAttribute : %p\n", (void*)GetProcAddress(u32, "SetWindowCompositionAttribute"));

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = WndProc; wc.lpszClassName = L"ProbeWnd"; wc.hInstance = GetModuleHandleW(NULL);
    RegisterClassW(&wc);
    HWND h = CreateWindowExW(0, L"ProbeWnd", L"Probe", WS_OVERLAPPEDWINDOW, 0,0,320,200, NULL,NULL,wc.hInstance,NULL);
    HMENU hm = CreateMenu(); HMENU hmf = CreatePopupMenu();
    AppendMenuW(hmf, MF_STRING, 1, L"Open");
    AppendMenuW(hm, MF_POPUP, (UINT_PTR)hmf, L"&File");
    SetMenu(h, hm);

    fnSetPreferredAppMode sp = (fnSetPreferredAppMode)GetProcAddress(ux, MAKEINTRESOURCEA(135));
    fnAllowDarkModeForWindow ad = (fnAllowDarkModeForWindow)GetProcAddress(ux, MAKEINTRESOURCEA(133));
    fnIsDarkModeAllowedForWindow idw = (fnIsDarkModeAllowedForWindow)GetProcAddress(ux, MAKEINTRESOURCEA(137));
    fnIsDarkModeAllowedForApp ida = (fnIsDarkModeAllowedForApp)GetProcAddress(ux, MAKEINTRESOURCEA(139));

    if (sp) printf("SetPreferredAppMode(2/*ForceDark*/) -> %d\n", sp(2));
    if (ad) printf("AllowDarkModeForWindow(hwnd,TRUE)   -> %d\n", ad(h, TRUE));
    if (idw) printf("IsDarkModeAllowedForWindow(hwnd)   -> %d\n", idw(h));
    if (ida) printf("IsDarkModeAllowedForApp()          -> %d\n", ida());

    ShowWindow(h, SW_SHOW); UpdateWindow(h);
    MSG msg; DWORD start = GetTickCount();
    while (GetTickCount() - start < 1500) {
        while (PeekMessageW(&msg,NULL,0,0,PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        Sleep(20);
    }
    printf("UAH menu msgs: %d (bit1=WM_UAHDRAWMENU bit2=WM_UAHDRAWMENUITEM bit4=WM_UAHMEASUREMENUITEM)\n", g_menumsgs);
    return 0;
}

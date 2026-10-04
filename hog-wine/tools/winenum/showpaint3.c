/* showpaint3.c -- faithful replay of Qt's Windows window-creation sequence for the
 * Hog "Processor" window, to find which step makes Wine skip the initial WM_PAINT.
 *
 * usage: showpaint3.exe <mode>
 *   0 = create A(hidden owner) + B, SetWindowTextW, ShowWindow  (baseline; works on Wine)
 *   1 = + SetWindowPos(B, HWND_TOP, 0,0,0,0, SWP_NOSIZE|SWP_NOMOVE|SWP_NOZORDER|
 *                       SWP_NOACTIVATE|SWP_FRAMECHANGED) before ShowWindow (Qt setWindowFlags_sys)
 *   2 = + SendMessageW(B, WM_NCPAINT, 1, 0xc000000f) after ShowWindow (Qt QWindowsWindow)
 *   3 = 1+2
 * Prints whether WM_PAINT / WM_ERASEBKGND arrived.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static int paints, erases;

static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WM_ERASEBKGND: erases++; return TRUE;
    case WM_PAINT: { PAINTSTRUCT ps; paints++; BeginPaint(h, &ps); EndPaint(h, &ps); return 0; }
    }
    return DefWindowProcW(h, m, w, l);
}

static void dump(const wchar_t *tag, HWND h)
{
    RECT r, ur;
    GetWindowRect(h, &r);
    wprintf(L"%ls hwnd=%p vis=%d update=%d rect=(%ld,%ld)-(%ld,%ld)\n", tag, h,
            IsWindowVisible(h) ? 1 : 0, GetUpdateRect(h, &ur, FALSE) ? 1 : 0,
            r.left, r.top, r.right, r.bottom);
    fflush(stdout);
}

int wmain(int argc, wchar_t **argv)
{
    int mode = argc > 1 ? _wtoi(argv[1]) : 0;
    WNDCLASSEXW wc = { sizeof(wc) };
    wc.style = CS_DBLCLKS;               /* Qt uses CS_DBLCLKS */
    wc.lpfnWndProc = wp;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"SP3_Qt5151QWindow";
    wc.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
    RegisterClassExW(&wc);

    HWND a = CreateWindowExW(0, L"SP3_Qt5151QWindow", L"monitor-win32-golden", 0x86cf0000,
                             633, 360, 648, 514, NULL, NULL, wc.hInstance, NULL);
    HWND b = CreateWindowExW(0, L"SP3_Qt5151QWindow", L"monitor-win32-golden", 0x86000000,
                             575, 415, 770, 370, a, NULL, wc.hInstance, NULL);
    SetWindowTextW(b, L"Processor");
    if (mode & 1)
        SetWindowPos(b, HWND_TOP, 0, 0, 0, 0,
                     SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    ShowWindow(b, SW_SHOWNORMAL);
    if (mode & 2)
        SendMessageW(b, WM_NCPAINT, 1, 0xc000000f);
    if (mode & 4) {
        /* mimic the tool window + IME window Qt creates right after showing */
        HWND tool = CreateWindowExW(0x80, L"SP3_Qt5151QWindow", NULL, 0x80000000,
                                    0, 0, 1, 1, GetDesktopWindow(), NULL, wc.hInstance, NULL);
        SetWindowPos(tool, HWND_TOP, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE);
    }

    for (int i = 0; i < 300; i++) {
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        if (paints) break;
        Sleep(10);
    }
    dump(L"B ", b);
    wprintf(L"RESULT mode=%d paints=%d erases=%d\n", mode, paints, erases);
    fflush(stdout);
    return paints ? 0 : 1;
}

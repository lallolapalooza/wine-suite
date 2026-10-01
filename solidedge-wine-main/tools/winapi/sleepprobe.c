/* sleepprobe.c — measure Sleep() and timer granularity, and the WM_PAINT delivery rate.
 * A viewport that repaints at ~1 Hz looks like "continuous flicker"; this says whether the
 * platform is what throttles it.
 * build: x86_64-w64-mingw32-gcc -O1 -Wall -o sleepprobe.exe sleepprobe.c -luser32
 */
#include <windows.h>
#include <stdio.h>

static int paints, timers;
static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_PAINT) { PAINTSTRUCT ps; BeginPaint(h, &ps); EndPaint(h, &ps); paints++; return 0; }
    if (m == WM_TIMER) { timers++; InvalidateRect(h, NULL, TRUE); return 0; }
    return DefWindowProcA(h, m, w, l);
}

int main(void)
{
    WNDCLASSA wc = {0};
    HWND hwnd;
    MSG msg;
    LARGE_INTEGER f, a, b;
    int i;

    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&a);
    for (i = 0; i < 60; i++) Sleep(16);
    QueryPerformanceCounter(&b);
    printf("60 x Sleep(16) took %.1f ms  (%.1f ms each)\n",
           1000.0 * (b.QuadPart - a.QuadPart) / f.QuadPart,
           (1000.0 * (b.QuadPart - a.QuadPart) / f.QuadPart) / 60);

    QueryPerformanceCounter(&a);
    for (i = 0; i < 20; i++) Sleep(100);
    QueryPerformanceCounter(&b);
    printf("20 x Sleep(100) took %.1f ms\n", 1000.0 * (b.QuadPart - a.QuadPart) / f.QuadPart);

    wc.lpfnWndProc = proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "sleepprobe";
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(0, "sleepprobe", "sleepprobe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                           10, 10, 300, 200, NULL, NULL, wc.hInstance, NULL);
    ShowWindow(hwnd, SW_SHOW);
    SetTimer(hwnd, 1, 50, NULL);

    QueryPerformanceCounter(&a);
    for (i = 0; i < 100; i++) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg); DispatchMessageA(&msg);
        }
        InvalidateRect(hwnd, NULL, FALSE);
        Sleep(16);
    }
    QueryPerformanceCounter(&b);
    printf("100 loop iterations took %.1f ms; timers=%d paints=%d (expected ~100 timers at 50 ms, ~60/s)\n",
           1000.0 * (b.QuadPart - a.QuadPart) / f.QuadPart, timers, paints);
    return 0;
}

/* dwmprobe.c — the Windows/Wine contract for DwmGetWindowAttribute.
 *
 * The point is to have the *Windows* answer for every attribute Solid Edge's stack queries
 * (in particular DWMWA_CLOAKED = 14, which .NET's UIAutomationClient calls from
 * IsWindowCloaked(hwnd) and which Wine answers with E_NOTIMPL).  Run it on the Windows guest
 * and under Wine and diff the two outputs.
 *
 * build:  x86_64-w64-mingw32-gcc -O1 -Wall -o dwmprobe.exe dwmprobe.c -ldwmapi -luser32
 */
#include <windows.h>
#include <dwmapi.h>
#include <stdio.h>
#include <string.h>

static const char *attr_name(int a)
{
    switch (a) {
    case 1:  return "DWMWA_NCRENDERING_ENABLED";
    case 2:  return "DWMWA_NCRENDERING_POLICY";
    case 3:  return "DWMWA_TRANSITIONS_FORCEDISABLED";
    case 4:  return "DWMWA_ALLOW_NCPAINT";
    case 5:  return "DWMWA_CAPTION_BUTTON_BOUNDS";
    case 6:  return "DWMWA_NONCLIENT_RTL_LAYOUT";
    case 7:  return "DWMWA_FORCE_ICONIC_REPRESENTATION";
    case 8:  return "DWMWA_FLIP3D_POLICY";
    case 9:  return "DWMWA_EXTENDED_FRAME_BOUNDS";
    case 10: return "DWMWA_HAS_ICONIC_BITMAP";
    case 11: return "DWMWA_DISALLOW_PEEK";
    case 12: return "DWMWA_EXCLUDED_FROM_PEEK";
    case 13: return "DWMWA_CLOAK";
    case 14: return "DWMWA_CLOAKED";
    case 15: return "DWMWA_FREEZE_REPRESENTATION";
    case 16: return "DWMWA_PASSIVE_UPDATE_MODE";
    case 17: return "DWMWA_USE_HOSTBACKDROPBRUSH";
    case 18: return "DWMWA_USE_IMMERSIVE_DARK_MODE(18)";
    case 19: return "DWMWA_WINDOW_CORNER_PREFERENCE(19)";
    case 20: return "DWMWA_USE_IMMERSIVE_DARK_MODE(20)";
    case 33: return "DWMWA_WINDOW_CORNER_PREFERENCE(33)";
    case 34: return "DWMWA_BORDER_COLOR";
    case 35: return "DWMWA_CAPTION_COLOR";
    case 36: return "DWMWA_TEXT_COLOR";
    case 37: return "DWMWA_VISIBLE_FRAME_BORDER_THICKNESS";
    case 38: return "DWMWA_SYSTEMBACKDROP_TYPE";
    default: return "";
    }
}

static void probe(HWND hwnd, int a, int size)
{
    unsigned char buf[64];
    HRESULT hr;
    char hex[16 * 3 + 1];
    int i;

    memset(buf, 0xAB, sizeof(buf));
    hr = DwmGetWindowAttribute(hwnd, a, buf, size);
    if (hr == 0 && size >= 16) {
        const int *p = (const int *)buf;
        snprintf(hex, sizeof(hex), "INT[4] %d %d %d %d", p[0], p[1], p[2], p[3]);
    } else if (hr == 0) {
        snprintf(hex, sizeof(hex), "DWORD %u", *(const unsigned int *)buf);
    } else {
        for (i = 0; i < size && i < 8; i++) snprintf(hex + i * 2, 3, "%02x", buf[i]);
        snprintf(hex + (i < 8 ? i : 8) * 2, 3, "..");
    }
    printf("attr %2d size %2d %-38s hr=0x%08lx  %s%s\n", a, size, attr_name(a),
           (unsigned long)hr, hr ? "unchanged " : "", hex);
}

int main(void)
{
    WNDCLASSA wc = {0};
    HWND hwnd, child;
    MSG msg;
    BOOL enabled = FALSE;
    HRESULT hr;
    int a;

    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "dwmprobeWnd";
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(0, "dwmprobeWnd", "dwmprobe", WS_OVERLAPPEDWINDOW,
                           50, 50, 400, 300, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("CreateWindow failed %lu\n", GetLastError()); return 1; }
    child = CreateWindowExA(0, "dwmprobeWnd", "child", WS_CHILD | WS_VISIBLE,
                            0, 0, 100, 100, hwnd, NULL, wc.hInstance, NULL);
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    for (a = 0; a < 40; a++) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        Sleep(5);
    }

    hr = DwmIsCompositionEnabled(&enabled);
    printf("DwmIsCompositionEnabled -> hr=0x%08lx enabled=%ld\n", (unsigned long)hr, (long)enabled);
    printf("OSVersionInfo major=%lu minor=%lu build=%lu\n",
           GetVersion() & 0xff, (GetVersion() >> 8) & 0xff, 0UL);

    printf("\n-- DwmGetWindowAttribute(hwnd, attr, buf, size)\n");
    for (a = 0; a <= 40; a++) {
        probe(hwnd, a, 4);
        probe(hwnd, a, 16);
    }

    printf("\n-- edge cases (attribute 14 unless noted)\n");
    printf("pv=NULL size=0    -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 14, NULL, 0));
    printf("pv=NULL size=4    -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 14, NULL, 4));
    { unsigned int v = 0; printf("size=0            -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 14, &v, 0)); }
    { unsigned int v = 0; printf("size=1            -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 14, &v, 1)); }
    { unsigned int v = 0; printf("size=3            -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 14, &v, 3)); }
    { unsigned int v = 0; printf("size=8            -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 14, &v, 8)); }
    { unsigned int v = 0; printf("bogus hwnd        -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute((HWND)0x1234, 14, &v, 4)); }
    { unsigned int v = 0xABABABAB; printf("attr 5 size=8     -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(hwnd, 5, &v, 8)); }
    printf("\n-- on a CHILD window (extended frame bounds / cloaked)\n");
    probe(child, 9, 16);
    probe(child, 14, 4);
    printf("attr 14 child     -> hr=0x%08lx\n", (unsigned long)DwmGetWindowAttribute(child, 14, (void *)&a, 4));

    printf("\n-- DwmSetWindowAttribute round trips\n");
    { int v = 1; hr = DwmSetWindowAttribute(hwnd, 20, &v, sizeof(v)); printf("set 20=1   -> hr=0x%08lx\n", (unsigned long)hr); }
    { unsigned int v = 0xAB; hr = DwmGetWindowAttribute(hwnd, 20, &v, 4); printf("get 20     -> hr=0x%08lx v=%u\n", (unsigned long)hr, v); }
    { int v = 2; hr = DwmSetWindowAttribute(hwnd, 33, &v, sizeof(v)); printf("set 33=2   -> hr=0x%08lx\n", (unsigned long)hr); }
    { unsigned int v = 0xAB; hr = DwmGetWindowAttribute(hwnd, 33, &v, 4); printf("get 33     -> hr=0x%08lx v=%u\n", (unsigned long)hr, v); }
    { int v = 0x1234; hr = DwmSetWindowAttribute(hwnd, 34, &v, sizeof(v)); printf("set 34     -> hr=0x%08lx\n", (unsigned long)hr); }
    { unsigned int v = 0xAB; hr = DwmGetWindowAttribute(hwnd, 34, &v, 4); printf("get 34     -> hr=0x%08lx v=0x%x\n", (unsigned long)hr, v); }

    DestroyWindow(child);
    DestroyWindow(hwnd);
    printf("\ndone\n");
    return 0;
}

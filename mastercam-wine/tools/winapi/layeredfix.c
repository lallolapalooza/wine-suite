/* layeredfix.c — external probe: for every WS_EX_LAYERED top-level window, set the layered
 * attributes and force a repaint, then report what happened.
 *
 * Hypothesis under test: Wine creates the app's WS_EX_LAYERED windows but never maps them
 * (winex11: "layered windows are mapped only once their attributes are set", data->layered is
 * only set by SetLayeredWindowAttributes), so they stay invisible/black.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o layeredfix.exe layeredfix.c -luser32
 */
#include <windows.h>
#include <stdio.h>

static int count;
static BOOL CALLBACK cb(HWND h, LPARAM lp)
{
    LONG_PTR ex = GetWindowLongPtrA(h, GWL_EXSTYLE);
    char cls[128], txt[256];
    RECT r;
    (void)lp;
    if (!(ex & WS_EX_LAYERED)) return TRUE;
    GetClassNameA(h, cls, sizeof cls);
    GetWindowTextA(h, txt, sizeof txt);
    GetWindowRect(h, &r);
    printf("layered hwnd=%p class=%s text=\"%s\" rect=%ld,%ld %ldx%ld vis=%d mapped=%d\n",
           (void *)h, cls, txt, r.left, r.top, r.right - r.left, r.bottom - r.top,
           IsWindowVisible(h), IsWindow(h) != 0);
    if (lp) {
        SetLastError(0);
        BOOL ok = SetLayeredWindowAttributes(h, 0, 255, LWA_ALPHA);
        printf("   SetLayeredWindowAttributes(alpha=255) -> %d err=%lu\n", ok, GetLastError());
        RedrawWindow(h, NULL, NULL, RDW_ERASE | RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN | RDW_FRAME);
        ShowWindow(h, SW_SHOWNA);
        count++;
    }
    return TRUE;
}

int main(int argc, char **argv)
{
    int dofix = (argc > 1);
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== layered windows (apply=%d) ===\n", dofix);
    EnumWindows(cb, (LPARAM)dofix);
    printf("total layered=%d fixed=%d\n", count, dofix ? count : 0);
    return 0;
}

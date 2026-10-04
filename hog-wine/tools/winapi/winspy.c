/* winspy.c — dump the Win32 window tree of the current desktop (text included).
 *
 * The Wine X window tree only carries titles; modal dialogs' control text lives in Win32
 * window text. This prints it so an invisible/black dialog can still be read.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o winspy.exe winspy.c -luser32
 */
#include <windows.h>
#include <stdio.h>

static void indent(int n) { while (n-- > 0) fputs("  ", stdout); }

static const char *cls(HWND h)
{
    static char buf[256];
    buf[0] = 0;
    GetClassNameA(h, buf, sizeof buf);
    return buf;
}

static void text(HWND h, char *out, int n)
{
    out[0] = 0;
    if (GetWindowTextA(h, out, n) == 0) {
        /* some controls keep text in a child */
    }
}

static BOOL CALLBACK child_proc(HWND h, LPARAM lp)
{
    int depth = (int)lp;
    char t[512];
    RECT r;
    GetWindowRect(h, &r);
    text(h, t, sizeof t);
    indent(depth);
    printf("[child %p] %-24s rect=%ld,%ld %ldx%ld vis=%d en=%d text=\"%s\"\n",
           (void *)h, cls(h), r.left, r.top, r.right - r.left, r.bottom - r.top,
           IsWindowVisible(h), IsWindowEnabled(h), t);
    EnumChildWindows(h, child_proc, depth + 1);
    return TRUE;
}

static BOOL CALLBACK top_proc(HWND h, LPARAM lp)
{
    char t[512];
    RECT r;
    DWORD pid = 0;
    (void)lp;
    GetWindowRect(h, &r);
    text(h, t, sizeof t);
    GetWindowThreadProcessId(h, &pid);
    printf("[top  %p] pid=%lu %-24s rect=%ld,%ld %ldx%ld vis=%d en=%d text=\"%s\"\n",
           (void *)h, (unsigned long)pid, cls(h), r.left, r.top,
           r.right - r.left, r.bottom - r.top,
           IsWindowVisible(h), IsWindowEnabled(h), t);
    EnumChildWindows(h, child_proc, 1);
    return TRUE;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== desktop windows ===\n");
    EnumWindows(top_proc, 0);
    return 0;
}

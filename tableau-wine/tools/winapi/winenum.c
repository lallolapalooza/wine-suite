/* winenum.c - dump the live HWND tree of a target process, with class, visibility,
 * geometry, z-order and owner process, plus the top-most window at probe points.
 *
 * Why: Power BI Desktop's "views" (ReportView, DataExplore, Model, DaxQuery,
 * Tmdl) are separate WebView2 hosts.  Under Wine the report page stops holding
 * the foreground after ~T+50 s while on Windows it does; the app's own action
 * trace is identical, so the question is what the *window structure* looks like
 * on each platform.  This probe prints that structure in one text format that
 * can be produced on both platforms (same PE binary).
 *
 * Build (host):  x86_64-w64-mingw32-gcc -O1 -o tools/winapi/bin/winenum.exe tools/winapi/winenum.c -luser32 -lpsapi -lole32
 *   (the probe needs only kernel32/user32; -lpsapi/-lole32 are harmless extras)
 *
 * Run:   wine 'C:\viewprobe\winenum.exe' [image-substring] [outfile]
 *        image-substring defaults to "PBIDesktop"
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char *want = "PBIDesktop";
static FILE *out;

/* cache pid -> image name so we do not query the same process repeatedly */
#define MAXPIDS 64
static struct { DWORD pid; char name[128]; } pidcache[MAXPIDS];
static int npidcache;

static const char *image_of(DWORD pid)
{
    int i;
    HANDLE h;
    char buf[MAX_PATH];
    DWORD n = sizeof(buf);
    for (i = 0; i < npidcache; i++)
        if (pidcache[i].pid == pid) return pidcache[i].name;
    if (npidcache >= MAXPIDS) return "?";
    pidcache[npidcache].pid = pid;
    buf[0] = 0;
    h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (h)
    {
        if (QueryFullProcessImageNameA(h, 0, buf, &n))
        {
            char *p = strrchr(buf, '\\');
            if (p) memmove(buf, p + 1, strlen(p) + 1);
        }
        else buf[0] = 0;
        CloseHandle(h);
    }
    if (!buf[0]) strcpy(buf, "?");
    strcpy(pidcache[npidcache].name, buf);
    return pidcache[npidcache++].name;
}

static const char *class_of(HWND h, char *buf, int len)
{
    buf[0] = 0;
    GetClassNameA(h, buf, len);
    if (!buf[0]) strcpy(buf, "-");
    return buf;
}

static void text_of(HWND h, char *buf, int len)
{
    int i;
    buf[0] = 0;
    GetWindowTextA(h, buf, len);
    for (i = 0; buf[i]; i++)
        if (buf[i] == '\n' || buf[i] == '\r' || buf[i] == '\t') buf[i] = ' ';
}

static int depth_of(HWND h, HWND root)
{
    int d = 0;
    while (h && h != root) { h = GetParent(h); d++; if (d > 64) break; }
    return d;
}

static BOOL CALLBACK dump_cb(HWND h, LPARAM lp)
{
    HWND root = (HWND)lp;
    DWORD pid = 0;
    char cls[256], txt[256];
    RECT r;
    LONG style, ex;
    int idx = 0;
    HWND p;

    GetWindowThreadProcessId(h, &pid);
    class_of(h, cls, sizeof(cls));
    text_of(h, txt, sizeof(txt));
    GetWindowRect(h, &r);
    style = GetWindowLongA(h, GWL_STYLE);
    ex = GetWindowLongA(h, GWL_EXSTYLE);
    p = GetParent(h);
    /* z-order index inside the parent: EnumChildWindows enumerates top -> bottom */
    if (p)
    {
        HWND c = GetWindow(p, GW_CHILD);
        while (c && c != h) { c = GetWindow(c, GW_HWNDNEXT); idx++; }
    }
    fprintf(out, "D %2d z%-3d hwnd=%p pid=%-6lu img=%-22s class=%-42s parent=%p vis=%d "
                 "style=%08lx ex=%08lx id=%lu rect=%ld,%ld,%ld,%ld size=%ldx%ld text=\"%s\"\n",
            depth_of(h, root), idx, h, (unsigned long)pid, image_of(pid), cls, p,
            IsWindowVisible(h) ? 1 : 0,
            (unsigned long)style, (unsigned long)ex,
            (unsigned long)GetWindowLongPtrA(h, GWLP_ID),
            r.left, r.top, r.right, r.bottom, r.right - r.left, r.bottom - r.top, txt);
    return TRUE;
}

static void chain(HWND h)
{
    char cls[256];
    int i = 0;
    while (h && i++ < 24)
    {
        DWORD pid = 0;
        GetWindowThreadProcessId(h, &pid);
        fprintf(out, "      chain[%d] hwnd=%p class=%s img=%s vis=%d\n", i - 1, h,
                class_of(h, cls, sizeof(cls)), image_of(pid), IsWindowVisible(h) ? 1 : 0);
        h = GetParent(h);
    }
}

static void point(int x, int y, const char *label)
{
    POINT pt;
    HWND h;
    pt.x = x; pt.y = y;
    h = WindowFromPoint(pt);
    fprintf(out, "P %s (%d,%d) hwnd=%p\n", label, x, y, h);
    if (h) chain(h);
}

static BOOL CALLBACK find_cb(HWND h, LPARAM lp)
{
    DWORD pid = 0;
    char cls[256], txt[256];
    RECT r;
    int *found = (int *)lp;

    GetWindowThreadProcessId(h, &pid);
    if (!strstr(image_of(pid), want)) return TRUE;
    if (!IsWindowVisible(h)) return TRUE;
    GetWindowRect(h, &r);
    if (r.right - r.left < 200 || r.bottom - r.top < 200) return TRUE;
    (*found)++;
    fprintf(out, "# root HWND %p pid=%lu img=%s class=%s style=%08lx ex=%08lx "
                 "rect=%ld,%ld,%ld,%ld text=\"%s\"\n",
            h, (unsigned long)pid, image_of(pid), class_of(h, cls, sizeof(cls)),
            (unsigned long)GetWindowLongA(h, GWL_STYLE),
            (unsigned long)GetWindowLongA(h, GWL_EXSTYLE),
            r.left, r.top, r.right, r.bottom, (text_of(h, txt, sizeof(txt)), txt));
    EnumChildWindows(h, dump_cb, (LPARAM)h);
    return TRUE;
}

int main(int argc, char **argv)
{
    int found = 0;
    HWND fg, act, foc;
    char cls[256];

    if (argc > 1) want = argv[1];
    out = stdout;
    if (argc > 2 && strcmp(argv[2], "-") != 0)
    {
        out = fopen(argv[2], "w");
        if (!out) { out = stdout; }
    }

    {
        DWORD fgpid = 0;
        fg = GetForegroundWindow();
        act = GetActiveWindow();
        foc = GetFocus();
        if (fg) GetWindowThreadProcessId(fg, &fgpid);
        fprintf(out, "# winenum: pid=%lu image=%s\n", (unsigned long)GetCurrentProcessId(), image_of(GetCurrentProcessId()));
        fprintf(out, "# foreground=%p class=%s img=%s active=%p focus=%p\n", fg,
                fg ? class_of(fg, cls, sizeof(cls)) : "-", fg ? image_of(fgpid) : "-", act, foc);
    }
    fprintf(out, "# screen=%dx%d\n", GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));

    EnumWindows(find_cb, (LPARAM)&found);
    fprintf(out, "# roots=%d\n", found);

    point(648, 71, "ribbon");
    point(648, 397, "canvas-center");
    point(1200, 200, "right-pane");
    point(200, 700, "bottom-left");
    fflush(out);
    return 0;
}

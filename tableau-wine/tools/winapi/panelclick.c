/* panelclick.c - drive one of Power BI Desktop's WebView2 view panels under Wine.
 *
 * Why this exists: under Wine the five view panels overlap, Wine's own hit-test (WindowFromPoint) names the
 * *report* panel everywhere, while the pixels on screen come from a secondary view (docs/VIEW_DIVERGENCE.md §5).
 * A real X-level click is therefore delivered to the report page and can never reach a tour dialog that lives in
 * the daxQueryView/tmdlView page.  This probe addresses a panel directly: it finds the panel by the page its
 * WebView2 has loaded, reports its coordinate mapping, and posts a synthetic key/click to that panel's Chromium
 * windows, bypassing Wine's hit-test.  It can also change a panel's z-order or visibility (the same ops
 * tools/winapi/winzorder.c offers), so the two routes to a dialog can be compared in one run.
 *
 * Build: x86_64-w64-mingw32-gcc -O1 -o tools/winapi/bin/panelclick.exe tools/winapi/panelclick.c -luser32
 *
 * Usage: panelclick.exe list
 *        panelclick.exe rect  <page-fragment>                 (screen rects + client origin of the panel chain)
 *        panelclick.exe probe <x> <y>                         (WindowFromPoint + which panel/URL owns it)
 *        panelclick.exe key   <page-fragment> <vk-hex> [target]
 *        panelclick.exe click <page-fragment> <x> <y>  [target]   (x,y = client coords of that panel)
 *        panelclick.exe top|hide|show <page-fragment>
 *
 *   target = all (default, posts to every window down the chain) | render | widget | w0 | panel
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define MAXP 10
static HWND panels[MAXP];
static char pages[MAXP][160];
static int npanels;
static HWND root;

static BOOL CALLBACK find_root(HWND h, LPARAM lp)
{
    DWORD pid = 0;
    char buf[MAX_PATH];
    HANDLE p;
    DWORD n = sizeof(buf);
    char cls[256];
    (void)lp;
    GetClassNameA(h, cls, sizeof(cls));
    if (!strstr(cls, "WindowsForms10.Window")) return TRUE;
    if (GetWindow(h, GW_OWNER)) return TRUE;
    GetWindowThreadProcessId(h, &pid);
    p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return TRUE;
    buf[0] = 0;
    if (!QueryFullProcessImageNameA(p, 0, buf, &n)) buf[0] = 0;
    CloseHandle(p);
    if (!strstr(buf, "PBIDesktop")) return TRUE;
    if (!IsWindowVisible(h)) return TRUE;
    root = h;
    return FALSE;
}

/* the page URL is the text of the panel's grandchild Chrome_WidgetWin_1 */
static void page_of(HWND panel, char *out, int len)
{
    HWND c, g;
    out[0] = 0;
    for (c = GetWindow(panel, GW_CHILD); c; c = GetWindow(c, GW_HWNDNEXT))
        for (g = GetWindow(c, GW_CHILD); g; g = GetWindow(g, GW_HWNDNEXT))
            if (GetWindowTextA(g, out, len) > 0) return;
}

static void scan(void)
{
    HWND c;
    npanels = 0;
    root = NULL;
    EnumWindows(find_root, 0);
    if (!root) return;
    for (c = GetWindow(root, GW_CHILD); c && npanels < MAXP; c = GetWindow(c, GW_HWNDNEXT))
    {
        RECT r;
        char cls[256];
        GetClassNameA(c, cls, sizeof(cls));
        if (!strstr(cls, "WindowsForms10.Window")) continue;
        GetWindowRect(c, &r);
        if (r.right - r.left < 400) continue;   /* skip the small dialog host */
        panels[npanels] = c;
        page_of(c, pages[npanels], sizeof(pages[npanels]));
        if (!pages[npanels][0]) strcpy(pages[npanels], "(no page url)");
        npanels++;
    }
}

static int zindex(HWND h)
{
    HWND p = GetParent(h), c;
    int idx = 0;
    if (!p) return -1;
    for (c = GetWindow(p, GW_CHILD); c && c != h; c = GetWindow(c, GW_HWNDNEXT)) idx++;
    return idx;
}

static int find_frag(const char *frag)
{
    int i;
    for (i = 0; i < npanels; i++)
        if (strstr(pages[i], frag)) return i;
    return -1;
}

static HWND find_class(HWND h, const char *want)
{
    HWND c;
    char cls[256];
    GetClassNameA(h, cls, sizeof(cls));
    if (strcmp(cls, want) == 0) return h;
    for (c = GetWindow(h, GW_CHILD); c; c = GetWindow(c, GW_HWNDNEXT))
    {
        HWND r = find_class(c, want);
        if (r) return r;
    }
    return NULL;
}

static const char *panel_of(HWND h)
{
    int i;
    HWND w = h;
    while (w)
    {
        for (i = 0; i < npanels; i++)
            if (panels[i] == w) return pages[i];
        w = GetParent(w);
    }
    return "-";
}

static void list(void)
{
    int i;
    printf("root=%p panels=%d (EnumChildWindows order = top first)\n", root, npanels);
    for (i = 0; i < npanels; i++)
        printf("  z%-2d panel=%p vis=%d zi=%d page=%s\n", i, panels[i],
               IsWindowVisible(panels[i]) ? 1 : 0, zindex(panels[i]), pages[i]);
}

static void rects(HWND panel)
{
    HWND chain[6];
    const char *names[6] = { "panel", "Chrome_WidgetWin_0", "Chrome_WidgetWin_1",
                             "Chrome_RenderWidgetHostHWND", "-", "-" };
    int n = 0, i;
    HWND w = panel;
    while (w && n < 4)
    {
        chain[n++] = w;
        if (n == 2 || n == 3)
        {
            /* step to the interesting child */
            HWND c = GetWindow(w, GW_CHILD);
            char cls[256];
            HWND next = NULL;
            for (; c; c = GetWindow(c, GW_HWNDNEXT))
            {
                GetClassNameA(c, cls, sizeof(cls));
                if (n == 1 && strcmp(cls, "Chrome_WidgetWin_0") == 0) { next = c; break; }
                if (n == 2 && strcmp(cls, "Chrome_WidgetWin_1") == 0) { next = c; break; }
                if (n == 3 && strcmp(cls, "Chrome_RenderWidgetHostHWND") == 0) { next = c; break; }
            }
            w = next;
        }
        else w = GetWindow(w, GW_CHILD);
    }
    for (i = 0; i < n; i++)
    {
        RECT r, c0, c1;
        POINT p;
        GetWindowRect(chain[i], &r);
        GetClientRect(chain[i], &c1);
        p.x = 0; p.y = 0;
        ClientToScreen(chain[i], &p);
        c0 = r;
        printf("  %-28s hwnd=%p winrect=%ld,%ld,%ld,%ld  client_size=%ldx%ld  client_origin_screen=%ld,%ld\n",
               names[i], chain[i], r.left, r.top, r.right, r.bottom,
               c1.right - c1.left, c1.bottom - c1.top, p.x, p.y);
    }
}

static void probe(int x, int y)
{
    POINT pt;
    HWND h;
    char cls[256];
    pt.x = x; pt.y = y;
    h = WindowFromPoint(pt);
    printf("point (%d,%d) -> hwnd=%p class=%s panel=%s\n", x, y, h,
           h ? (GetClassNameA(h, cls, sizeof(cls)), cls) : "-", panel_of(h));
}

int main(int argc, char **argv)
{
    const char *op = argc > 1 ? argv[1] : "list";
    int k, x, y;
    HWND panel, w0, w1, rw;
    const char *tg;

    scan();
    if (!root) { printf("no PBIDesktop main window\n"); return 1; }
    if (!strcmp(op, "list")) { list(); return 0; }
    if (!strcmp(op, "probe"))
    {
        list();
        if (argc > 3) probe(atoi(argv[2]), atoi(argv[3]));
        return 0;
    }
    if (argc < 3) { printf("missing page fragment\n"); return 2; }
    k = find_frag(argv[2]);
    if (k < 0) { printf("no panel matching '%s'\n", argv[2]); list(); return 2; }
    panel = panels[k];
    w0 = find_class(panel, "Chrome_WidgetWin_0");
    w1 = find_class(panel, "Chrome_WidgetWin_1");
    rw = find_class(panel, "Chrome_RenderWidgetHostHWND");
    printf("panel '%s' -> %p w0=%p w1=%p render=%p zi=%d vis=%d\n", pages[k], panel, w0, w1, rw,
           zindex(panel), IsWindowVisible(panel) ? 1 : 0);

    if (!strcmp(op, "rect")) { rects(panel); return 0; }
    if (!strcmp(op, "top"))
    {
        SetWindowPos(panel, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        list();
        return 0;
    }
    if (!strcmp(op, "hide")) { ShowWindow(panel, SW_HIDE); list(); return 0; }
    if (!strcmp(op, "show")) { ShowWindow(panel, SW_SHOW); list(); return 0; }

    tg = argc > (strcmp(op, "click") == 0 ? 5 : 4) ? argv[strcmp(op, "click") == 0 ? 5 : 4] : "all";

    if (!strcmp(op, "key"))
    {
        int vk = (int)strtol(argv[3], NULL, 16);
        HWND t[4];
        int i, n = 0;
        t[n++] = rw; t[n++] = w1; t[n++] = w0; t[n++] = panel;
        printf("posting WM_KEYDOWN/UP vk=0x%02x target=%s\n", vk, tg);
        for (i = 0; i < n; i++)
        {
            if (!t[i]) continue;
            if (strcmp(tg, "all") && (strcmp(tg, "render") || t[i] != rw) &&
                (strcmp(tg, "widget") || t[i] != w1) && (strcmp(tg, "w0") || t[i] != w0) &&
                (strcmp(tg, "panel") || t[i] != panel)) continue;
            PostMessage(t[i], WM_KEYDOWN, vk, 0);
            Sleep(30);
            PostMessage(t[i], WM_KEYUP, vk, 0);
            Sleep(30);
            printf("  -> %p key posted\n", t[i]);
        }
        return 0;
    }
    if (!strcmp(op, "click"))
    {
        LPARAM lp;
        HWND t[4];
        int i, n = 0;
        x = atoi(argv[3]); y = atoi(argv[4]);
        lp = MAKELPARAM(x, y);
        t[n++] = rw; t[n++] = w1; t[n++] = w0; t[n++] = panel;
        printf("posting click client(%d,%d) target=%s\n", x, y, tg);
        for (i = 0; i < n; i++)
        {
            if (!t[i]) continue;
            if (strcmp(tg, "all") && (strcmp(tg, "render") || t[i] != rw) &&
                (strcmp(tg, "widget") || t[i] != w1) && (strcmp(tg, "w0") || t[i] != w0) &&
                (strcmp(tg, "panel") || t[i] != panel)) continue;
            PostMessage(t[i], WM_MOUSEMOVE, 0, lp);
            Sleep(30);
            PostMessage(t[i], WM_LBUTTONDOWN, MK_LBUTTON, lp);
            Sleep(50);
            PostMessage(t[i], WM_LBUTTONUP, 0, lp);
            Sleep(30);
            printf("  -> %p click posted\n", t[i]);
        }
        return 0;
    }
    printf("unknown op %s\n", op);
    return 2;
}

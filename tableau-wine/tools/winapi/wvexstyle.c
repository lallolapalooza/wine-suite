/* wvexstyle.c - measure the *clip region* Wine/Windows give a covered child window, and the role of
 * WS_EX_TRANSPARENT in computing it.  One PE, both platforms.
 *
 * Why: under Wine the five Power BI view panels overlap; the report panel is topmost in Wine's own
 * z-order and hit-test (WindowFromPoint -> its Chrome_RenderWidgetHostHWND) yet the pixels on screen
 * come from a *covered* panel (docs/VIEW_DIVERGENCE.md §5).  Wine's GDI/GPU presentation paths clip
 * out-of-band content with the DC's system region (GetRandomRgn SYSRGN: dlls/win32u/clipping.c case
 * SYSRGN <- dc->hVisRgn <- dlls/win32u/dce.c update_visible_region <- server get_visible_region), and
 * that region subtracts the visible rects of the *siblings above* the window -- except that
 * server/window.c:clip_children() skips siblings with WS_EX_TRANSPARENT.  Every Power BI view panel is
 * created WS_EX_TRANSPARENT (ex=0x00000020, measured on both platforms, logs/occlusion/winenum_t130.txt
 * vs logs/viewdiff/guest/wv_winstru_winenum_t1.txt), so under Wine each covered panel may believe it is
 * fully visible and present over the report page.
 *
 * Modes
 *   wvexstyle.exe synth                 self-contained z-order/region test, no app needed (any platform)
 *   wvexstyle.exe panels                live Power BI: per panel ex-styles, page URL, SYSRGN, hit-test
 *   wvexstyle.exe clear <0|1>           clear (0) / restore (1) WS_EX_TRANSPARENT on the five panels
 *   wvexstyle.exe sysrgn <hwnd-hex>     region report for one window
 *
 * Build: x86_64-w64-mingw32-gcc -O1 -o tools/winapi/bin/wvexstyle.exe tools/winapi/wvexstyle.c -luser32
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#ifndef WINVER
#define WINVER 0x0601
#endif
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* mingw-w64 does not declare DCX_USESTYLE (a Windows 2000+ flag, 0x00010000); the live Wine path
 * (win32u client_surface_present) uses DCX_CACHE|DCX_USESTYLE, so mirror it exactly */
#ifndef DCX_USESTYLE
#define DCX_USESTYLE 0x00010000
#endif

#define MAXP 10

/* ------------------------------------------------------------------ region reporting */

static void region_report_flags(FILE *f, const char *label, HWND h, DWORD flags)
{
    HDC dc;
    HRGN rgn;
    RECT box = {0, 0, 0, 0};
    int type, nrects = 0, status;

    dc = GetDCEx(h, 0, flags);
    if (!dc) { fprintf(f, "%-34s hwnd=%p NO DC\n", label, (void *)h); return; }
    rgn = CreateRectRgn(0, 0, 0, 0);
    status = GetRandomRgn(dc, rgn, SYSRGN);
    if (status > 0)
    {
        type = GetRgnBox(rgn, &box);
        RGNDATA *d;
        DWORD size = GetRegionData(rgn, 0, NULL);
        if (size)
        {
            d = malloc(size);
            if (GetRegionData(rgn, size, d)) nrects = d->rdh.nCount;
            free(d);
        }
    }
    else type = 0;
    fprintf(f, "%-34s hwnd=%p flags=%08lx sysrgn=%s box=%ld,%ld,%ld,%ld rects=%d\n", label, (void *)h,
            (unsigned long)flags,
            status <= 0 ? "NULL" : (type == NULLREGION ? "EMPTY" : (type == SIMPLEREGION ? "SIMPLE" : "COMPLEX")),
            box.left, box.top, box.right, box.bottom, nrects);
    DeleteObject(rgn);
    ReleaseDC(h, dc);
}

static void region_report(FILE *f, const char *label, HWND h)
{
    region_report_flags(f, label, h, DCX_CACHE | DCX_USESTYLE);
}

static void window_report(FILE *f, const char *label, HWND h)
{
    char cls[256] = "-";
    RECT r = {0};
    GetClassNameA(h, cls, sizeof(cls));
    GetWindowRect(h, &r);
    fprintf(f, "  %-14s hwnd=%p class=%-42s ex=%08lx style=%08lx rect=%ld,%ld,%ld,%ld vis=%d\n",
            label, (void *)h, cls, (unsigned long)GetWindowLongA(h, GWL_EXSTYLE),
            (unsigned long)GetWindowLongA(h, GWL_STYLE), r.left, r.top, r.right, r.bottom,
            IsWindowVisible(h) ? 1 : 0);
}

/* ------------------------------------------------------------------ synth mode */

static int any_class;   /* explicit root given: accept any child class (smoke test) */
static int keep_cover;  /* hold mode: keep the covering sibling alive for inspection */


#define SYNTH_W 300
#define SYNTH_H 200

static LRESULT CALLBACK synth_proc(HWND h, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_PAINT) { PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); FillRect(dc, &ps.rcPaint, (HBRUSH)GetStockObject(GRAY_BRUSH)); EndPaint(h, &ps); return 0; }
    return DefWindowProcA(h, msg, wp, lp);
}

/* one case: a "cover" container and a "target" container as overlapping siblings of `parent`, each
 * holding one full-size inner child (mirrors panel -> Chrome_WidgetWin_0 -> Chrome_WidgetWin_1 ->
 * Chrome_RenderWidgetHostHWND).  The target is created last, i.e. it is the *top* of the pair; the
 * interesting question is what the *covered* window below it reports. */
static void synth_case(FILE *f, HWND parent, int x, const char *name, DWORD cover_ex, DWORD target_ex,
                       int cover_first)
{
    HWND cover, target, cover_in, target_in;
    DWORD style = WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN;
    RECT r;

    fprintf(f, "\n== case %s cover_ex=%08lx target_ex=%08lx (cover created %s)\n", name,
            (unsigned long)cover_ex, (unsigned long)target_ex, cover_first ? "first" : "second");

    r.left = x; r.top = 0; r.right = x + SYNTH_W; r.bottom = SYNTH_H;

    cover = CreateWindowExA(cover_ex, "wvexstyle_synth", "", style, r.left, r.top, SYNTH_W, SYNTH_H,
                            parent, NULL, GetModuleHandleA(NULL), NULL);
    target = CreateWindowExA(target_ex, "wvexstyle_synth", "", style, r.left, r.top, SYNTH_W, SYNTH_H,
                             parent, NULL, GetModuleHandleA(NULL), NULL);
    /* the inner child is what carries the GPU surface in the real app; Chromium also sets
     * WS_EX_TRANSPARENT on it (ex=0x20 in the live enumerations on both platforms) */
    cover_in = CreateWindowExA(WS_EX_TRANSPARENT, "wvexstyle_synth", "", style, 0, 0, SYNTH_W, SYNTH_H,
                               cover, NULL, GetModuleHandleA(NULL), NULL);
    target_in = CreateWindowExA(WS_EX_TRANSPARENT, "wvexstyle_synth", "", style, 0, 0, SYNTH_W, SYNTH_H,
                                target, NULL, GetModuleHandleA(NULL), NULL);
    (void)cover_in;

    window_report(f, "cover(above)", cover);
    window_report(f, "target(below)", target);
    window_report(f, "target.inner", target_in);
    region_report(f, "cover_sysrgn", cover);
    region_report(f, "target_sysrgn", target);
    region_report(f, "target_inner_sysrgn", target_in);
    {
        POINT p;
        HWND hit;
        p.x = x + SYNTH_W / 2; p.y = SYNTH_H / 2;
        ClientToScreen(parent, &p);
        hit = WindowFromPoint(p);
        fprintf(f, "  hit-test at center -> hwnd=%p (%s)\n", (void *)hit,
                hit == target_in ? "target.inner" : (hit == cover_in ? "cover.inner" : "other"));
    }
    if (!keep_cover) DestroyWindow(cover);
}

static int synth(void)
{
    WNDCLASSA wc;
    HWND top;
    FILE *f = stdout;
    MSG msg;

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = synth_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "wvexstyle_synth";
    wc.hbrBackground = (HBRUSH)GetStockObject(GRAY_BRUSH);
    if (!RegisterClassA(&wc)) { printf("RegisterClass failed %lu\n", GetLastError()); return 1; }

    top = CreateWindowExA(0, "wvexstyle_synth", "wvexstyle synth", WS_POPUP | WS_VISIBLE,
                          0, 0, 3 * SYNTH_W, SYNTH_H, NULL, NULL, wc.hInstance, NULL);
    if (!top) { printf("CreateWindow failed %lu\n", GetLastError()); return 1; }
    UpdateWindow(top);
    ShowWindow(top, SW_SHOW);

    synth_case(f, top, 0, "normal", 0, 0, 1);
    synth_case(f, top, SYNTH_W, "transparent_cover", WS_EX_TRANSPARENT, 0, 1);
    synth_case(f, top, 2 * SYNTH_W, "transparent_both", WS_EX_TRANSPARENT, WS_EX_TRANSPARENT, 1);
    synth_case(f, top, 0, "layered_transparent_cover", WS_EX_LAYERED | WS_EX_TRANSPARENT, 0, 1);

    /* let the (possible) compositor settle before reporting once more */
    while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
    Sleep(500);
    fprintf(f, "\n-- after settle --\n");
    synth_case(f, top, 0, "normal(2)", 0, 0, 1);
    synth_case(f, top, SYNTH_W, "transparent_cover(2)", WS_EX_TRANSPARENT, 0, 1);
    fprintf(f, "== done ==\n");
    return 0;
}

/* ------------------------------------------------------------------ live Power BI modes */

static HWND root;

static BOOL CALLBACK find_root(HWND h, LPARAM lp)
{
    DWORD pid = 0;
    char buf[MAX_PATH] = "";
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
    if (!QueryFullProcessImageNameA(p, 0, buf, &n)) buf[0] = 0;
    CloseHandle(p);
    if (!strstr(buf, "PBIDesktop")) return TRUE;
    if (!IsWindowVisible(h)) return TRUE;
    root = h;
    return FALSE;
}

static void text_of(HWND h, char *out, int len)
{
    out[0] = 0;
    GetWindowTextA(h, out, len);
}

static HWND deepest(HWND h, int *depth)
{
    HWND c, last = h;
    int d = 0;
    while ((c = GetWindow(h, GW_CHILD))) { h = c; d++; }
    if (depth) *depth = d;
    return last;
}

static int panels(HWND explicit_root)
{
    HWND c;
    int idx = 0;
    POINT pts[4];
    const char *labels[4] = { "ribbon", "canvas", "right-pane", "bottom-left" };
    int i;

    root = explicit_root;
    any_class = explicit_root != NULL;
    if (!root) EnumWindows(find_root, 0);
    if (!root) { printf("no PBIDesktop root window found\n"); return 1; }
    printf("root hwnd=%p\n", (void *)root);
    for (c = GetWindow(root, GW_CHILD); c && idx < MAXP; c = GetWindow(c, GW_HWNDNEXT), idx++)
    {
        HWND w0, w1, rw, deep;
        char page[256] = "", cls[256] = "-";
        int depth = 0;
        RECT r;
        GetClassNameA(c, cls, sizeof(cls));
        if (!any_class && !strstr(cls, "WindowsForms10.Window")) { idx--; continue; }
        w0 = GetWindow(c, GW_CHILD);
        w1 = w0 ? GetWindow(w0, GW_CHILD) : NULL;
        if (w1) text_of(w1, page, sizeof(page));
        if (w1) rw = GetWindow(w1, GW_CHILD); else rw = NULL;
        deep = deepest(c, &depth);
        GetWindowRect(c, &r);
        printf("\nz%d panel hwnd=%p rect=%ld,%ld,%ld,%ld page=\"%s\"\n", idx, (void *)c,
               r.left, r.top, r.right, r.bottom, page);
        window_report(stdout, "panel", c);
        if (w0) window_report(stdout, "widgetwin0", w0);
        if (w1) window_report(stdout, "widgetwin1", w1);
        if (rw) window_report(stdout, "renderwidget", rw);
        printf("  deepest=%p depth=%d\n", (void *)deep, depth);
        region_report(stdout, "panel_sysrgn", c);
        if (rw) region_report(stdout, "renderwidget_sysrgn", rw);
    }
    pts[0].x = 648; pts[0].y = 71;
    pts[1].x = 648; pts[1].y = 397;
    pts[2].x = 1200; pts[2].y = 200;
    pts[3].x = 200; pts[3].y = 700;
    printf("\n-- hit tests (WindowFromPoint) --\n");
    for (i = 0; i < 4; i++)
    {
        HWND h = WindowFromPoint(pts[i]);
        char cls[256] = "-";
        HWND p = h;
        GetClassNameA(h, cls, sizeof(cls));
        while (GetParent(p) && GetParent(p) != root) p = GetParent(p);
        printf("  %-12s (%ld,%ld) -> hwnd=%p class=%s panel=", labels[i], pts[i].x, pts[i].y,
               (void *)h, cls);
        if (p == root) printf("(root)\n");
        else
        {
            char page[256] = "";
            HWND w0 = GetWindow(p, GW_CHILD);
            HWND w1 = w0 ? GetWindow(w0, GW_CHILD) : NULL;
            if (w1) text_of(w1, page, sizeof(page));
            printf("%p page=\"%s\"\n", (void *)p, page);
        }
    }
    printf("== done ==\n");
    return 0;
}

static HWND find_panel(const char *fragment);

/* raise the panel whose page URL contains <fragment> to the top of the z-order; the app's own
 * selected view can then be put back in front (measured: raising a panel makes its system region full and the
 * screen follows it -- tools/occl_judge_run.sh, FINDINGS M67) */
static int raise_panel(const char *fragment)
{
    HWND found = find_panel(fragment);
    if (!found) { printf("no panel matching \"%s\"\n", fragment); return 1; }
    SetWindowPos(found, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    printf("raised hwnd=%p (matching \"%s\")\n", (void *)found, fragment);
    return 0;
}

/* find the panel whose page URL contains <fragment> */
static HWND find_panel(const char *fragment)
{
    HWND c, found = NULL;
    int idx = 0;
    root = NULL;
    EnumWindows(find_root, 0);
    if (!root) return NULL;
    for (c = GetWindow(root, GW_CHILD); c && idx < MAXP; c = GetWindow(c, GW_HWNDNEXT), idx++)
    {
        HWND w0, w1;
        char page[256] = "", cls[256] = "-";
        GetClassNameA(c, cls, sizeof(cls));
        if (!strstr(cls, "WindowsForms10.Window")) { idx--; continue; }
        w0 = GetWindow(c, GW_CHILD);
        w1 = w0 ? GetWindow(w0, GW_CHILD) : NULL;
        if (w1) text_of(w1, page, sizeof(page));
        if (strstr(page, fragment)) { found = c; break; }
    }
    return found;
}

/* force a panel's Chromium content to be repainted and re-presented: WM_PAINT on the render widget is what makes
 * Chromium schedule a compositor frame, and the visible region is already correct -- measured: the covering panel's
 * region is full while its (stale) pixels are not on screen, because a static page produces no damage */
static int redraw_panel(const char *fragment)
{
    HWND panel = find_panel(fragment), deep;
    int depth = 0;
    if (!panel) { printf("no panel matching \"%s\"\n", fragment); return 1; }
    deep = deepest(panel, &depth);
    printf("redraw hwnd=%p (\"%s\"), deepest=%p depth=%d\n", (void *)panel, fragment, (void *)deep, depth);
    InvalidateRect(deep, NULL, TRUE);
    UpdateWindow(deep);
    RedrawWindow(panel, NULL, NULL, RDW_INVALIDATE | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN | RDW_UPDATENOW);
    printf("redraw done\n");
    return 0;
}

/* hide every view panel except the one matching <fragment> (or show them all again).
 *
 * Why: the screen is the last DXGI surface the WebView2 GPU processes pushed (M69), so no Wine-side repaint of a
 * region Wine has already decided is covered can bring the selected view back. A *hidden* window's Chromium
 * renderer stops producing frames, so hiding the secondary views is the one lever that does not depend on Wine
 * re-presenting anything. Reversible: `showall` restores every panel.
 */
static int hide_others(const char *fragment)
{
    HWND c, keep;
    int idx = 0, n = 0;
    if (!root) EnumWindows(find_root, 0);
    if (!root) { printf("no PBIDesktop root window found\n"); return 1; }
    keep = find_panel(fragment);
    printf("keep  hwnd=%p (\"%s\")\n", (void *)keep, fragment);
    for (c = GetWindow(root, GW_CHILD); c && idx < MAXP; c = GetWindow(c, GW_HWNDNEXT), idx++)
    {
        char cls[256] = "-";
        GetClassNameA(c, cls, sizeof(cls));
        if (!strstr(cls, "WindowsForms10.Window")) { idx--; continue; }
        if (c == keep) continue;
        ShowWindow(c, SW_HIDE);
        printf("hide  hwnd=%p\n", (void *)c);
        n++;
    }
    printf("== hid %d panels, kept \"%s\" visible ==\n", n, fragment);
    return 0;
}

static int show_all(void)
{
    HWND c;
    int idx = 0, n = 0;
    if (!root) EnumWindows(find_root, 0);
    if (!root) { printf("no PBIDesktop root window found\n"); return 1; }
    for (c = GetWindow(root, GW_CHILD); c && idx < MAXP; c = GetWindow(c, GW_HWNDNEXT), idx++)
    {
        char cls[256] = "-";
        GetClassNameA(c, cls, sizeof(cls));
        if (!strstr(cls, "WindowsForms10.Window")) { idx--; continue; }
        ShowWindow(c, SW_SHOW);
        printf("show  hwnd=%p\n", (void *)c);
        n++;
    }
    printf("== %d panels shown ==\n", n);
    return 0;
}

/* clear (mode 0) or restore (mode 1) WS_EX_TRANSPARENT on the five view panels */
static int clear_ex(int on, HWND explicit_root)
{
    HWND c;
    int idx = 0, n = 0;
    root = explicit_root;
    any_class = explicit_root != NULL;
    if (!root) EnumWindows(find_root, 0);
    if (!root) { printf("no PBIDesktop root window found\n"); return 1; }
    for (c = GetWindow(root, GW_CHILD); c && idx < MAXP; c = GetWindow(c, GW_HWNDNEXT), idx++)
    {
        char cls[256] = "-";
        LONG ex;
        GetClassNameA(c, cls, sizeof(cls));
        if (!any_class && !strstr(cls, "WindowsForms10.Window")) { idx--; continue; }
        ex = GetWindowLongA(c, GWL_EXSTYLE);
        if (on) SetWindowLongA(c, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT);
        else SetWindowLongA(c, GWL_EXSTYLE, ex & ~WS_EX_TRANSPARENT);
        SetWindowPos(c, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        printf("panel z%d hwnd=%p ex %08lx -> %08lx\n", idx, (void *)c, (unsigned long)ex,
               (unsigned long)GetWindowLongA(c, GWL_EXSTYLE));
        n++;
    }
    printf("== %d panels %s WS_EX_TRANSPARENT ==\n", n, on ? "restored to" : "cleared of");
    return 0;
}

/* hold: build the app-shaped tree (transparent overlapping panels) and stay alive, so another
 * invocation of this probe can inspect it with `panels <hwnd>` / `clear` -- the smoke test for the
 * live modes without needing Power BI. */
static int hold(int secs)
{
    WNDCLASSA wc;
    HWND top;
    MSG msg;
    DWORD end;

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = synth_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "wvexstyle_synth";
    RegisterClassA(&wc);
    keep_cover = 1;
    top = CreateWindowExA(0, "wvexstyle_synth", "wvexstyle hold", WS_POPUP | WS_VISIBLE,
                          0, 0, 3 * SYNTH_W, SYNTH_H, NULL, NULL, wc.hInstance, NULL);
    if (!top) return 1;
    synth_case(stdout, top, 0, "normal", 0, 0, 1);
    synth_case(stdout, top, SYNTH_W, "transparent_cover", WS_EX_TRANSPARENT, 0, 1);
    printf("HOLD root=%p for %ds\n", (void *)top, secs);
    end = GetTickCount() + secs * 1000;
    while (GetTickCount() < end)
    {
        DWORD r = MsgWaitForMultipleObjectsEx(0, NULL, 250, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        if (r == WAIT_OBJECT_0) while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
    }
    printf("HOLD done\n");
    return 0;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { printf("usage: wvexstyle.exe synth|panels [hwnd]|regions <hwnd...>|sysrgn <hwnd>|clear <0|1> [hwnd]|raise <page-fragment>|redraw <page-fragment>|hide <page-fragment>|showall|hold <secs>\n"); return 2; }
    if (!strcmp(argv[1], "synth")) return synth();
    if (!strcmp(argv[1], "panels"))
        return panels(argc > 2 ? (HWND)(ULONG_PTR)strtoull(argv[2], NULL, 16) : NULL);
    if (!strcmp(argv[1], "clear"))
        return clear_ex(argc > 2 ? atoi(argv[2]) : 0,
                        argc > 3 ? (HWND)(ULONG_PTR)strtoull(argv[3], NULL, 16) : NULL);
    if (!strcmp(argv[1], "hold")) return hold(argc > 2 ? atoi(argv[2]) : 30);
    if (!strcmp(argv[1], "raise") && argc > 2) return raise_panel(argv[2]);
    if (!strcmp(argv[1], "redraw") && argc > 2) return redraw_panel(argv[2]);
    if (!strcmp(argv[1], "hide") && argc > 2) return hide_others(argv[2]);
    if (!strcmp(argv[1], "showall")) return show_all();
    if (!strcmp(argv[1], "regions") && argc > 2)
    {
        int i;
        for (i = 2; i < argc; i++)
        {
            HWND h = (HWND)(ULONG_PTR)strtoull(argv[i], NULL, 16);
            window_report(stdout, "window", h);
            region_report_flags(stdout, "  cache", h, DCX_CACHE);
            region_report_flags(stdout, "  cache|usestyle", h, DCX_CACHE | DCX_USESTYLE);
            region_report_flags(stdout, "  cache|window", h, DCX_CACHE | DCX_WINDOW);
            region_report_flags(stdout, "  cache|clipsib|clipch", h, DCX_CACHE | DCX_CLIPSIBLINGS | DCX_CLIPCHILDREN);
            region_report_flags(stdout, "  cache|parentclip", h, DCX_CACHE | DCX_PARENTCLIP);
            region_report_flags(stdout, "  usestyle", h, DCX_USESTYLE);
        }
        return 0;
    }
    if (!strcmp(argv[1], "sysrgn") && argc > 2)
    {
        HWND h = (HWND)(ULONG_PTR)strtoull(argv[2], NULL, 16);
        window_report(stdout, "window", h);
        region_report(stdout, "sysrgn", h);
        return 0;
    }
    printf("unknown mode\n");
    return 2;
}

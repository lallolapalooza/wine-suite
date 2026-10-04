/* winzorder.c - identify Power BI Desktop's view panels and change their z-order/visibility,
 * so the question "does the screen follow the HWND z-order / visibility?" can be asked of a
 * live run in one call.
 *
 * The five view panels are siblings of the main form; each hosts
 *   Chrome_WidgetWin_0 (PBIDesktop.exe) -> Chrome_WidgetWin_1 (msedgewebview2.exe, whose window
 *   text is the page URL, e.g. ms-pbi.pbi.microsoft.com/minerva/tmdlView.html)
 * -> Chrome_RenderWidgetHostHWND.
 * So a panel is identified by the page its Chrome_WidgetWin_1 reports.
 *
 * Build: x86_64-w64-mingw32-gcc -O1 -o tools/winapi/bin/winzorder.exe tools/winapi/winzorder.c -luser32
 * Usage: winzorder.exe list
 *        winzorder.exe hide|show <page-fragment>      (SW_HIDE on the panel / SW_SHOW)
 *        winzorder.exe bottom|top <page-fragment>     (SetWindowPos HWND_BOTTOM / HWND_TOP)
 *        winzorder.exe print                          (z-order of the panels, top first)
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define MAXP 8
static HWND panels[MAXP];
static char pages[MAXP][128];
static int npanels;

static BOOL CALLBACK find_root(HWND h, LPARAM lp)
{
    DWORD pid = 0;
    char buf[MAX_PATH];
    HANDLE p;
    DWORD n = sizeof(buf);
    HWND *root = (HWND *)lp;
    char cls[256];

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
    *root = h;
    return FALSE;
}

/* the page URL lives in the panel's grandchild Chrome_WidgetWin_1 window text */
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
    HWND root = NULL, c;
    npanels = 0;
    EnumWindows(find_root, (LPARAM)&root);
    if (!root) { printf("no PBIDesktop main window\n"); return; }
    for (c = GetWindow(root, GW_CHILD); c && npanels < MAXP; c = GetWindow(c, GW_HWNDNEXT))
    {
        RECT r;
        char cls[256];
        GetClassNameA(c, cls, sizeof(cls));
        if (!strstr(cls, "WindowsForms10.Window")) continue;
        GetWindowRect(c, &r);
        if (r.right - r.left < 400) continue;              /* skip the small dialog host */
        panels[npanels] = c;
        page_of(c, pages[npanels], sizeof(pages[npanels]));
        if (!pages[npanels][0]) strcpy(pages[npanels], "(no page url)");
        npanels++;
    }
}

static void print_list(void)
{
    int i;
    scan();
    printf("main=0x%p panels=%d (EnumChildWindows order = top first)\n",
           (void *)0, npanels);
    for (i = 0; i < npanels; i++)
        printf("  z%d panel=%p vis=%d page=%s\n", i, panels[i], IsWindowVisible(panels[i]) ? 1 : 0, pages[i]);
}

static int find_frag(const char *frag)
{
    int i;
    for (i = 0; i < npanels; i++)
        if (strstr(pages[i], frag)) return i;
    return -1;
}

int main(int argc, char **argv)
{
    const char *op = argc > 1 ? argv[1] : "list";
    const char *frag = argc > 2 ? argv[2] : "";
    int i, k;

    scan();
    if (!npanels) { printf("no panels\n"); return 1; }

    if (!strcmp(op, "list") || !strcmp(op, "print"))
    {
        print_list();
        return 0;
    }
    if (!strcmp(op, "hideall") || !strcmp(op, "showall") || !strcmp(op, "bottomall"))
    {
        for (i = 0; i < npanels; i++)
        {
            if (!strcmp(op, "hideall")) ShowWindow(panels[i], SW_HIDE);
            else if (!strcmp(op, "showall")) ShowWindow(panels[i], SW_SHOW);
            else SetWindowPos(panels[i], HWND_BOTTOM, 0, 0, 0, 0,
                              SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        printf("%s: applied to %d panels\n", op, npanels);
        print_list();
        return 0;
    }

    k = find_frag(frag);
    if (k < 0) { printf("no panel matching '%s'\n", frag); print_list(); return 2; }
    if (!strcmp(op, "hide")) ShowWindow(panels[k], SW_HIDE);
    else if (!strcmp(op, "show")) ShowWindow(panels[k], SW_SHOW);
    else if (!strcmp(op, "bottom")) SetWindowPos(panels[k], HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    else if (!strcmp(op, "top")) SetWindowPos(panels[k], HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    else { printf("unknown op %s\n", op); return 2; }
    printf("%s %s -> panel=%p\n", op, pages[k], panels[k]);
    print_list();
    return 0;
}

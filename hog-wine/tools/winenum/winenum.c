/* winenum.c -- tiny Win32 helper for the Hog monitor render investigation.
 *
 *   winenum.exe list                 enumerate top-level windows (class/title/pid/vis/rect)
 *   winenum.exe find <titleSubstr>   print windows whose title contains the substring,
 *                                    then force a full repaint on each:
 *                                      InvalidateRect(hwnd, NULL, TRUE) + UpdateWindow()
 *                                      + RedrawWindow(RDW_INVALIDATE|RDW_UPDATENOW|RDW_ERASE|RDW_ALLCHILDREN)
 *   winenum.exe class <pid>          print class/title/vis/rect of every top-level window of pid
 *
 * Build (i386, to match the Hog apps):
 *   i686-w64-mingw32-gcc -O2 -municode -o winenum.exe winenum.c
 * Also build an ASCII variant used from cmd:  -municode needs wmain; keep it simple.
 */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <stdlib.h>

static void show(HWND h)
{
    WCHAR t[512] = {0}, c[256] = {0};
    DWORD pid = 0;
    RECT r = {0,0,0,0};
    GetWindowTextW(h, t, 511);
    GetClassNameW(h, c, 255);
    GetWindowThreadProcessId(h, &pid);
    GetWindowRect(h, &r);
    {
        RECT ur;
        BOOL has_update = GetUpdateRect(h, &ur, FALSE);
        DWORD style = (DWORD)GetWindowLongW(h, GWL_STYLE);
        DWORD ex = (DWORD)GetWindowLongW(h, GWL_EXSTYLE);
        HWND owner = GetWindow(h, GW_OWNER);
        HWND parent = GetParent(h);
        wprintf(L"hwnd=0x%08lx pid=%lu vis=%d class=%ls rect=(%ld,%ld)-(%ld,%ld) style=0x%08lx ex=0x%08lx owner=0x%08lx parent=0x%08lx update=%d title='%ls'\n",
                (unsigned long)(ULONG_PTR)h, (unsigned long)pid, IsWindowVisible(h) ? 1 : 0,
                c, r.left, r.top, r.right, r.bottom, (unsigned long)style, (unsigned long)ex,
                (unsigned long)(ULONG_PTR)owner, (unsigned long)(ULONG_PTR)parent,
                has_update ? 1 : 0, t);
    }
    fflush(stdout);
}

static const WCHAR *g_want;
static DWORD g_pid;
static HWND g_found2;
static const WCHAR *g_want2;

static BOOL CALLBACK enum_one(HWND h, LPARAM l)
{
    (void)l;
    WCHAR t[512] = {0};
    GetWindowTextW(h, t, 511);
    if (g_want2 && wcsstr(t, g_want2)) { g_found2 = h; return FALSE; }
    return TRUE;
}

static BOOL CALLBACK enum_list(HWND h, LPARAM l) { (void)l; show(h); return TRUE; }

static BOOL CALLBACK enum_want(HWND h, LPARAM l)
{
    (void)l;
    WCHAR t[512] = {0};
    GetWindowTextW(h, t, 511);
    if (g_want && wcsstr(t, g_want)) {
        show(h);
        wprintf(L"  -> InvalidateRect(NULL,TRUE)+UpdateWindow()+RedrawWindow(RDW_UPDATENOW|ERASE|ALLCHILDREN)\n");
        fflush(stdout);
        InvalidateRect(h, NULL, TRUE);
        UpdateWindow(h);
        RedrawWindow(h, NULL, NULL,
                     RDW_INVALIDATE | RDW_UPDATENOW | RDW_ERASE | RDW_ALLCHILDREN);
    }
    return TRUE;
}

static BOOL CALLBACK enum_pid(HWND h, LPARAM l)
{
    (void)l;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (pid == g_pid) show(h);
    return TRUE;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 2) {
        wprintf(L"usage: winenum.exe list | find <titleSubstr> | class <pid>\n");
        return 2;
    }
    if (!wcscmp(argv[1], L"watch")) {
        /* watch <titleSubstr> <iterations> : non-consuming GetUpdateRgn poll */
        int iters = argc > 3 ? _wtoi(argv[3]) : 40;
        g_want = argc > 2 ? argv[2] : L"Processor";
        for (int i = 0; i < iters; i++) {
            HWND h = NULL;
            g_found2 = NULL; g_want2 = g_want;
            EnumWindows(enum_one, 0);
            h = g_found2;
            if (!h) { wprintf(L"[%d] gone\n", i); break; }
            HRGN rgn = CreateRectRgn(0, 0, 0, 0);
            int t = GetUpdateRgn(h, rgn, FALSE);
            RECT rb = {0,0,0,0};
            GetRgnBox(rgn, &rb);
            wprintf(L"[%d] hwnd=%p vis=%d GetUpdateRgn=%d (%s) box=(%ld,%ld)-(%ld,%ld)\n",
                    i, h, IsWindowVisible(h) ? 1 : 0, t,
                    t == NULLREGION ? L"NULL" : t == SIMPLEREGION ? L"SIMPLE" : t == COMPLEXREGION ? L"COMPLEX" : L"ERROR",
                    rb.left, rb.top, rb.right, rb.bottom);
            DeleteObject(rgn);
            fflush(stdout);
            Sleep(250);
        }
    } else if (!wcscmp(argv[1], L"inv")) {
        /* inv <titleSubstr> : RedrawWindow(RDW_INVALIDATE) only -- no UPDATENOW, so any
         * repaint must come back through the normal queued WM_PAINT path */
        g_found2 = NULL; g_want2 = argc > 2 ? argv[2] : L"Processor";
        EnumWindows(enum_one, 0);
        if (!g_found2) { wprintf(L"not found\n"); return 1; }
        wprintf(L"inv hwnd=%p -> RedrawWindow(RDW_INVALIDATE)\n", g_found2);
        fflush(stdout);
        RedrawWindow(g_found2, NULL, NULL, RDW_INVALIDATE);
    } else if (!wcscmp(argv[1], L"val")) {
        /* val <titleSubstr> : ValidateRect(h, NULL) -- refused by the server if the
         * window is not visible to it */
        g_found2 = NULL; g_want2 = argc > 2 ? argv[2] : L"Processor";
        EnumWindows(enum_one, 0);
        if (!g_found2) { wprintf(L"not found\n"); return 1; }
        wprintf(L"val hwnd=%p -> ValidateRect(NULL)\n", g_found2);
        fflush(stdout);
        ValidateRect(g_found2, NULL);
    } else if (!wcscmp(argv[1], L"poke")) {
        /* poke <titleSubstr> : ValidateRect (clear region) then InvalidateRect (set it
         * fresh, so the server increments its paint_count) -- still no UpdateWindow, so a
         * repaint must arrive via the queued WM_PAINT path */
        g_found2 = NULL; g_want2 = argc > 2 ? argv[2] : L"Processor";
        EnumWindows(enum_one, 0);
        if (!g_found2) { wprintf(L"not found\n"); return 1; }
        wprintf(L"poke hwnd=%p -> ValidateRect + InvalidateRect(TRUE)\n", g_found2);
        fflush(stdout);
        ValidateRect(g_found2, NULL);
        InvalidateRect(g_found2, NULL, TRUE);
    } else if (!wcscmp(argv[1], L"postpaint")) {
        /* postpaint <titleSubstr> : PostMessage(WM_PAINT) -- bypass Wine's paint-message
         * generation entirely; proves the app's own paint path works */
        g_found2 = NULL; g_want2 = argc > 2 ? argv[2] : L"Processor";
        EnumWindows(enum_one, 0);
        if (!g_found2) { wprintf(L"not found\n"); return 1; }
        wprintf(L"postpaint hwnd=%p -> PostMessage(WM_PAINT)\n", g_found2);
        fflush(stdout);
        PostMessageW(g_found2, WM_PAINT, 0, 0);
    } else if (!wcscmp(argv[1], L"classstyle")) {
        g_found2 = NULL; g_want2 = argc > 2 ? argv[2] : L"Processor";
        EnumWindows(enum_one, 0);
        if (!g_found2) { wprintf(L"not found\n"); return 1; }
        wprintf(L"classstyle hwnd=%p GCL_STYLE=0x%08lx GCLP_HBRBACKGROUND=%p\n", g_found2,
                (unsigned long)GetClassLongW(g_found2, GCL_STYLE),
                (void*)GetClassLongPtrW(g_found2, GCLP_HBRBACKGROUND));
    } else if (!wcscmp(argv[1], L"list")) {
        EnumWindows(enum_list, 0);
    } else if (!wcscmp(argv[1], L"find")) {
        g_want = argc > 2 ? argv[2] : L"Processor";
        EnumWindows(enum_want, 0);
    } else if (!wcscmp(argv[1], L"class")) {
        g_pid = argc > 2 ? (DWORD)wcstoul(argv[2], NULL, 10) : 0;
        EnumWindows(enum_pid, 0);
    } else {
        wprintf(L"unknown command\n");
        return 2;
    }
    return 0;
}

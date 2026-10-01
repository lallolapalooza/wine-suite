/* glchild.c — reproduce "an OpenGL child window flickers black" without Solid Edge.
 *
 * Solid Edge's viewport is an OpenGL context on a child window of its frame (render.dll imports
 * OPENGL32/GLU32/wglGetProcAddress), and the reported symptom is that the sketch viewport
 * flickers black continuously.  This program builds the same shape — a frame that paints a
 * background on WM_PAINT and a GL child that draws and SwapBuffers — so the mechanism can be
 * isolated from the application and a Wine change can be judged by a black-frame count.
 *
 * usage: glchild.exe [options] [seconds]
 *   --no-clipchildren   parent without WS_CLIPCHILDREN
 *   --single            single buffered pixel format (no PFD_DOUBLEBUFFER)
 *   --no-ownpaint       parent does not paint at all (no WM_ERASEBKGND/WM_PAINT work)
 *   --no-invalidate     parent never invalidates itself
 *   --swapinterval N    wglSwapIntervalEXT(N)
 *   --childstyle hex    override the child window style, e.g. 0x56000000
 *   --print             print each paint/swap to stdout (rate evidence)
 *
 * The window title is "glchild" so `import -window` / xdotool can find it, and the child is
 * filled with a colour that alternates slowly (so a frozen frame is distinguishable from a live
 * one).  A black child area is the failure: it means the parent's background reached the screen
 * where the GL surface should be.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -Wall -o glchild.exe glchild.c -lopengl32 -lgdi32 -luser32
 */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef BOOL (WINAPI *PFNWGLSWAPINTERVALEXTPROC)(int);
typedef void *(WINAPI *PFNWGLGETPROCADDRESSPROC)(const char *);

static int opt_clipchildren = 1;
static int opt_doublebuffer = 1;
static int opt_parentpaint = 1;
static int opt_invalidate = 1;
static int opt_print = 0;
static int opt_swapinterval = 0;
static DWORD opt_childstyle = WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS;
static int opt_layered = 0;      /* WS_EX_LAYERED + SetLayeredWindowAttributes on the frame */
static int opt_rgn = 0;          /* SetWindowRgn (rounded) on the frame */
static int run_seconds = 20;

static HWND frame, child;
static HGLRC glrc;
static HDC glhdc;
static int paint_count, swap_count, child_paint_count, erase_count;
static long long swap_us_total, swap_us_max;
static unsigned char bg = 0x20;
static DWORD start_tick;

static void say(const char *what)
{
    DWORD t = GetTickCount() - start_tick;
    printf("%6lu ms  %s  frame_paint=%d erase=%d child_paint=%d swaps=%d\n",
           (unsigned long)t, what, paint_count, erase_count, child_paint_count, swap_count);
    fflush(stdout);
}

static LRESULT CALLBACK child_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_PAINT:
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        if (glhdc && wglMakeCurrent(glhdc, glrc)) {
            int w = ps.rcPaint.right - ps.rcPaint.left, h = ps.rcPaint.bottom - ps.rcPaint.top;
            /* a colour that changes once a second, so a stalled frame is visible */
            double phase = (double)((GetTickCount() / 1000) % 6) / 6.0;
            if (w <= 0) w = 1;
            if (h <= 0) h = 1;
            glViewport(0, 0, w, h);
            glClearColor((float)(0.15 + 0.6 * phase), 0.35f, (float)(0.8 - 0.6 * phase), 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            glMatrixMode(GL_PROJECTION); glLoadIdentity();
            glMatrixMode(GL_MODELVIEW); glLoadIdentity();
            glBegin(GL_TRIANGLES);
            glColor3f(1, 1, 0); glVertex2f(-0.5f, -0.5f);
            glColor3f(0, 1, 1); glVertex2f(0.5f, -0.5f);
            glColor3f(1, 0, 1); glVertex2f(0.0f, 0.5f);
            glEnd();
        }
        {
            LARGE_INTEGER f, t0, t1;
            QueryPerformanceFrequency(&f);
            QueryPerformanceCounter(&t0);
            SwapBuffers(hdc);
            QueryPerformanceCounter(&t1);
            swap_us_total += (t1.QuadPart - t0.QuadPart) * 1000000 / f.QuadPart;
            if ((t1.QuadPart - t0.QuadPart) * 1000000 / f.QuadPart > swap_us_max)
                swap_us_max = (t1.QuadPart - t0.QuadPart) * 1000000 / f.QuadPart;
            swap_count++;
        }
        EndPaint(hwnd, &ps);
        child_paint_count++;
        if (opt_print) say("child WM_PAINT+SwapBuffers");
        return 0;
    }
    case WM_ERASEBKGND:
        /* Windows does not let a child's GL surface survive an erase it asked for; the real
         * question is whether saying "erased" here is what makes the parent's paint show. */
        return 1;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

static LRESULT CALLBACK frame_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_ERASEBKGND:
        erase_count++;
        if (!opt_parentpaint) return 1;
        return DefWindowProcA(hwnd, msg, wp, lp);
    case WM_PAINT:
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        if (opt_parentpaint) {
            HBRUSH br = CreateSolidBrush(RGB(bg, bg, bg));
            FillRect(hdc, &ps.rcPaint, br);
            DeleteObject(br);
        }
        EndPaint(hwnd, &ps);
        paint_count++;
        if (opt_print) say("frame WM_PAINT");
        return 0;
    }
    case WM_TIMER:
        if (opt_invalidate) InvalidateRect(hwnd, NULL, TRUE);
        return 0;
    case WM_SIZE:
        if (child) MoveWindow(child, 4, 4, LOWORD(lp) - 8, HIWORD(lp) - 8, TRUE);
        return 0;
    case WM_CLOSE:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int main(int argc, char **argv)
{
    WNDCLASSA wc = {0};
    MSG msg;
    PIXELFORMATDESCRIPTOR pfd;
    PFNWGLGETPROCADDRESSPROC wglGetProcAddressP;
    PFNWGLSWAPINTERVALEXTPROC wglSwapIntervalEXT;
    HMODULE glmod;
    int i, fmt;
    DWORD end_tick;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--no-clipchildren")) opt_clipchildren = 0;
        else if (!strcmp(argv[i], "--single")) opt_doublebuffer = 0;
        else if (!strcmp(argv[i], "--no-ownpaint")) opt_parentpaint = 0;
        else if (!strcmp(argv[i], "--no-invalidate")) opt_invalidate = 0;
        else if (!strcmp(argv[i], "--print")) opt_print = 1;
        else if (!strcmp(argv[i], "--swapinterval") && i + 1 < argc) opt_swapinterval = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--childstyle") && i + 1 < argc) opt_childstyle = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--layered")) opt_layered = 1;
        else if (!strcmp(argv[i], "--rgn")) opt_rgn = 1;
        else run_seconds = atoi(argv[i]);
    }
    printf("glchild: clipchildren=%d doublebuffer=%d parentpaint=%d invalidate=%d swapinterval=%d childstyle=%#lx layered=%d rgn=%d secs=%d\n",
           opt_clipchildren, opt_doublebuffer, opt_parentpaint, opt_invalidate, opt_swapinterval,
           (unsigned long)opt_childstyle, opt_layered, opt_rgn, run_seconds);

    wc.lpfnWndProc = frame_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "glchild_frame";
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassA(&wc);

    wc.lpfnWndProc = child_proc;
    wc.lpszClassName = "glchild_child";
    RegisterClassA(&wc);

    frame = CreateWindowExA(opt_layered ? WS_EX_LAYERED : 0, "glchild_frame", "glchild",
                            WS_OVERLAPPEDWINDOW | WS_VISIBLE |
                            (opt_clipchildren ? WS_CLIPCHILDREN : 0),
                            40, 40, 800, 600, NULL, NULL, wc.hInstance, NULL);
    if (!frame) { printf("frame CreateWindow failed %lu\n", GetLastError()); return 1; }
    if (opt_layered) {
        /* Solid Edge's frame does this (control.dll/ToolkitPro import SetLayeredWindowAttributes
         * and UpdateLayeredWindow), and puts a rounded region on it (it asks DWM for
         * DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND). */
        BOOL ok = SetLayeredWindowAttributes(frame, 0, 255, LWA_ALPHA);
        printf("SetLayeredWindowAttributes(LWA_ALPHA,255) -> %d (err %lu)\n", ok, GetLastError());
    }
    if (opt_rgn) {
        HRGN rgn = CreateRoundRectRgn(0, 0, 801, 601, 24, 24);
        BOOL ok = SetWindowRgn(frame, rgn, TRUE);
        printf("SetWindowRgn(round) -> %d (err %lu)\n", ok, GetLastError());
    }

    child = CreateWindowExA(0, "glchild_child", "", opt_childstyle,
                            4, 4, 780, 560, frame, NULL, wc.hInstance, NULL);
    if (!child) { printf("child CreateWindow failed %lu\n", GetLastError()); return 1; }

    glhdc = GetDC(child);
    memset(&pfd, 0, sizeof(pfd));
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | (opt_doublebuffer ? PFD_DOUBLEBUFFER : 0);
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    fmt = ChoosePixelFormat(glhdc, &pfd);
    printf("ChoosePixelFormat -> %d\n", fmt);
    if (!fmt || !SetPixelFormat(glhdc, fmt, &pfd)) {
        printf("SetPixelFormat failed %lu\n", GetLastError());
        return 1;
    }
    glrc = wglCreateContext(glhdc);
    printf("wglCreateContext -> %p\n", (void *)glrc);
    if (!glrc) return 1;
    wglMakeCurrent(glhdc, glrc);

    glmod = LoadLibraryA("opengl32.dll");
    wglGetProcAddressP = (PFNWGLGETPROCADDRESSPROC)GetProcAddress(glmod, "wglGetProcAddress");
    if (wglGetProcAddressP) {
        wglSwapIntervalEXT = (PFNWGLSWAPINTERVALEXTPROC)wglGetProcAddressP("wglSwapIntervalEXT");
        if (wglSwapIntervalEXT && opt_swapinterval) wglSwapIntervalEXT(opt_swapinterval);
    }
    printf("GL_RENDERER = %s\n", (const char *)glGetString(GL_RENDERER));

    ShowWindow(frame, SW_SHOW);
    UpdateWindow(frame);
    SetTimer(frame, 1, 50, NULL);            /* parent repaints every 50 ms, like a busy UI */
    start_tick = GetTickCount();
    say("start");

    end_tick = start_tick + run_seconds * 1000;
    while (GetTickCount() < end_tick) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        /* the child redraws on its own timer too, at ~30 Hz */
        InvalidateRect(child, NULL, FALSE);
        Sleep(16);
    }

    say("end");
    printf("SUMMARY frame_paint=%d erase=%d child_paint=%d swaps=%d swap_avg_us=%lld swap_max_us=%lld\n",
           paint_count, erase_count, child_paint_count, swap_count,
           swap_count ? swap_us_total / swap_count : 0, swap_us_max);
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(glrc);
    DestroyWindow(child);
    DestroyWindow(frame);
    return 0;
}

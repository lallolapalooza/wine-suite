/* swapprobe.c — time SwapBuffers on a top-level window and on the same window's child.
 *
 * Found with this probe: under Wine on the VNC display, SwapBuffers on a **child** window takes
 * ~920 ms (independent of the swap interval), while the same GL content in a top-level window
 * swaps immediately.  A viewport that presents once per second and is erased in between is
 * exactly "the viewport flickers black continuously".
 *
 * usage: swapprobe.exe [--child] [--swapinterval N] [--frames N] [--no-ownerdraw] [--size WxH]
 *
 * build: x86_64-w64-mingw32-gcc -O1 -Wall -o swapprobe.exe swapprobe.c -lopengl32 -lgdi32 -luser32
 */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

typedef BOOL (WINAPI *PFNWGLSWAPINTERVALEXTPROC)(int);
typedef void *(WINAPI *PFNWGLGETPROCADDRESSPROC)(const char *);

static int use_child = 0, frames = 60, interval = 0;
static int width = 640, height = 480;
static HWND top, target;

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_PAINT) { PAINTSTRUCT ps; BeginPaint(h, &ps); EndPaint(h, &ps); return 0; }
    if (m == WM_CLOSE) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

static double now_ms(LARGE_INTEGER freq)
{
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)freq.QuadPart;
}

int main(int argc, char **argv)
{
    WNDCLASSA wc = {0};
    HDC hdc;
    HGLRC rc;
    PIXELFORMATDESCRIPTOR pfd;
    PFNWGLGETPROCADDRESSPROC wglGetProcAddressP;
    PFNWGLSWAPINTERVALEXTPROC wglSwapIntervalEXT;
    LARGE_INTEGER freq;
    double best = 1e18, worst = 0, total = 0, t0, t1;
    int fmt, i;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--child")) use_child = 1;
        else if (!strcmp(argv[i], "--swapinterval") && i + 1 < argc) interval = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--size") && i + 1 < argc) sscanf(argv[++i], "%dx%d", &width, &height);
    }
    QueryPerformanceFrequency(&freq);

    wc.lpfnWndProc = proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "swapprobe";
    RegisterClassA(&wc);
    top = CreateWindowExA(0, "swapprobe", "swapprobe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                          20, 20, width + 16, height + 60, NULL, NULL, wc.hInstance, NULL);
    if (use_child)
        target = CreateWindowExA(0, "swapprobe", "", WS_CHILD | WS_VISIBLE,
                                 8, 8, width, height, top, NULL, wc.hInstance, NULL);
    else
        target = top;
    ShowWindow(top, SW_SHOW);
    UpdateWindow(top);
    for (i = 0; i < 50; i++) { MSG m; while (PeekMessageA(&m, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageA(&m); } Sleep(10); }

    hdc = GetDC(target);
    memset(&pfd, 0, sizeof(pfd));
    pfd.nSize = sizeof(pfd); pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32; pfd.cDepthBits = 24;
    fmt = ChoosePixelFormat(hdc, &pfd);
    SetPixelFormat(hdc, fmt, &pfd);
    rc = wglCreateContext(hdc);
    wglMakeCurrent(hdc, rc);

    wglGetProcAddressP = (PFNWGLGETPROCADDRESSPROC)GetProcAddress(GetModuleHandleA("opengl32.dll"), "wglGetProcAddress");
    if (wglGetProcAddressP) {
        wglSwapIntervalEXT = (PFNWGLSWAPINTERVALEXTPROC)wglGetProcAddressP("wglSwapIntervalEXT");
        if (wglSwapIntervalEXT) wglSwapIntervalEXT(interval);
    }
    printf("window=%s size=%dx%d interval=%d renderer=%s\n",
           use_child ? "child" : "top-level", width, height, interval, (const char *)glGetString(GL_RENDERER));

    glViewport(0, 0, width, height);
    for (i = 0; i < frames; i++) {
        glClearColor((float)0.2, 0.4f, 0.6f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glFlush();
        t0 = now_ms(freq);
        SwapBuffers(hdc);
        t1 = now_ms(freq);
        total += t1 - t0;
        if (t1 - t0 < best) best = t1 - t0;
        if (t1 - t0 > worst) worst = t1 - t0;
    }
    printf("SwapBuffers x%d: avg %.2f ms  min %.2f ms  max %.2f ms  (%.1f fps)\n",
           frames, total / frames, best, worst, 1000.0 / (total / frames));

    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(rc);
    if (use_child) DestroyWindow(target);
    DestroyWindow(top);
    return 0;
}

/* glclear.c — control probe: an OpenGL window that clears to a known colour and stays open.
 *
 * Used to test whether an X screenshot of the Wine display can see GL-rendered window content
 * (Arena's windows capture as pure black; this decides whether that is real or a capture artifact).
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o glclear.exe glclear.c -lgdi32 -lopengl32 -luser32
 */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>

static int running = 1;

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_CLOSE) { running = 0; return 0; }
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

int main(void)
{
    WNDCLASSA wc = {0};
    HWND hwnd;
    HDC hdc;
    HGLRC rc;
    PIXELFORMATDESCRIPTOR pfd = {0};
    int fmt;
    MSG msg;

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "glclear";
    RegisterClassA(&wc);
    hwnd = CreateWindowA("glclear", "glclear", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         50, 50, 400, 300, NULL, NULL, wc.hInstance, NULL);
    hdc = GetDC(hwnd);
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    fmt = ChoosePixelFormat(hdc, &pfd);
    SetPixelFormat(hdc, fmt, &pfd);
    rc = wglCreateContext(hdc);
    wglMakeCurrent(hdc, rc);
    fprintf(stderr, "GL_VERSION=%s\n", (const char *)glGetString(GL_VERSION));

    while (running) {
        /* magenta so it cannot be confused with a black default */
        glClearColor(1.0f, 0.0f, 1.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        SwapBuffers(hdc);
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        Sleep(16);
    }
    return 0;
}

/* wglprobe.c — what the platform says about OpenGL pixel formats and WGL extensions.
 *
 * Solid Edge's render.dll probes the graphic subsystem (Visual.dll exports
 * SupportsOpenGL(HDC, DWORD), JValidateGraphicSubsystem(), JCreateGDI2OpenGL()) and picks
 * between an accelerated GL path and a fallback.  The decision rests on the pixel-format
 * flags ChoosePixelFormat/DescribePixelFormat report, so print them, plus the extension set
 * and the GL version strings.
 *
 * Run on Windows and under Wine and diff.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -Wall -o wglprobe.exe wglprobe.c -lopengl32 -lgdi32 -luser32
 */
#include <windows.h>
#include <stdio.h>

typedef const char *(WINAPI *PFNGETSTRINGPROC)(unsigned int);
typedef void *(WINAPI *PFNWGLGETPROCADDRESSPROC)(const char *);
typedef int (WINAPI *PFNWGLCHOOSEPIXELFORMATARBPROC)(HDC, const int *, const unsigned int *,
                                                     unsigned int, int *, unsigned int *);
typedef const char *(WINAPI *PFNWGLGETEXTENSIONSSTRINGARBPROC)(HDC);
typedef const char *(WINAPI *PFNWGLGETEXTENSIONSSTRINGEXTPROC)(void);
typedef HGLRC (WINAPI *PFNWGLCREATECONTEXTATTRIBSARBPROC)(HDC, HGLRC, const int *);
typedef BOOL (WINAPI *PFNWGLSWAPINTERVALEXTPROC)(int);

#define PFD_FLAGS_STR(buf, f) do {                                        \
    sprintf(buf, "%s%s%s%s%s%s%s%s%s%s",                                  \
        ((f) & PFD_DOUBLEBUFFER) ? "DOUBLEBUFFER " : "",                   \
        ((f) & PFD_DRAW_TO_WINDOW) ? "DRAW_TO_WINDOW " : "",               \
        ((f) & PFD_DRAW_TO_BITMAP) ? "DRAW_TO_BITMAP " : "",               \
        ((f) & PFD_SUPPORT_GDI) ? "SUPPORT_GDI " : "",                     \
        ((f) & PFD_SUPPORT_OPENGL) ? "SUPPORT_OPENGL " : "",               \
        ((f) & PFD_GENERIC_FORMAT) ? "GENERIC_FORMAT " : "",               \
        ((f) & PFD_GENERIC_ACCELERATED) ? "GENERIC_ACCELERATED " : "",     \
        ((f) & PFD_NEED_PALETTE) ? "NEED_PALETTE " : "",                   \
        ((f) & PFD_SWAP_EXCHANGE) ? "SWAP_EXCHANGE " : "",                 \
        ((f) & PFD_SWAP_COPY) ? "SWAP_COPY " : "");                        \
} while (0)

static const char *type_str(BYTE t)
{
    switch (t) {
    case 0: return "RGBA";
    case 1: return "COLORINDEX";
    default: return "?";
    }
}

int main(void)
{
    HWND hwnd;
    HDC hdc;
    PIXELFORMATDESCRIPTOR pfd, got;
    HGLRC gl;
    int fmt, n, i, count;
    char flags[256];
    PFNGETSTRINGPROC pglGetString;
    PFNWGLGETPROCADDRESSPROC pwglGetProcAddress;
    PFNWGLCHOOSEPIXELFORMATARBPROC pwglChoosePixelFormatARB;
    PFNWGLGETEXTENSIONSSTRINGARBPROC pwglGetExtensionsStringARB;
    PFNWGLGETEXTENSIONSSTRINGEXTPROC pwglGetExtensionsStringEXT;
    PFNWGLCREATECONTEXTATTRIBSARBPROC pwglCreateContextAttribsARB;
    PFNWGLSWAPINTERVALEXTPROC pwglSwapIntervalEXT;
    HMODULE gl_module;

    hwnd = CreateWindowExA(0, "STATIC", "wglprobe", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                           50, 50, 320, 240, NULL, NULL, NULL, NULL);
    if (!hwnd) { printf("CreateWindow failed %lu\n", GetLastError()); return 1; }
    hdc = GetDC(hwnd);
    printf("hwnd %p hdc %p\n\n", (void *)hwnd, (void *)hdc);

    memset(&pfd, 0, sizeof(pfd));
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;

    n = DescribePixelFormat(hdc, 1, 0, NULL);
    printf("DescribePixelFormat(hdc, 1, 0, NULL) = %d   (number of pixel formats)\n", n);

    fmt = ChoosePixelFormat(hdc, &pfd);
    printf("ChoosePixelFormat(RGBA32+DBL+depth24+stencil8) = %d  (last error %lu)\n", fmt, GetLastError());
    if (!fmt) { printf("no pixel format\n"); return 1; }

    memset(&got, 0, sizeof(got));
    got.nSize = sizeof(got);
    got.nVersion = 1;
    if (DescribePixelFormat(hdc, fmt, sizeof(got), &got)) {
        PFD_FLAGS_STR(flags, got.dwFlags);
        printf("  chosen: id=%d type=%s color=%u depth=%u stencil=%u accum=%u/%u/%u/%u flags=%s\n",
               fmt, type_str(got.iPixelType), got.cColorBits, got.cDepthBits, got.cStencilBits,
               got.cAccumBits, got.cAccumRedBits, got.cAccumGreenBits, got.cAccumBlueBits, flags);
    } else printf("  DescribePixelFormat(chosen) failed %lu\n", GetLastError());

    printf("\n-- all pixel formats\n");
    count = DescribePixelFormat(hdc, 1, 0, NULL);
    for (i = 1; i <= count; i++) {
        memset(&got, 0, sizeof(got));
        got.nSize = sizeof(got);
        got.nVersion = 1;
        if (!DescribePixelFormat(hdc, i, sizeof(got), &got)) continue;
        if (!(got.dwFlags & PFD_SUPPORT_OPENGL)) continue;
        PFD_FLAGS_STR(flags, got.dwFlags);
        printf("  %3d type=%-10s color=%2u depth=%2u stencil=%2u %s\n",
               i, type_str(got.iPixelType), got.cColorBits, got.cDepthBits, got.cStencilBits, flags);
    }

    if (!SetPixelFormat(hdc, fmt, &pfd))
        printf("SetPixelFormat(%d) failed %lu\n", fmt, GetLastError());
    else
        printf("SetPixelFormat(%d) ok\n", fmt);

    gl_module = LoadLibraryA("opengl32.dll");
    pglGetString = (PFNGETSTRINGPROC)GetProcAddress(gl_module, "glGetString");
    pwglGetProcAddress = (PFNWGLGETPROCADDRESSPROC)GetProcAddress(gl_module, "wglGetProcAddress");

    gl = wglCreateContext(hdc);
    printf("\n-- context\nwglCreateContext = %p (last error %lu)\n", (void *)gl, GetLastError());
    if (gl) {
        if (!wglMakeCurrent(hdc, gl)) printf("wglMakeCurrent failed %lu\n", GetLastError());
        else {
            printf("glGetString(GL_VENDOR)   = %s\n", pglGetString(0x1F00));
            printf("glGetString(GL_RENDERER) = %s\n", pglGetString(0x1F01));
            printf("glGetString(GL_VERSION)  = %s\n", pglGetString(0x1F02));
            pwglGetExtensionsStringEXT = (PFNWGLGETEXTENSIONSSTRINGEXTPROC)pwglGetProcAddress("wglGetExtensionsStringEXT");
            pwglGetExtensionsStringARB = (PFNWGLGETEXTENSIONSSTRINGARBPROC)pwglGetProcAddress("wglGetExtensionsStringARB");
            printf("wglGetExtensionsStringARB = %p\nwglGetExtensionsStringEXT = %p\n",
                   (void *)pwglGetExtensionsStringARB, (void *)pwglGetExtensionsStringEXT);
            if (pwglGetExtensionsStringARB) printf("ARB extensions: %s\n", pwglGetExtensionsStringARB(hdc));
            if (pwglGetExtensionsStringEXT) printf("EXT extensions: %s\n", pwglGetExtensionsStringEXT());
        }
    }

    pwglChoosePixelFormatARB = (PFNWGLCHOOSEPIXELFORMATARBPROC)pwglGetProcAddress("wglChoosePixelFormatARB");
    pwglCreateContextAttribsARB = (PFNWGLCREATECONTEXTATTRIBSARBPROC)pwglGetProcAddress("wglCreateContextAttribsARB");
    pwglSwapIntervalEXT = (PFNWGLSWAPINTERVALEXTPROC)pwglGetProcAddress("wglSwapIntervalEXT");
    printf("\n-- procs\n");
    printf("wglChoosePixelFormatARB      = %p\n", (void *)pwglChoosePixelFormatARB);
    printf("wglCreateContextAttribsARB   = %p\n", (void *)pwglCreateContextAttribsARB);
    printf("wglSwapIntervalEXT           = %p\n", (void *)pwglSwapIntervalEXT);
    if (pwglSwapIntervalEXT) printf("  wglSwapIntervalEXT(1) = %d\n", pwglSwapIntervalEXT(1));

    if (pwglChoosePixelFormatARB) {
        const int attribs[] = { 0x2001 /* WGL_DRAW_TO_WINDOW_ARB */, 1,
                                0x2002 /* WGL_SUPPORT_OPENGL_ARB */, 1,
                                0x2010 /* WGL_DOUBLE_BUFFER_ARB */, 1,
                                0x2011 /* WGL_PIXEL_TYPE_ARB */, 0x202B /* RGBA */,
                                0x2013 /* WGL_COLOR_BITS_ARB */, 32,
                                0x2022 /* WGL_DEPTH_BITS_ARB */, 24,
                                0 };
        unsigned int nformats = 0, chosen = 0;
        int ok = pwglChoosePixelFormatARB(hdc, attribs, NULL, 1, (int *)&chosen, &nformats);
        printf("  wglChoosePixelFormatARB -> %d err=%lu nformats=%u format=%u\n",
               ok, GetLastError(), nformats, chosen);
    }

    if (gl) { wglMakeCurrent(NULL, NULL); wglDeleteContext(gl); }
    ReleaseDC(hwnd, hdc);
    DestroyWindow(hwnd);
    printf("\ndone\n");
    return 0;
}

#include <string.h>

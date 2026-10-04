/* glprobe.c — measure what OpenGL/WGL the host actually gives a Windows PE.
 *
 * Differential probe: run it on the Windows guest and under Wine and diff the output.
 * It reports the GL/GLSL version strings, the renderer/vendor, the WGL extension list, and
 * whether WGL_ARB_create_context can produce the 4.1+ context Arena requires.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o glprobe.exe glprobe.c -lgdi32 -lopengl32
 */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>

/* mingw's GL/gl.h is GL 1.1 only */
#ifndef GL_SHADING_LANGUAGE_VERSION
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#endif

typedef HGLRC (WINAPI *pfn_wglCreateContextAttribsARB)(HDC, HGLRC, const int *);
typedef const char * (WINAPI *pfn_wglGetExtensionsStringARB)(HDC);
typedef BOOL (WINAPI *pfn_wglSwapIntervalEXT)(int);

#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB  0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x00000001

static const char *gl_str(unsigned name)
{
    const char *s = (const char *)glGetString(name);
    return s ? s : "(null)";
}

int main(void)
{
    WNDCLASSA wc = {0};
    HWND hwnd;
    HDC hdc;
    HGLRC rc, rc41 = NULL;
    PIXELFORMATDESCRIPTOR pfd = {0};
    int fmt;
    const char *ext;
    pfn_wglCreateContextAttribsARB create_ctx;
    pfn_wglGetExtensionsStringARB get_ext;
    pfn_wglSwapIntervalEXT swap_interval;
    static const int attribs[] = {
        WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
        WGL_CONTEXT_MINOR_VERSION_ARB, 1,
        WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        0
    };

    setvbuf(stdout, NULL, _IONBF, 0);

    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "glprobe";
    if (!RegisterClassA(&wc)) { printf("RegisterClass failed %lu\n", GetLastError()); return 2; }
    hwnd = CreateWindowA("glprobe", "glprobe", WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("CreateWindow failed %lu\n", GetLastError()); return 2; }
    hdc = GetDC(hwnd);
    if (!hdc) { printf("GetDC failed %lu\n", GetLastError()); return 2; }

    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    fmt = ChoosePixelFormat(hdc, &pfd);
    printf("ChoosePixelFormat = %d\n", fmt);
    if (!fmt) { printf("no pixel format, GDI Generic only\n"); return 1; }
    if (!SetPixelFormat(hdc, fmt, &pfd)) { printf("SetPixelFormat failed %lu\n", GetLastError()); return 1; }

    rc = wglCreateContext(hdc);
    printf("wglCreateContext = %p\n", (void *)rc);
    if (!rc) { printf("no GL context\n"); return 1; }
    if (!wglMakeCurrent(hdc, rc)) { printf("wglMakeCurrent failed %lu\n", GetLastError()); return 1; }

    printf("GL_VERSION  = %s\n", gl_str(GL_VERSION));
    printf("GL_VENDOR   = %s\n", gl_str(GL_VENDOR));
    printf("GL_RENDERER = %s\n", gl_str(GL_RENDERER));
    printf("GLSL        = %s\n", gl_str(GL_SHADING_LANGUAGE_VERSION));

    get_ext = (pfn_wglGetExtensionsStringARB)wglGetProcAddress("wglGetExtensionsStringARB");
    ext = get_ext ? get_ext(hdc) : NULL;
    printf("WGL_extensions = %s\n", ext ? ext : "(none)");
    swap_interval = (pfn_wglSwapIntervalEXT)wglGetProcAddress("wglSwapIntervalEXT");
    printf("wglSwapIntervalEXT = %s\n", swap_interval ? "present" : "absent");

    create_ctx = (pfn_wglCreateContextAttribsARB)wglGetProcAddress("wglCreateContextAttribsARB");
    printf("wglCreateContextAttribsARB = %s\n", create_ctx ? "present" : "absent");
    if (create_ctx) {
        rc41 = create_ctx(hdc, NULL, attribs);
        printf("4.1 core context = %p\n", (void *)rc41);
        if (rc41) {
            wglMakeCurrent(hdc, rc41);
            printf("GL41_VERSION = %s\n", gl_str(GL_VERSION));
            printf("GL41_RENDERER= %s\n", gl_str(GL_RENDERER));
        }
    }
    return 0;
}

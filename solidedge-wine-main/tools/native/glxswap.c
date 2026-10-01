/* glxswap.c — the control experiment for the SwapBuffers timing: a *native* X client doing
 * glXSwapBuffers with a swap interval, on the same display Wine was measured on.
 *
 * If the native client is also slow, the display/driver is what blocks and a Wine-side change
 * cannot fix it; if the native client is fast, the block is in Wine.
 *
 * build: gcc -O1 -Wall -o glxswap glxswap.c -lGL -lX11
 * usage: glxswap [interval] [frames] [WxH]
 */
#include <X11/Xlib.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef void (*PFNSWAPINTERVALEXT)(Display *, GLXDrawable, int);

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

int main(int argc, char **argv)
{
    Display *dpy;
    Window win;
    XVisualInfo *vi;
    GLXContext ctx;
    GLXDrawable draw;
    int interval = argc > 1 ? atoi(argv[1]) : 1;
    int frames = argc > 2 ? atoi(argv[2]) : 60;
    int w = 640, h = 480;
    int attribs[] = { GLX_RGBA, GLX_DOUBLEBUFFER, GLX_DEPTH_SIZE, 24, None };
    PFNSWAPINTERVALEXT p_swap_interval;
    double best = 1e18, worst = 0, total = 0;
    int i;

    if (argc > 3) sscanf(argv[3], "%dx%d", &w, &h);

    dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "cannot open display\n"); return 1; }
    vi = glXChooseVisual(dpy, DefaultScreen(dpy), attribs);
    if (!vi) { fprintf(stderr, "no GLX visual\n"); return 1; }
    win = XCreateSimpleWindow(dpy, RootWindow(dpy, vi->screen), 30, 30, w, h, 0, 0, 0);
    XMapWindow(dpy, win);
    XStoreName(dpy, win, "glxswap");
    for (i = 0; i < 50; i++) { XFlush(dpy); usleep(10000); }

    ctx = glXCreateContext(dpy, vi, NULL, True);
    if (!ctx) { fprintf(stderr, "no GLX context\n"); return 1; }
    glXMakeCurrent(dpy, win, ctx);
    draw = win;

    p_swap_interval = (PFNSWAPINTERVALEXT)glXGetProcAddress((const GLubyte *)"glXSwapIntervalEXT");
    if (p_swap_interval) p_swap_interval(dpy, draw, interval);
    else fprintf(stderr, "no glXSwapIntervalEXT; interval stays at the driver default\n");

    printf("display=%s renderer=%s interval=%d window=%dx%d\n", DisplayString(dpy),
           (const char *)glGetString(GL_RENDERER), interval, w, h);

    glViewport(0, 0, w, h);
    for (i = 0; i < frames; i++) {
        double t0, t1;
        glClearColor(0.2f, 0.4f, 0.6f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glFlush();
        t0 = now_ms();
        glXSwapBuffers(dpy, draw);
        t1 = now_ms();
        total += t1 - t0;
        if (t1 - t0 < best) best = t1 - t0;
        if (t1 - t0 > worst) worst = t1 - t0;
    }
    printf("glXSwapBuffers x%d: avg %.2f ms  min %.2f ms  max %.2f ms  (%.1f fps)\n",
           frames, total / frames, best, worst, 1000.0 / (total / frames));

    glXMakeCurrent(dpy, None, NULL);
    glXDestroyContext(dpy, ctx);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    return 0;
}

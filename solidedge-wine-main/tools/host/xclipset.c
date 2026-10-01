/* xclipset.c — own the X CLIPBOARD/PRIMARY selection with a string, so a Windows dialog running
 * under Wine can paste it with Ctrl+V.
 *
 * Driving a Wine dialog by synthesising keystrokes is unreliable here (measured: `xdotool type`
 * without --window loses and mangles characters on this X server — "C:\t.par" arrived as
 * "Cit par"), and XSendEvent delivery to a specific window is ignored by the common dialog's
 * edit control.  Owning the selection and pasting is one keystroke and always exact.
 *
 * usage: xclipset 'text to place on the clipboard' [seconds]     # default 30 s, then exits
 *        xclipset 'text' 0                                       # stay until killed
 *
 * build: gcc -O1 -Wall -o xclipset xclipset.c -lX11
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    Display *dpy;
    Window win;
    Atom clipboard, targets, utf8, primary, xsel_data, incr;
    XEvent ev;
    const char *text;
    double seconds = 30;
    time_t start, now;
    int have_owner = 0;

    if (argc < 2) { fprintf(stderr, "usage: %s 'text' [seconds]\n", argv[0]); return 2; }
    text = argv[1];
    if (argc > 2) seconds = atof(argv[2]);

    dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "cannot open display\n"); return 1; }

    clipboard = XInternAtom(dpy, "CLIPBOARD", False);
    primary = XInternAtom(dpy, "PRIMARY", False);
    targets = XInternAtom(dpy, "TARGETS", False);
    utf8 = XInternAtom(dpy, "UTF8_STRING", False);
    xsel_data = XInternAtom(dpy, "XSEL_DATA", False);
    incr = XInternAtom(dpy, "INCR", False);

    win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), -10, -10, 1, 1, 0, 0, 0);

    XSetSelectionOwner(dpy, clipboard, win, CurrentTime);
    XSetSelectionOwner(dpy, primary, win, CurrentTime);
    XFlush(dpy);
    if (XGetSelectionOwner(dpy, clipboard) != win) { fprintf(stderr, "could not own CLIPBOARD\n"); return 1; }
    printf("clipboard set: %s\n", text);
    fflush(stdout);

    start = time(NULL);
    while (1) {
        while (XPending(dpy)) {
            XNextEvent(dpy, &ev);
            if (ev.type == SelectionRequest) {
                XSelectionRequestEvent *req = &ev.xselectionrequest;
                XSelectionEvent notify;
                Atom prop = req->property ? req->property : req->target;

                memset(&notify, 0, sizeof(notify));
                notify.type = SelectionNotify;
                notify.display = req->display;
                notify.requestor = req->requestor;
                notify.selection = req->selection;
                notify.target = req->target;
                notify.time = req->time;
                notify.property = None;

                if (req->target == targets) {
                    Atom list[2] = { utf8, XA_STRING };
                    XChangeProperty(dpy, req->requestor, prop, XA_ATOM, 32, PropModeReplace,
                                    (unsigned char *)list, 2);
                    notify.property = prop;
                } else if (req->target == utf8 || req->target == XA_STRING) {
                    XChangeProperty(dpy, req->requestor, prop, req->target, 8, PropModeReplace,
                                    (const unsigned char *)text, (int)strlen(text));
                    notify.property = prop;
                }
                XSendEvent(dpy, req->requestor, False, 0, (XEvent *)&notify);
                XFlush(dpy);
                /* the owner must stay alive after handing the data over */
                if (!have_owner) have_owner = 1;
            } else if (ev.type == SelectionClear) {
                printf("selection lost\n");
                fflush(stdout);
                XCloseDisplay(dpy);
                return 0;
            }
        }
        if (seconds > 0) {
            now = time(NULL);
            if (difftime(now, start) > seconds) break;
        }
        usleep(20000);
    }
    XCloseDisplay(dpy);
    return 0;
}

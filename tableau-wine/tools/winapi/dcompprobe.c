/* dcompprobe.c - call the DirectComposition API sequence a Chromium compositor needs, one call per
 * step, printing every HRESULT.  The same PE runs under Wine and on the Windows guest, so the two
 * transcripts can be diffed call by call.
 *
 * Why: on the guest every Power BI WebView2 view has a child of class "Intermediate D3D Window"
 * (WS_EX_NOREDIRECTIONBITMAP|WS_EX_LAYERED, msedgewebview2.exe) - Chromium's DirectComposition
 * presentation surface.  Under Wine that child does not exist.  This probe separates "Wine's dcomp
 * cannot answer these calls" from "Chromium never asked" (e.g. because of the OS version the app
 * sees: under Wine the prefix reports NT 6.1.7601 / DeprecatedOS).
 *
 * Self-contained on purpose: mingw's dcomp.h does not compile standalone, so the interfaces are
 * declared here by IID with index-based vtable calls (IDCompositionDevice:
 * 3 Commit, 6 CreateTargetForHwnd, 7 CreateVisual, 8 CreateSurface; IDCompositionSurface:
 * 3 BeginDraw, 4 EndDraw - the SDK's own order after IUnknown).
 *
 * Build: x86_64-w64-mingw32-gcc -O1 -o tools/winapi/bin/dcompprobe.exe tools/winapi/dcompprobe.c -lole32 -luuid -lgdi32
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <objbase.h>
#include <stdio.h>

typedef struct { void **lpVtbl; } IFACE;

static const GUID IID_DCD = {0xC37EA93A,0xE7AA,0x450D,{0xB1,0x6F,0x97,0x46,0xCB,0x04,0x07,0xF3}};
static const GUID IID_DCD2 = {0x75F1E0BF,0xE6E3,0x4A37,{0x8D,0x1D,0xA5,0xFB,0x4E,0x3A,0x52,0xC4}};
static const GUID IID_DCD3 = {0x0987CB06,0xF916,0x48BF,{0x8D,0x35,0xCE,0x76,0x41,0x8E,0xB6,0x80}};
static const GUID IID_DXGISurf = {0xCAFA0C6D,0x9D68,0x463A,{0xB1,0xAA,0xDA,0x6D,0xB0,0xE9,0xF0,0xC8}};

typedef HRESULT (WINAPI *fnCreateDevice)(void *, const GUID *, void **);
typedef HRESULT (WINAPI *fnCreateSurfaceHandle)(DWORD, const GUID *, HANDLE *);

static void hr_(const char *what, HRESULT hr)
{
    printf("%-52s hr=0x%08lx %s\n", what, (unsigned long)hr, SUCCEEDED(hr) ? "SUCCEEDED" : "FAILED");
}

#define VT(p, n) (((void **)((IFACE *)(p))->lpVtbl)[(n)])

static HRESULT call_commit(IFACE *dev)
{
    typedef HRESULT (WINAPI *F)(IFACE *);
    return ((F)VT(dev, 3))(dev);
}
static HRESULT call_target(IFACE *dev, HWND w, BOOL topmost, void **out)
{
    typedef HRESULT (WINAPI *F)(IFACE *, HWND, BOOL, void **);
    return ((F)VT(dev, 6))(dev, w, topmost, out);
}
static HRESULT call_visual(IFACE *dev, void **out)
{
    typedef HRESULT (WINAPI *F)(IFACE *, void **);
    return ((F)VT(dev, 7))(dev, out);
}
static HRESULT call_surface(IFACE *dev, UINT w, UINT h, UINT fmt, UINT alpha, void **out)
{
    typedef HRESULT (WINAPI *F)(IFACE *, UINT, UINT, UINT, UINT, void **);
    return ((F)VT(dev, 8))(dev, w, h, fmt, alpha, out);
}
static HRESULT call_begindraw(IFACE *s, const RECT *r, const GUID *iid, void **out, POINT *off)
{
    typedef HRESULT (WINAPI *F)(IFACE *, const RECT *, const GUID *, void **, POINT *);
    return ((F)VT(s, 3))(s, r, iid, out, off);
}
static HRESULT call_enddraw(IFACE *s)
{
    typedef HRESULT (WINAPI *F)(IFACE *);
    return ((F)VT(s, 4))(s);
}

int main(void)
{
    HMODULE dll;
    fnCreateDevice pDev, pDev2, pDev3, pDev4;
    fnCreateSurfaceHandle pHandle;
    IFACE *dev = NULL, *dev2 = NULL, *target = NULL, *visual = NULL, *surface = NULL;
    WNDCLASSA wc;
    HWND wnd;
    HRESULT hr;
    HANDLE shared = NULL;
    OSVERSIONINFOA vi;

    printf("== dcompprobe ==\n");
    ZeroMemory(&vi, sizeof(vi)); vi.dwOSVersionInfoSize = sizeof(vi);
    if (GetVersionExA(&vi))
        printf("GetVersionExA                       %lu.%lu build %lu\n",
               (unsigned long)vi.dwMajorVersion, (unsigned long)vi.dwMinorVersion, (unsigned long)vi.dwBuildNumber);
    else printf("GetVersionExA                       FAILED\n");

    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "dcompprobe";
    RegisterClassA(&wc);
    wnd = CreateWindowExA(WS_EX_NOREDIRECTIONBITMAP, "dcompprobe", "dcompprobe", WS_POPUP, 0, 0, 200, 200,
                          NULL, NULL, wc.hInstance, NULL);
    printf("CreateWindowExA(WS_EX_NOREDIRECTIONBITMAP) hwnd=%p\n", (void *)wnd);

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    hr_("CoInitializeEx", hr);

    dll = LoadLibraryA("dcomp.dll");
    printf("LoadLibraryA(\"dcomp.dll\")           %p\n", (void *)dll);
    if (!dll) { printf("RESULT dcomp.dll not loadable\n"); return 1; }
    pDev  = (fnCreateDevice)GetProcAddress(dll, "DCompositionCreateDevice");
    pDev2 = (fnCreateDevice)GetProcAddress(dll, "DCompositionCreateDevice2");
    pDev3 = (fnCreateDevice)GetProcAddress(dll, "DCompositionCreateDevice3");
    pDev4 = (fnCreateDevice)GetProcAddress(dll, "DCompositionCreateDevice4");
    pHandle = (fnCreateSurfaceHandle)GetProcAddress(dll, "DCompositionCreateSurfaceHandle");
    printf("exports CreateDevice=%p CreateDevice2=%p CreateDevice3=%p CreateDevice4=%p CreateSurfaceHandle=%p\n",
           (void *)pDev, (void *)pDev2, (void *)pDev3, (void *)pDev4, (void *)pHandle);

    if (pDev3) { hr = pDev3(NULL, &IID_DCD3, (void **)&dev2); hr_("DCompositionCreateDevice3", hr); }
    if (!dev2 && pDev2) { hr = pDev2(NULL, &IID_DCD2, (void **)&dev2); hr_("DCompositionCreateDevice2", hr); }
    if (!dev2 && pDev) { hr = pDev(NULL, &IID_DCD, (void **)&dev); hr_("DCompositionCreateDevice", hr); }
    if (pHandle) { hr = pHandle(0, &IID_DXGISurf, &shared); hr_("DCompositionCreateSurfaceHandle", hr); }
    printf("device=%p device2=%p sharedHandle=%p\n", (void *)dev, (void *)dev2, shared);

    if (dev)
    {
        hr = call_target(dev, wnd, TRUE, (void **)&target);   hr_("IDCompositionDevice::CreateTargetForHwnd", hr);
        hr = call_visual(dev, (void **)&visual);              hr_("IDCompositionDevice::CreateVisual", hr);
        hr = call_surface(dev, 64, 64, 87 /*BGRA8*/, 1, (void **)&surface);
        hr_("IDCompositionDevice::CreateSurface(64x64 BGRA)", hr);
        if (surface)
        {
            POINT off = {0, 0};
            void *dxgi = NULL;
            hr = call_begindraw(surface, NULL, &IID_DXGISurf, &dxgi, &off); hr_("IDCompositionSurface::BeginDraw", hr);
            hr = call_enddraw(surface);                                    hr_("IDCompositionSurface::EndDraw", hr);
        }
        hr = call_commit(dev);                                 hr_("IDCompositionDevice::Commit", hr);
        printf("RESULT target=%p visual=%p surface=%p\n", (void *)target, (void *)visual, (void *)surface);
    }
    else if (dev2)
    {
        hr = call_target(dev2, wnd, TRUE, (void **)&target);   hr_("IDCompositionDevice2::CreateTargetForHwnd", hr);
        hr = call_visual(dev2, (void **)&visual);              hr_("IDCompositionDevice2::CreateVisual", hr);
        hr = call_surface(dev2, 64, 64, 87, 1, (void **)&surface);
        hr_("IDCompositionDevice2::CreateSurface(64x64 BGRA)", hr);
        hr = call_commit(dev2);                                hr_("IDCompositionDevice2::Commit", hr);
        printf("RESULT target=%p visual=%p surface=%p\n", (void *)target, (void *)visual, (void *)surface);
    }
    else printf("RESULT no device object\n");
    printf("== done ==\n");
    return 0;
}

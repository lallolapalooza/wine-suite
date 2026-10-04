// Control reproducer for CapCut-on-Wine: does D3D11 present to an HWND, and does the
// DirectComposition path (what Qt's D3D11 RHI uses for a top-level window) work?
//
// Reports: D3D11 device creation, adapter identity (proves which GPU the app would see),
// HWND swapchain present loop, and - for both B8G8R8A8 and R8G8B8A8 composition swap
// chains - SetContent/SetRoot/Commit followed by reading the window pixel back.  The
// pixel check is the point: an API sequence that returns S_OK says nothing about whether
// the composited pixels arrive, which is how this probe previously reported "ALL PATHS OK"
// while CapCut's window stayed white.
//
// PROBE_ONLY=bgra8|rgba8 selects one composition case (default: both).  Run in prefix-test
// with WINEDLLOVERRIDES="d3d10core,d3d11,dxgi,d3d8,d3d9=b" if that prefix has DXVK.
//
// exit 0 = every step worked and the pixels matched; non-zero = the number of failures.
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dcomp.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>

static int failures = 0;

static void step(const char *what, HRESULT hr)
{
    if (SUCCEEDED(hr)) printf("[ ok ] %-42s (%08lx)\n", what, (unsigned long)hr);
    else { printf("[FAIL] %-42s (%08lx)\n", what, (unsigned long)hr); failures++; }
}

/* The API sequence alone says nothing about whether the pixels arrive -- the
 * first version of this probe reported ALL PATHS OK while the window stayed
 * white.  Read what the window actually shows. */
static bool check_window_color(HWND hwnd, const char *tag, int r, int g, int b)
{
    HDC dc = GetDC(hwnd);
    COLORREF c = dc ? GetPixel(dc, 400, 300) : CLR_INVALID;
    if (dc) ReleaseDC(hwnd, dc);
    if (c == CLR_INVALID) { printf("[FAIL] %-42s window pixel unreadable\n", tag); failures++; return false; }
    if (abs((int)GetRValue(c) - r) <= 8 && abs((int)GetGValue(c) - g) <= 8 && abs((int)GetBValue(c) - b) <= 8)
    {
        printf("[ ok ] %-42s window shows RGB(%u,%u,%u)\n", tag, GetRValue(c), GetGValue(c), GetBValue(c));
        return true;
    }
    printf("[FAIL] %-42s window shows RGB(%u,%u,%u), expected RGB(%d,%d,%d)\n",
            tag, GetRValue(c), GetGValue(c), GetBValue(c), r, g, b);
    failures++;
    return false;
}

static const char *fl_name(D3D_FEATURE_LEVEL fl)
{
    switch (fl) {
    case D3D_FEATURE_LEVEL_11_1: return "11_1";
    case D3D_FEATURE_LEVEL_11_0: return "11_0";
    case D3D_FEATURE_LEVEL_10_1: return "10_1";
    case D3D_FEATURE_LEVEL_10_0: return "10_0";
    default: return "other";
    }
}

static bool present_frames(IDXGISwapChain1 *sc, ID3D11Device *dev, ID3D11DeviceContext *ctx,
                           const char *tag, int n)
{
    ID3D11Texture2D *bb = NULL;
    ID3D11RenderTargetView *rtv = NULL;
    HRESULT hr = sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);
    if (FAILED(hr)) { printf("[FAIL] %s GetBuffer (%08lx)\n", tag, (unsigned long)hr); failures++; return false; }
    hr = dev->CreateRenderTargetView(bb, NULL, &rtv);
    if (FAILED(hr)) { printf("[FAIL] %s CreateRenderTargetView (%08lx)\n", tag, (unsigned long)hr); failures++; return false; }

    float color[4] = { 0.10f, 0.55f, 0.85f, 1.0f };
    for (int i = 0; i < n; i++) {
        ctx->OMSetRenderTargets(1, &rtv, NULL);
        color[0] = 0.05f + 0.9f * (i / (float)n);
        ctx->ClearRenderTargetView(rtv, color);
        ctx->Flush();
        hr = sc->Present(1, 0);
        if (FAILED(hr)) { printf("[FAIL] %s Present #%d (%08lx)\n", tag, i, (unsigned long)hr); failures++; rtv->Release(); bb->Release(); return false; }
        MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        Sleep(16);
    }
    printf("[ ok ] %s presented %d frames\n", tag, n);
    rtv->Release(); bb->Release();
    return true;
}

/* One DirectComposition case: create the composition swap chain, SetContent/SetRoot,
 * render a solid colour, then Commit and read the window pixel back - a static scene
 * renders once and may never Present again.  Then repeat in the order Qt's D3D11 RHI
 * uses (Present, then Commit).  Qt composites with R8G8B8A8 (the format the app asks
 * for) and this control only ever used B8G8R8A8, so both are exercised. */
static bool dcomp_case(IDXGIFactory2 *factory, ID3D11Device *dev, ID3D11DeviceContext *ctx,
                       HWND hwnd, IDCompositionDevice *dcomp, DXGI_FORMAT format, const char *tag,
                       int r, int g, int b)
{
    DXGI_SWAP_CHAIN_DESC1 cs;
    IDCompositionTarget *target = NULL;
    IDCompositionVisual *visual = NULL;
    IDXGISwapChain1 *csc = NULL;
    ID3D11Texture2D *bb = NULL;
    ID3D11RenderTargetView *rtv = NULL;
    float color[4] = { r / 255.0f, g / 255.0f, b / 255.0f, 1.0f };
    HRESULT hr;

    memset(&cs, 0, sizeof(cs));
    cs.Width = 800; cs.Height = 600;
    cs.Format = format;
    cs.SampleDesc.Count = 1;
    cs.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    cs.BufferCount = 2;
    cs.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    cs.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;   /* what Qt asks for */

    if (FAILED(hr = factory->CreateSwapChainForComposition(dev, &cs, NULL, &csc)))
    { step("CreateSwapChainForComposition", hr); goto done; }
    printf("[ ok ] %-42s\n", "CreateSwapChainForComposition");
    if (FAILED(hr = dcomp->CreateTargetForHwnd(hwnd, TRUE, &target)))
    { step("CreateTargetForHwnd", hr); goto done; }
    if (FAILED(hr = dcomp->CreateVisual(&visual))) { step("CreateVisual", hr); goto done; }
    if (FAILED(hr = visual->SetContent(csc))) { step("SetContent", hr); goto done; }
    if (FAILED(hr = target->SetRoot(visual))) { step("SetRoot", hr); goto done; }

    if (FAILED(hr = csc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb))
            || FAILED(hr = dev->CreateRenderTargetView(bb, NULL, &rtv)))
    { step("back buffer RTV", hr); goto done; }
    ctx->OMSetRenderTargets(1, &rtv, NULL);
    ctx->ClearRenderTargetView(rtv, color);
    ctx->Flush();
    Sleep(20);

    /* Commit alone must put the rendered buffer on screen: a static scene
     * renders once and may never Present again. */
    if (FAILED(hr = dcomp->Commit())) { step("Commit", hr); goto done; }
    { MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); } }
    check_window_color(hwnd, tag, r, g, b);

    /* And in the order Qt's RHI uses: Present, then Commit. */
    if (FAILED(hr = csc->Present(1, 0))) { step("Present", hr); goto done; }
    if (FAILED(hr = dcomp->Commit())) { step("Commit", hr); goto done; }
    { MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); } }

done:
    if (rtv) rtv->Release();
    if (bb) bb->Release();
    if (csc) csc->Release();
    if (visual) visual->Release();
    if (target) target->Release();
    return failures == 0;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    WNDCLASSA wc;
    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "CapCutWineTest";
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowExA(0, "CapCutWineTest", "CapCutWineTest", WS_OVERLAPPEDWINDOW,
                                60, 60, 800, 600, NULL, NULL, wc.hInstance, NULL);
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    { MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); } }

    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL got = (D3D_FEATURE_LEVEL)0;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                   D3D11_SDK_VERSION, &dev, &got, &ctx);
    step("D3D11CreateDevice(HARDWARE)", hr);
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_WARP, NULL, 0, NULL, 0,
                               D3D11_SDK_VERSION, &dev, &got, &ctx);
        step("D3D11CreateDevice(WARP)", hr);
    }
    if (FAILED(hr)) { printf("RESULT: D3D11 UNAVAILABLE\n"); return 2; }
    printf("       feature level %s\n", fl_name(got));

    IDXGIDevice *dxgi_dev = NULL;
    step("QueryInterface(IDXGIDevice)", dev->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi_dev));
    IDXGIAdapter *adapter = NULL;
    if (dxgi_dev) step("IDXGIDevice::GetAdapter", dxgi_dev->GetAdapter(&adapter));
    if (adapter) {
        DXGI_ADAPTER_DESC d;
        if (SUCCEEDED(adapter->GetDesc(&d)))
            printf("       adapter: \"%ls\" vendor=%04x device=%04x subsystem=%08x vram=%llu MB\n",
                   d.Description, d.VendorId, d.DeviceId, d.SubSysId,
                   (unsigned long long)(d.DedicatedVideoMemory >> 20));
    }
    IDXGIFactory2 *factory = NULL;
    if (adapter) step("IDXGIAdapter::GetParent(IDXGIFactory2)",
                      adapter->GetParent(__uuidof(IDXGIFactory2), (void **)&factory));

    // --- path A: swapchain for hwnd (the non-DComp path) ---
    if (factory) {
        DXGI_SWAP_CHAIN_DESC1 sd;
        memset(&sd, 0, sizeof(sd));
        sd.Width = 800; sd.Height = 600;
        sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        sd.SampleDesc.Count = 1;
        sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.BufferCount = 2;
        sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
        sd.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
        IDXGISwapChain1 *sc = NULL;
        hr = factory->CreateSwapChainForHwnd(dev, hwnd, &sd, NULL, NULL, &sc);
        step("CreateSwapChainForHwnd(FLIP_DISCARD)", hr);
        if (SUCCEEDED(hr)) { present_frames(sc, dev, ctx, "hwnd", 30); sc->Release(); }
    }

    // --- path B: DirectComposition (what Qt6Gui does for a top-level window) ---
    // A dedicated window: Qt gives its top-level window a composition swapchain
    // and never a window-system swapchain, so path A's swapchain must not be
    // left on the window under test.
    HWND hwnd2 = CreateWindowExA(0, "CapCutWineTest", "CapCutWineTest dcomp", WS_OVERLAPPEDWINDOW,
                                 80, 80, 900, 700, NULL, NULL, wc.hInstance, NULL);
    ShowWindow(hwnd2, SW_SHOW);
    UpdateWindow(hwnd2);
    { MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); } }

    IDCompositionDevice *dcomp = NULL;
    hr = DCompositionCreateDevice(NULL, __uuidof(IDCompositionDevice), (void **)&dcomp);
    step("DCompositionCreateDevice(NULL)", hr);
    if (SUCCEEDED(hr) && factory) {
        IDCompositionVisual *visual = NULL;
        if (SUCCEEDED(dcomp->CreateVisual(&visual))) {
            IDCompositionVisual2 *v2 = NULL;   /* newest this mingw dcomp.h declares */
            step("QueryInterface(IDCompositionVisual2)", visual->QueryInterface(__uuidof(IDCompositionVisual2), (void **)&v2));
            if (v2) v2->Release();
            visual->Release();
        }
        const char *only = getenv("PROBE_ONLY");   /* bgra8 | rgba8 | unset = both */
        if (!only || !strcmp(only, "bgra8"))
            dcomp_case(factory, dev, ctx, hwnd2, dcomp, DXGI_FORMAT_B8G8R8A8_UNORM, "dcomp BGRA8 pixel", 230, 51, 13);
        if (!only || !strcmp(only, "rgba8"))
            dcomp_case(factory, dev, ctx, hwnd2, dcomp, DXGI_FORMAT_R8G8B8A8_UNORM, "dcomp RGBA8 pixel", 13, 51, 230);
        dcomp->Release();
    }

    printf("RESULT: %s (%d failures)\n", failures ? "FAIL" : "ALL PATHS OK", failures);
    return failures ? 1 : 0;
}

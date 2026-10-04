// Probe: how a DirectComposition swap chain (what Qt 6's D3D11 RHI creates for a
// top-level window) can be read back so that a compositor can show its frames.
//
// Measured on Wine and on the Windows guest with the same binary.  Reports, for
// each format: CreateSwapChainForComposition, the D3D11 back buffer description
// (MiscFlags), IDXGISurface1::GetDC, IDXGISurface::Map, and the same swap chain
// created for an HWND with DXGI_SWAP_CHAIN_FLAG_GDI_COMPATIBLE.
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <cstdio>

static int failures = 0;

static void r(const char *what, HRESULT hr)
{
    printf("%-58s %s (%08lx)\n", what, SUCCEEDED(hr) ? "ok  " : "FAIL", (unsigned long)hr);
    if (FAILED(hr)) failures++;
}

static void test_format(IDXGIFactory2 *factory, ID3D11Device *dev, DXGI_FORMAT format, const char *name)
{
    IDXGISwapChain1 *sc = NULL;
    ID3D11Texture2D *tex = NULL;
    IDXGISurface1 *surface1 = NULL;
    IDXGISurface *surface = NULL;
    D3D11_TEXTURE2D_DESC td;
    DXGI_MAPPED_RECT mapped;
    HDC dc = NULL;
    HRESULT hr;

    printf("\n=== %s ===\n", name);

    DXGI_SWAP_CHAIN_DESC1 desc;
    memset(&desc, 0, sizeof(desc));
    desc.Width = 64;
    desc.Height = 64;
    desc.Format = format;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.Scaling = DXGI_SCALING_STRETCH;
    desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    desc.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;

    hr = factory->CreateSwapChainForComposition(dev, &desc, NULL, &sc);
    r("CreateSwapChainForComposition(RGBA/premultiplied)", hr);
    if (FAILED(hr)) return;

    hr = sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&tex);
    r("GetBuffer(0, ID3D11Texture2D)", hr);
    if (SUCCEEDED(hr))
    {
        tex->GetDesc(&td);
        printf("      back buffer: format %u %ux%u  BindFlags %#x  MiscFlags %#x%s\n",
                td.Format, td.Width, td.Height, td.BindFlags, td.MiscFlags,
                (td.MiscFlags & D3D11_RESOURCE_MISC_GDI_COMPATIBLE) ? " (GDI_COMPATIBLE)" : "");
    }

    hr = sc->GetBuffer(0, __uuidof(IDXGISurface1), (void **)&surface1);
    r("GetBuffer(0, IDXGISurface1)", hr);
    if (SUCCEEDED(hr))
    {
        hr = surface1->GetDC(FALSE, &dc);
        r("  IDXGISurface1::GetDC", hr);
        if (SUCCEEDED(hr)) surface1->ReleaseDC(NULL);
    }

    hr = sc->GetBuffer(0, __uuidof(IDXGISurface), (void **)&surface);
    r("GetBuffer(0, IDXGISurface)", hr);
    if (SUCCEEDED(hr))
    {
        hr = surface->Map(&mapped, DXGI_MAP_READ);
        r("  IDXGISurface::Map(DXGI_MAP_READ)", hr);
        if (SUCCEEDED(hr))
        {
            printf("      mapped pitch %u, first pixel %08x\n", mapped.Pitch,
                    mapped.pBits ? *(unsigned int *)mapped.pBits : 0);
            surface->Unmap();
        }
    }

    /* Same format, but a normal HWND swap chain with the GDI compatible flag. */
    {
        static HWND hwnd;
        DXGI_SWAP_CHAIN_DESC1 d = desc;
        IDXGISwapChain1 *sc2 = NULL;
        d.AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED;
        d.Flags = DXGI_SWAP_CHAIN_FLAG_GDI_COMPATIBLE;
        if (!hwnd) hwnd = CreateWindowExW(0, L"Static", NULL, WS_POPUP, 0, 0, 64, 64, NULL, NULL, NULL, NULL);
        hr = factory->CreateSwapChainForHwnd(dev, hwnd, &d, NULL, NULL, &sc2);
        r("CreateSwapChainForHwnd(GDI_COMPATIBLE, same format)", hr);
        if (SUCCEEDED(hr)) sc2->Release();
        if (hwnd) DestroyWindow(hwnd), hwnd = NULL;
    }

    if (tex) tex->Release();
    if (surface1) surface1->Release();
    if (surface) surface->Release();
    sc->Release();
}

int main(void)
{
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL fl = (D3D_FEATURE_LEVEL)0;
    IDXGIDevice *dxgi_dev = NULL;
    IDXGIAdapter *adapter = NULL;
    IDXGIFactory2 *factory = NULL;
    HRESULT hr;

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx);
    r("D3D11CreateDevice(HARDWARE)", hr);
    if (FAILED(hr)) return 2;
    if (SUCCEEDED(dev->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi_dev))
            && SUCCEEDED(dxgi_dev->GetAdapter(&adapter)))
    {
        DXGI_ADAPTER_DESC ad;
        if (SUCCEEDED(adapter->GetDesc(&ad)))
            printf("      adapter: %ls vendor %04x device %04x\n", ad.Description, ad.VendorId, ad.DeviceId);
        r("IDXGIAdapter::GetParent(IDXGIFactory2)",
                adapter->GetParent(__uuidof(IDXGIFactory2), (void **)&factory));
    }
    if (!factory) { printf("RESULT: no factory\n"); return 2; }

    test_format(factory, dev, DXGI_FORMAT_R8G8B8A8_UNORM, "R8G8B8A8_UNORM");
    test_format(factory, dev, DXGI_FORMAT_B8G8R8A8_UNORM, "B8G8R8A8_UNORM");

    printf("\nRESULT: %s (%d failures)\n", failures ? "FAIL" : "ALL OK", failures);
    return failures ? 1 : 0;
}

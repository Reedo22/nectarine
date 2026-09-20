/* Nectarine D3D11 render-pass benchmark.
 *
 * Reproduces the exact pathology found in DSP: a bloom-style pyramid of render targets,
 * each drawn with ONE draw call, which is 89% of that game's render passes. Deterministic
 * and finishes in seconds, unlike DSP (needs Steam, 2 min to load, resets its resolution,
 * and swings 19-55 fps between samples).
 *
 * The pixel shader outputs a constant so shading cost is negligible -- what remains is
 * per-pass overhead plus the attachment load/store traffic, which is what we're attacking.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 d3d11probe.c -o d3d11probe.exe -ld3d11 -ldxgi -ld3dcompiler
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>
#include <stdio.h>

#define LEVELS 8
#define ITERS  2000

static const char* kVS =
  "float4 main(uint id : SV_VertexID) : SV_Position {"
  "  float2 uv = float2((id << 1) & 2, id & 2);"
  "  return float4(uv * 2.0 - 1.0, 0.0, 1.0);"
  "}";
static const char* kPS =
  "float4 main() : SV_Target { return float4(0.25, 0.5, 0.75, 1.0); }";

static double now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

int main(int argc, char** argv) {
    int iters = (argc > 1) ? atoi(argv[1]) : ITERS;

    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL got;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                   D3D11_SDK_VERSION, &dev, &got, &ctx);
    if (FAILED(hr)) { printf("D3D11CreateDevice FAILED hr=0x%08lx\n", (unsigned long)hr); return 1; }
    printf("device OK, feature level 0x%x\n", (unsigned)got);

    /* identify the adapter so we can confirm which DXVK/driver is live */
    IDXGIDevice *dxgiDev = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void**)&dxgiDev))) {
        IDXGIAdapter *ad = NULL;
        if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgiDev, &ad))) {
            DXGI_ADAPTER_DESC d; IDXGIAdapter_GetDesc(ad, &d);
            printf("adapter: %ls\n", d.Description);
            IDXGIAdapter_Release(ad);
        }
        IDXGIDevice_Release(dxgiDev);
    }

    ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
    if (FAILED(D3DCompile(kVS, strlen(kVS), NULL, NULL, NULL, "main", "vs_5_0", 0, 0, &vsb, &err)) ||
        FAILED(D3DCompile(kPS, strlen(kPS), NULL, NULL, NULL, "main", "ps_5_0", 0, 0, &psb, &err))) {
        printf("shader compile FAILED%s%s\n", err ? ": " : "", err ? (char*)ID3D10Blob_GetBufferPointer(err) : "");
        return 1;
    }
    ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL;
    ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs);
    ID3D11Device_CreatePixelShader (dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps);

    /* the pyramid: 1920x804 down to 15x6, matching what DSP actually does */
    ID3D11Texture2D        *tex[LEVELS] = {0};
    ID3D11RenderTargetView *rtv[LEVELS] = {0};
    UINT w = 1920, h = 804;
    for (int i = 0; i < LEVELS; i++) {
        D3D11_TEXTURE2D_DESC td = {0};
        td.Width = w; td.Height = h; td.MipLevels = 1; td.ArraySize = 1;
        td.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;      /* DSP uses RGBA16F here */
        td.SampleDesc.Count = 1; td.Usage = D3D11_USAGE_DEFAULT;
        td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
        if (FAILED(ID3D11Device_CreateTexture2D(dev, &td, NULL, &tex[i]))) { printf("tex %d failed\n", i); return 1; }
        ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource*)tex[i], NULL, &rtv[i]);
        if (w > 15) { w /= 2; h /= 2; }
    }

    ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
    ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
    ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    /* warm up so shader/pipeline compilation is not in the timed section */
    for (int i = 0; i < LEVELS; i++) {
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv[i], NULL);
        ID3D11DeviceContext_Draw(ctx, 3, 0);
    }
    ID3D11DeviceContext_Flush(ctx);
    Sleep(500);

    double t0 = now_ms();
    for (int it = 0; it < iters; it++) {
        UINT vw = 1920, vh = 804;
        for (int i = 0; i < LEVELS; i++) {
            D3D11_VIEWPORT vp = { 0.0f, 0.0f, (FLOAT)vw, (FLOAT)vh, 0.0f, 1.0f };
            ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
            ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv[i], NULL);
            ID3D11DeviceContext_Draw(ctx, 3, 0);      /* ONE draw per pass, as DSP does */
            if (vw > 15) { vw /= 2; vh /= 2; }
        }
    }
    /* Flush() only SUBMITS -- it does not wait, so timing it measures CPU submission
       only. Force actual GPU completion with a staging copy + Map(READ), which blocks. */
    {
        D3D11_TEXTURE2D_DESC sd = {0};
        sd.Width = 16; sd.Height = 16; sd.MipLevels = 1; sd.ArraySize = 1;
        sd.Format = DXGI_FORMAT_R16G16B16A16_FLOAT; sd.SampleDesc.Count = 1;
        sd.Usage = D3D11_USAGE_STAGING; sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        ID3D11Texture2D *stg = NULL;
        if (SUCCEEDED(ID3D11Device_CreateTexture2D(dev, &sd, NULL, &stg))) {
            D3D11_BOX box = { 0, 0, 0, 16, 16, 1 };
            ID3D11DeviceContext_CopySubresourceRegion(ctx, (ID3D11Resource*)stg, 0, 0, 0, 0,
                                                      (ID3D11Resource*)tex[LEVELS-1], 0, &box);
            D3D11_MAPPED_SUBRESOURCE ms;
            if (SUCCEEDED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource*)stg, 0, D3D11_MAP_READ, 0, &ms)))
                ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource*)stg, 0);
            ID3D11Texture2D_Release(stg);
        }
    }
    double t1 = now_ms();

    double passes = (double)iters * LEVELS;
    printf("%d iterations x %d passes = %.0f single-draw render passes\n", iters, LEVELS, passes);
    printf("elapsed %.1f ms  ->  %.1f passes/sec, %.4f ms per pass\n",
           t1 - t0, passes / ((t1 - t0) / 1000.0), (t1 - t0) / passes);
    return 0;
}

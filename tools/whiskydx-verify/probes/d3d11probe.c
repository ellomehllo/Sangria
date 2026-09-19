/* D3D11 probe: device + swapchain at a chosen feature level, runtime HLSL
 * compile through d3dcompiler_47, then a fixed GPU-bound pixel shader
 * (Mandelbrot, 256 iterations) drawn full screen until time runs out.
 * Writes <exe>.results.txt with what happened and the average FPS. */
#include "common.h"

#ifndef PROBE_FL
#define PROBE_FL 0xb000
#endif

typedef struct { UINT Numerator, Denominator; } DXGI_RATIONAL;
typedef struct {
    UINT Width, Height; DXGI_RATIONAL RefreshRate; UINT Format, ScanlineOrdering, Scaling;
} DXGI_MODE_DESC;
typedef struct {
    DXGI_MODE_DESC BufferDesc; UINT SampleCount, SampleQuality; UINT BufferUsage, BufferCount;
    HWND OutputWindow; BOOL Windowed; UINT SwapEffect, Flags;
} DXGI_SWAP_CHAIN_DESC;
typedef struct {
    WCHAR Description[128]; UINT VendorId, DeviceId, SubSysId, Revision;
    SIZE_T DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory; DWORD LuidLow; long LuidHigh;
} DXGI_ADAPTER_DESC;
typedef struct { float TopLeftX, TopLeftY, Width, Height, MinDepth, MaxDepth; } D3D11_VIEWPORT;

IMPORT HRESULT D3D11CreateDeviceAndSwapChain(void *adapter, UINT driverType, HMODULE software, UINT flags,
                                             const UINT *levels, UINT numLevels, UINT sdk,
                                             const DXGI_SWAP_CHAIN_DESC *desc, void **swapchain, void **device,
                                             UINT *level, void **context);
IMPORT HRESULT D3DCompile(const void *src, SIZE_T size, const char *name, const void *defines, void *include,
                          const char *entry, const char *target, UINT flags1, UINT flags2, void **code,
                          void **errors);

static const GUID IID_ID3D11Texture2D = {0x6f15aaf2, 0xd208, 0x4e89, {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};
static const GUID IID_IDXGIDevice = {0x54ec77fa, 0x1377, 0x44e6, {0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c}};

static const char shader[] =
    "float4 vs(uint id : SV_VertexID) : SV_Position {\n"
    "  float2 uv = float2((id << 1) & 2, id & 2);\n"
    "  return float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);\n"
    "}\n"
    "float4 ps(float4 pos : SV_Position) : SV_Target {\n"
    "  float2 c = float2(pos.x / 1280.0 * 3.0 - 2.1, pos.y / 720.0 * 2.0 - 1.0);\n"
    "  float2 z = float2(0, 0); float i = 0;\n"
    "  [loop] for (int n = 0; n < ITERS; n++) {\n"
    "    z = float2(z.x * z.x - z.y * z.y, 2 * z.x * z.y) + c;\n"
    "    if (dot(z, z) > 4) break;\n"
    "    i += 1;\n"
    "  }\n"
    "  float t = i / (float)ITERS;\n"
    "  return float4(t, t * t, sqrt(t), 1);\n"
    "}\n";

typedef struct { const char *Name, *Definition; } D3D_SHADER_MACRO;
static char g_iters[16];

static void *compile(const char *entry, const char *target) {
    void *code = 0, *errors = 0;
    D3D_SHADER_MACRO defines[] = {{"ITERS", g_iters}, {0, 0}};
    HRESULT hr = D3DCompile(shader, sizeof(shader) - 1, "probe.hlsl", defines, 0, entry, target, 0, 0, &code,
                            &errors);
    char line[160];
    wsprintfA(line, "compile_%s=%s hr=0x%08x", entry, FAILED(hr) ? "fail" : "ok", (unsigned)hr);
    results_add(line);
    if (errors) {
        /* ID3DBlob::GetBufferPointer = 3 */
        const char *text = COM(errors, 3, const char *(*)(void *))(errors);
        char msg[200];
        int n = 0;
        while (text && text[n] && n < 180 && text[n] != '\n') { msg[n] = text[n]; n++; }
        msg[n] = 0;
        results_add(msg);
    }
    return FAILED(hr) ? 0 : code;
}

void entry(void) {
    results_init();
    results_add("probe=d3d11");
    char line[256];
    wsprintfA(line, "requested_feature_level=0x%x", PROBE_FL);
    results_add(line);

    static const WCHAR title[] = {'D', '3', 'D', '1', '1', ' ', 'P', 'r', 'o', 'b', 'e', 0};
    HWND hwnd = make_window(title, 1280, 720);

    DXGI_SWAP_CHAIN_DESC desc;
    memset(&desc, 0, sizeof(desc));
    desc.BufferDesc.Width = 1280;
    desc.BufferDesc.Height = 720;
    desc.BufferDesc.Format = 28; /* DXGI_FORMAT_R8G8B8A8_UNORM */
    desc.SampleCount = 1;
    desc.BufferUsage = 0x20; /* DXGI_USAGE_RENDER_TARGET_OUTPUT */
    desc.BufferCount = 2;
    desc.OutputWindow = hwnd;
    desc.Windowed = 1;
    desc.SwapEffect = 4; /* DXGI_SWAP_EFFECT_FLIP_DISCARD */

    UINT level = PROBE_FL, got = 0;
    void *swapchain = 0, *device = 0, *context = 0;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(0, 1 /* HARDWARE */, 0, 0, &level, 1, 7, &desc, &swapchain,
                                               &device, &got, &context);
    results_hr("create_device", hr);
    if (FAILED(hr)) {
        results_add("status=device_failed");
        results_flush();
        ExitProcess(2);
    }
    wsprintfA(line, "feature_level=0x%x", got);
    results_add(line);

    /* IUnknown::QueryInterface(IDXGIDevice) -> GetAdapter (7) -> GetDesc (8) */
    void *dxgiDevice = 0, *adapter = 0;
    if (!FAILED(COM(device, 0, HRESULT (*)(void *, const GUID *, void **))(device, &IID_IDXGIDevice, &dxgiDevice)) &&
        !FAILED(COM(dxgiDevice, 7, HRESULT (*)(void *, void **))(dxgiDevice, &adapter))) {
        DXGI_ADAPTER_DESC ad;
        memset(&ad, 0, sizeof(ad));
        COM(adapter, 8, HRESULT (*)(void *, DXGI_ADAPTER_DESC *))(adapter, &ad);
        char name[129];
        int n = 0;
        for (; n < 128 && ad.Description[n]; n++) name[n] = ad.Description[n] < 128 ? (char)ad.Description[n] : '?';
        name[n] = 0;
        wsprintfA(line, "adapter=%s vendor=0x%04x device=0x%04x", name, ad.VendorId, ad.DeviceId);
        results_add(line);
    }
    results_flush();

    /* IDXGISwapChain::GetBuffer (9), ID3D11Device::CreateRenderTargetView (9) */
    void *backbuffer = 0, *rtv = 0;
    COM(swapchain, 9, HRESULT (*)(void *, UINT, const GUID *, void **))(swapchain, 0, &IID_ID3D11Texture2D, &backbuffer);
    hr = COM(device, 9, HRESULT (*)(void *, void *, const void *, void **))(device, backbuffer, 0, &rtv);
    results_hr("create_rtv", hr);

    wsprintfA(g_iters, "%d", arg_int("iters=", 256));
    wsprintfA(line, "shader_iterations=%s", g_iters);
    results_add(line);
    const char *vsTarget = got >= 0xb000 ? "vs_5_0" : "vs_4_0";
    const char *psTarget = got >= 0xb000 ? "ps_5_0" : "ps_4_0";
    void *vsCode = compile("vs", vsTarget), *psCode = compile("ps", psTarget);
    void *vs = 0, *ps = 0;
    if (vsCode && psCode) {
        /* ID3DBlob GetBufferPointer (3) / GetBufferSize (4); CreateVertexShader (12) / CreatePixelShader (15) */
        void *(*ptr)(void *) = (void *(*)(void *))VTBL(vsCode)[3];
        SIZE_T (*size)(void *) = (SIZE_T(*)(void *))VTBL(vsCode)[4];
        hr = COM(device, 12, HRESULT (*)(void *, const void *, SIZE_T, void *, void **))(device, ptr(vsCode),
                                                                                         size(vsCode), 0, &vs);
        results_hr("create_vs", hr);
        hr = COM(device, 15, HRESULT (*)(void *, const void *, SIZE_T, void *, void **))(device, ptr(psCode),
                                                                                         size(psCode), 0, &ps);
        results_hr("create_ps", hr);
    }
    results_add(vs && ps ? "draw=mandelbrot" : "draw=clear_only");
    results_flush();

    D3D11_VIEWPORT vp = {0, 0, 1280, 720, 0, 1};
    const float clear[4] = {0.1f, 0.2f, 0.4f, 1.0f};
    int seconds = arg_int("secs=", 10);
    int syncInterval = arg_int("sync=", 0);
    wsprintfA(line, "sync_interval=%d", syncInterval);
    results_add(line);
    double start = now_seconds(), end = start + seconds, t = start;
    long frames = 0;
    HRESULT presentHr = 0;
    while (!g_quit && (t = now_seconds()) < end) {
        pump();
        /* OMSetRenderTargets (33), RSSetViewports (44), ClearRenderTargetView (50) */
        COM(context, 33, void (*)(void *, UINT, void **, void *))(context, 1, &rtv, 0);
        COM(context, 44, void (*)(void *, UINT, const D3D11_VIEWPORT *))(context, 1, &vp);
        COM(context, 50, void (*)(void *, void *, const float *))(context, rtv, clear);
        if (vs && ps) {
            /* IASetPrimitiveTopology (24) TRIANGLELIST, VSSetShader (11), PSSetShader (9), Draw (13) */
            COM(context, 24, void (*)(void *, UINT))(context, 4);
            COM(context, 11, void (*)(void *, void *, void *, UINT))(context, vs, 0, 0);
            COM(context, 9, void (*)(void *, void *, void *, UINT))(context, ps, 0, 0);
            COM(context, 13, void (*)(void *, UINT, UINT))(context, 3, 0);
        }
        /* IDXGISwapChain::Present (8), vsync per sync= (default off) */
        presentHr = COM(swapchain, 8, HRESULT (*)(void *, UINT, UINT))(swapchain, (UINT)syncInterval, 0);
        if (FAILED(presentHr)) break;
        frames++;
    }
    results_hr("last_present", presentHr);
    report_fps(frames, t - start);
    results_add(FAILED(presentHr) ? "status=present_failed" : "status=ok");
    results_flush();
    ExitProcess(0);
}

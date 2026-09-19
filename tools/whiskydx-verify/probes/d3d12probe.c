/* D3D12 probe: device, direct queue and a flip-model swapchain through dxgi,
 * then the D3D11 probe's GPU-bound pixel shader (Mandelbrot, compiled at
 * runtime through d3dcompiler_47) drawn full screen and presented until time
 * runs out. The first frame is also copied back to the CPU and two pixels are
 * checked, so status=ok means the shader ran and landed in the swapchain, not
 * just that Present returned S_OK. Its import table (d3d12.dll) is what the
 * app's API check reads. Writes <exe>.results.txt. */
#include "common.h"

typedef unsigned short UINT16;
typedef unsigned long long UINT64;

#define WIDTH 1280
#define HEIGHT 720
#define FRAMES_IN_FLIGHT 2

typedef struct { UINT Numerator, Denominator; } DXGI_RATIONAL;
typedef struct {
    UINT Width, Height; DXGI_RATIONAL RefreshRate; UINT Format, ScanlineOrdering, Scaling;
} DXGI_MODE_DESC;
typedef struct { UINT Count, Quality; } DXGI_SAMPLE_DESC;
typedef struct {
    DXGI_MODE_DESC BufferDesc; DXGI_SAMPLE_DESC SampleDesc; UINT BufferUsage, BufferCount;
    HWND OutputWindow; BOOL Windowed; UINT SwapEffect, Flags;
} DXGI_SWAP_CHAIN_DESC;
typedef struct {
    WCHAR Description[128]; UINT VendorId, DeviceId, SubSysId, Revision;
    SIZE_T DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory; DWORD LuidLow; long LuidHigh;
} DXGI_ADAPTER_DESC;

typedef struct { UINT Type; INT Priority; UINT Flags, NodeMask; } D3D12_COMMAND_QUEUE_DESC;
typedef struct { UINT Type, NumDescriptors, Flags, NodeMask; } D3D12_DESCRIPTOR_HEAP_DESC;
typedef struct { SIZE_T ptr; } D3D12_CPU_DESCRIPTOR_HANDLE;
typedef struct { UINT NumFeatureLevels; const UINT *pFeatureLevelsRequested; UINT MaxSupportedFeatureLevel; }
    D3D12_FEATURE_DATA_FEATURE_LEVELS;
/* The union's largest member is the transition, so this is the full size. */
typedef struct {
    UINT Type, Flags; void *pResource; UINT Subresource, StateBefore, StateAfter;
} D3D12_RESOURCE_BARRIER;
typedef struct { float TopLeftX, TopLeftY, Width, Height, MinDepth, MaxDepth; } D3D12_VIEWPORT;
typedef struct { long left, top, right, bottom; } D3D12_RECT;
typedef struct {
    UINT NumParameters; const void *pParameters; UINT NumStaticSamplers; const void *pStaticSamplers; UINT Flags;
} D3D12_ROOT_SIGNATURE_DESC;

typedef struct { const void *pShaderBytecode; SIZE_T BytecodeLength; } D3D12_SHADER_BYTECODE;
typedef struct {
    const void *pSODeclaration; UINT NumEntries; const UINT *pBufferStrides; UINT NumStrides, RasterizedStream;
} D3D12_STREAM_OUTPUT_DESC;
typedef struct {
    BOOL BlendEnable, LogicOpEnable;
    UINT SrcBlend, DestBlend, BlendOp, SrcBlendAlpha, DestBlendAlpha, BlendOpAlpha, LogicOp;
    BYTE RenderTargetWriteMask;
} D3D12_RENDER_TARGET_BLEND_DESC;
typedef struct {
    BOOL AlphaToCoverageEnable, IndependentBlendEnable; D3D12_RENDER_TARGET_BLEND_DESC RenderTarget[8];
} D3D12_BLEND_DESC;
typedef struct {
    UINT FillMode, CullMode; BOOL FrontCounterClockwise; INT DepthBias; float DepthBiasClamp, SlopeScaledDepthBias;
    BOOL DepthClipEnable, MultisampleEnable, AntialiasedLineEnable; UINT ForcedSampleCount, ConservativeRaster;
} D3D12_RASTERIZER_DESC;
typedef struct { UINT StencilFailOp, StencilDepthFailOp, StencilPassOp, StencilFunc; } D3D12_DEPTH_STENCILOP_DESC;
typedef struct {
    BOOL DepthEnable; UINT DepthWriteMask, DepthFunc; BOOL StencilEnable; BYTE StencilReadMask, StencilWriteMask;
    D3D12_DEPTH_STENCILOP_DESC FrontFace, BackFace;
} D3D12_DEPTH_STENCIL_DESC;
typedef struct { const void *pInputElementDescs; UINT NumElements; } D3D12_INPUT_LAYOUT_DESC;
typedef struct { const void *pCachedBlob; SIZE_T CachedBlobSizeInBytes; } D3D12_CACHED_PIPELINE_STATE;
typedef struct {
    void *pRootSignature;
    D3D12_SHADER_BYTECODE VS, PS, DS, HS, GS;
    D3D12_STREAM_OUTPUT_DESC StreamOutput;
    D3D12_BLEND_DESC BlendState;
    UINT SampleMask;
    D3D12_RASTERIZER_DESC RasterizerState;
    D3D12_DEPTH_STENCIL_DESC DepthStencilState;
    D3D12_INPUT_LAYOUT_DESC InputLayout;
    UINT IBStripCutValue, PrimitiveTopologyType, NumRenderTargets, RTVFormats[8], DSVFormat;
    DXGI_SAMPLE_DESC SampleDesc;
    UINT NodeMask;
    D3D12_CACHED_PIPELINE_STATE CachedPSO;
    UINT Flags;
} D3D12_GRAPHICS_PIPELINE_STATE_DESC;

typedef struct { UINT Type, CPUPageProperty, MemoryPoolPreference, CreationNodeMask, VisibleNodeMask; }
    D3D12_HEAP_PROPERTIES;
typedef struct {
    UINT Dimension; UINT64 Alignment, Width; UINT Height; UINT16 DepthOrArraySize, MipLevels; UINT Format;
    DXGI_SAMPLE_DESC SampleDesc; UINT Layout, Flags;
} D3D12_RESOURCE_DESC;
typedef struct { UINT Format, Width, Height, Depth, RowPitch; } D3D12_SUBRESOURCE_FOOTPRINT;
typedef struct { UINT64 Offset; D3D12_SUBRESOURCE_FOOTPRINT Footprint; } D3D12_PLACED_SUBRESOURCE_FOOTPRINT;
/* Union of the footprint and a subresource index; index 0 is Offset 0. */
typedef struct { void *pResource; UINT Type; D3D12_PLACED_SUBRESOURCE_FOOTPRINT PlacedFootprint; }
    D3D12_TEXTURE_COPY_LOCATION;

typedef struct {
    DWORD dwOSVersionInfoSize, dwMajorVersion, dwMinorVersion, dwBuildNumber, dwPlatformId; WCHAR szCSDVersion[128];
} RTL_OSVERSIONINFOW;

/* The x64 layouts every Windows game compiles against. */
_Static_assert(sizeof(D3D12_GRAPHICS_PIPELINE_STATE_DESC) == 656, "PSO desc layout");
_Static_assert(sizeof(D3D12_RESOURCE_BARRIER) == 32, "barrier layout");
_Static_assert(sizeof(D3D12_RESOURCE_DESC) == 56, "resource desc layout");
_Static_assert(sizeof(D3D12_TEXTURE_COPY_LOCATION) == 48, "copy location layout");
_Static_assert(sizeof(D3D12_ROOT_SIGNATURE_DESC) == 40, "root signature desc layout");

IMPORT HRESULT D3D12CreateDevice(void *adapter, UINT minimumLevel, const GUID *riid, void **device);
IMPORT HRESULT D3D12SerializeRootSignature(const D3D12_ROOT_SIGNATURE_DESC *desc, UINT version, void **blob,
                                           void **errors);
IMPORT HRESULT CreateDXGIFactory1(const GUID *riid, void **factory);
IMPORT HRESULT D3DCompile(const void *src, SIZE_T size, const char *name, const void *defines, void *include,
                          const char *entry, const char *target, UINT flags1, UINT flags2, void **code,
                          void **errors);
IMPORT HANDLE CreateEventW(void *attributes, BOOL manualReset, BOOL initialState, const WCHAR *name);
IMPORT DWORD WaitForSingleObject(HANDLE handle, DWORD milliseconds);
IMPORT long RtlGetVersion(RTL_OSVERSIONINFOW *info);

static const GUID IID_ID3D12Device = {0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}};
static const GUID IID_ID3D12CommandQueue = {0x0ec870a6, 0x5d7e, 0x4c22,
                                            {0x8c, 0xfc, 0x5b, 0xaa, 0xe0, 0x76, 0x16, 0xed}};
static const GUID IID_ID3D12CommandAllocator = {0x6102dee4, 0xaf59, 0x4b09,
                                                {0xb9, 0x99, 0xb4, 0x4d, 0x73, 0xf0, 0x9b, 0x24}};
static const GUID IID_ID3D12GraphicsCommandList = {0x5b160d0f, 0xac1b, 0x4185,
                                                   {0x8b, 0xa8, 0xb3, 0xae, 0x42, 0xa5, 0xa4, 0x55}};
static const GUID IID_ID3D12DescriptorHeap = {0x8efb471d, 0x616c, 0x4f49,
                                              {0x90, 0xf7, 0x12, 0x7b, 0xb7, 0x63, 0xfa, 0x51}};
static const GUID IID_ID3D12Fence = {0x0a753dcf, 0xc4d8, 0x4b91, {0xad, 0xf6, 0xbe, 0x5a, 0x60, 0xd9, 0x5a, 0x76}};
static const GUID IID_ID3D12Resource = {0x696442be, 0xa72e, 0x4059, {0xbc, 0x79, 0x5b, 0x5c, 0x98, 0x04, 0x0f, 0xad}};
static const GUID IID_ID3D12RootSignature = {0xc54a6b66, 0x72df, 0x4ee8,
                                             {0x8b, 0xe5, 0xa9, 0x46, 0xa1, 0x42, 0x92, 0x14}};
static const GUID IID_ID3D12PipelineState = {0x765a30f3, 0xf624, 0x4c6f,
                                             {0xa8, 0x28, 0xac, 0xe9, 0x48, 0x62, 0x24, 0x45}};
static const GUID IID_IDXGIFactory1 = {0x770aae78, 0xf26f, 0x4dba, {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}};
static const GUID IID_IDXGISwapChain3 = {0x94d99bdb, 0xf1f8, 0x4ab0,
                                         {0xb2, 0x36, 0x7d, 0xa0, 0x17, 0x0e, 0xda, 0xb1}};

/* Same shader as the D3D11 probe, so the two backends' FPS compare. */
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

/* Everything large lives here, not on a stack with no probes. */
static D3D12_GRAPHICS_PIPELINE_STATE_DESC g_pso;
static void *g_device, *g_queue, *g_list, *g_fence, *g_allocators[FRAMES_IN_FLIGHT];
static HANDLE g_event;
static UINT64 g_fence_value;

/* results_hr, flushed at once, so a crash inside the next call still leaves
 * the last step that worked on disk */
static void step_hr(const char *what, HRESULT hr) {
    results_hr(what, hr);
    results_flush();
}

static void finish(const char *status, UINT code) {
    results_add(status);
    results_flush();
    ExitProcess(code);
}

static void *compile(const char *entry, const char *target) {
    void *code = 0, *errors = 0;
    D3D_SHADER_MACRO defines[] = {{"ITERS", g_iters}, {0, 0}};
    HRESULT hr = D3DCompile(shader, sizeof(shader) - 1, "probe.hlsl", defines, 0, entry, target, 0, 0, &code,
                            &errors);
    char line[160];
    wsprintfA(line, "compile_%s=%s hr=0x%08x", entry, FAILED(hr) ? "fail" : "ok", (unsigned)hr);
    results_add(line);
    return FAILED(hr) ? 0 : code;
}

/* ID3DBlob::GetBufferPointer (3) / GetBufferSize (4) */
static D3D12_SHADER_BYTECODE bytecode(void *blob) {
    D3D12_SHADER_BYTECODE code = {COM(blob, 3, void *(*)(void *))(blob), COM(blob, 4, SIZE_T(*)(void *))(blob)};
    return code;
}

/* ID3D12CommandQueue::Signal (14); returns the value it signals. */
static UINT64 signal_queue(void) {
    g_fence_value++;
    COM(g_queue, 14, HRESULT (*)(void *, void *, UINT64))(g_queue, g_fence, g_fence_value);
    return g_fence_value;
}

/* ID3D12Fence GetCompletedValue (8) / SetEventOnCompletion (9). Returns 0
 * when the GPU has not got there within 5 s. */
static int wait_for(UINT64 value) {
    if (COM(g_fence, 8, UINT64 (*)(void *))(g_fence) >= value) return 1;
    COM(g_fence, 9, HRESULT (*)(void *, UINT64, HANDLE))(g_fence, value, g_event);
    return WaitForSingleObject(g_event, 5000) == 0;
}

static void transition(void *resource, UINT before, UINT after) {
    D3D12_RESOURCE_BARRIER barrier = {0, 0, resource, 0xffffffff, before, after};
    /* ResourceBarrier (26) */
    COM(g_list, 26, void (*)(void *, UINT, const D3D12_RESOURCE_BARRIER *))(g_list, 1, &barrier);
}

/* What the Windows version setting reports, so a per-program override can be
 * seen landing. */
static void report_os_version(void) {
    RTL_OSVERSIONINFOW info;
    memset(&info, 0, sizeof(info));
    info.dwOSVersionInfoSize = sizeof(info);
    RtlGetVersion(&info);
    char line[96];
    wsprintfA(line, "os_version=%u.%u.%u", info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber);
    results_add(line);
}

static void report_adapter(void *factory) {
    /* IDXGIFactory::EnumAdapters (7), IDXGIAdapter::GetDesc (8) */
    void *adapter = 0;
    if (FAILED(COM(factory, 7, HRESULT (*)(void *, UINT, void **))(factory, 0, &adapter))) return;
    DXGI_ADAPTER_DESC desc;
    memset(&desc, 0, sizeof(desc));
    COM(adapter, 8, HRESULT (*)(void *, DXGI_ADAPTER_DESC *))(adapter, &desc);
    char name[129], line[256];
    int n = 0;
    for (; n < 128 && desc.Description[n]; n++) name[n] = desc.Description[n] < 128 ? (char)desc.Description[n] : '?';
    name[n] = 0;
    wsprintfA(line, "adapter=%s vendor=0x%04x device=0x%04x", name, desc.VendorId, desc.DeviceId);
    results_add(line);
}

static void report_feature_level(void) {
    static const UINT levels[] = {0xc200, 0xc100, 0xc000, 0xb100, 0xb000};
    D3D12_FEATURE_DATA_FEATURE_LEVELS data = {5, levels, 0};
    /* CheckFeatureSupport (13), D3D12_FEATURE_FEATURE_LEVELS = 2 */
    HRESULT hr = COM(g_device, 13, HRESULT (*)(void *, UINT, void *, UINT))(g_device, 2, &data, sizeof(data));
    char line[64];
    wsprintfA(line, "feature_level=0x%x", FAILED(hr) ? 0 : data.MaxSupportedFeatureLevel);
    results_add(line);
}

/* Root signature with nothing in it: the shaders read only SV_VertexID and
 * SV_Position. Returns the PSO, or 0 when any step failed. */
static void *make_pipeline(void **rootSignature) {
    wsprintfA(g_iters, "%d", arg_int("iters=", 256));
    char line[64];
    wsprintfA(line, "shader_iterations=%s", g_iters);
    results_add(line);
    void *vsCode = compile("vs", "vs_5_0"), *psCode = compile("ps", "ps_5_0");
    if (!vsCode || !psCode) return 0;

    D3D12_ROOT_SIGNATURE_DESC rsDesc;
    memset(&rsDesc, 0, sizeof(rsDesc));
    void *blob = 0, *errors = 0;
    HRESULT hr = D3D12SerializeRootSignature(&rsDesc, 1 /* 1_0 */, &blob, &errors);
    step_hr("serialize_root_signature", hr);
    if (FAILED(hr)) return 0;
    D3D12_SHADER_BYTECODE rs = bytecode(blob);
    /* CreateRootSignature (16) */
    hr = COM(g_device, 16, HRESULT (*)(void *, UINT, const void *, SIZE_T, const GUID *, void **))(
        g_device, 0, rs.pShaderBytecode, rs.BytecodeLength, &IID_ID3D12RootSignature, rootSignature);
    step_hr("create_root_signature", hr);
    if (FAILED(hr)) return 0;

    memset(&g_pso, 0, sizeof(g_pso));
    g_pso.pRootSignature = *rootSignature;
    g_pso.VS = bytecode(vsCode);
    g_pso.PS = bytecode(psCode);
    D3D12_RENDER_TARGET_BLEND_DESC *blend = &g_pso.BlendState.RenderTarget[0];
    blend->SrcBlend = blend->SrcBlendAlpha = 2;   /* ONE */
    blend->DestBlend = blend->DestBlendAlpha = 1; /* ZERO */
    blend->BlendOp = blend->BlendOpAlpha = 1;     /* ADD */
    blend->LogicOp = 4;                           /* NOOP */
    blend->RenderTargetWriteMask = 0xf;
    g_pso.SampleMask = 0xffffffff;
    g_pso.RasterizerState.FillMode = 3; /* SOLID */
    g_pso.RasterizerState.CullMode = 1; /* NONE */
    g_pso.RasterizerState.DepthClipEnable = 1;
    g_pso.DepthStencilState.DepthWriteMask = 1; /* ALL */
    g_pso.DepthStencilState.DepthFunc = 2;      /* LESS */
    g_pso.DepthStencilState.StencilReadMask = g_pso.DepthStencilState.StencilWriteMask = 0xff;
    D3D12_DEPTH_STENCILOP_DESC keep = {1, 1, 1, 8}; /* KEEP x3, ALWAYS */
    g_pso.DepthStencilState.FrontFace = g_pso.DepthStencilState.BackFace = keep;
    g_pso.PrimitiveTopologyType = 3; /* TRIANGLE */
    g_pso.NumRenderTargets = 1;
    g_pso.RTVFormats[0] = 28; /* R8G8B8A8_UNORM */
    g_pso.SampleDesc.Count = 1;
    void *pipeline = 0;
    /* CreateGraphicsPipelineState (10) */
    hr = COM(g_device, 10, HRESULT (*)(void *, const D3D12_GRAPHICS_PIPELINE_STATE_DESC *, const GUID *, void **))(
        g_device, &g_pso, &IID_ID3D12PipelineState, &pipeline);
    step_hr("create_pso", hr);
    return FAILED(hr) ? 0 : pipeline;
}

/* The first frame's pixels: inside the Mandelbrot set (centre) is white,
 * far outside (corner) is black, and a clear-only frame is the clear colour. */
static int check_pixels(void *readback, int drew) {
    const BYTE *data = 0;
    /* ID3D12Resource::Map (8) / Unmap (9) */
    HRESULT hr = COM(readback, 8, HRESULT (*)(void *, UINT, const void *, const BYTE **))(readback, 0, 0, &data);
    step_hr("map_readback", hr);
    if (FAILED(hr) || !data) return 0;
    const BYTE *centre = data + (HEIGHT / 2) * WIDTH * 4 + (WIDTH / 2) * 4;
    const BYTE *corner = data;
    char line[96];
    wsprintfA(line, "pixel_centre=%u,%u,%u,%u", centre[0], centre[1], centre[2], centre[3]);
    results_add(line);
    wsprintfA(line, "pixel_corner=%u,%u,%u,%u", corner[0], corner[1], corner[2], corner[3]);
    results_add(line);
    /* 0.1 * 255 is 25.5, which implementations round either way */
    int ok = drew ? centre[0] > 240 && centre[1] > 240 && corner[0] < 16 && corner[1] < 16
                  : centre[0] >= 25 && centre[0] <= 26 && centre[1] == 51 && centre[2] == 102;
    COM(readback, 9, void (*)(void *, UINT, const void *))(readback, 0, 0);
    return ok;
}

/* Copies the back buffer into the readback buffer, ending in PRESENT. */
static void record_readback(void *backbuffer, void *readback) {
    D3D12_TEXTURE_COPY_LOCATION dst, src;
    memset(&dst, 0, sizeof(dst));
    memset(&src, 0, sizeof(src));
    dst.pResource = readback;
    dst.Type = 1; /* PLACED_FOOTPRINT */
    dst.PlacedFootprint.Footprint.Format = 28;
    dst.PlacedFootprint.Footprint.Width = WIDTH;
    dst.PlacedFootprint.Footprint.Height = HEIGHT;
    dst.PlacedFootprint.Footprint.Depth = 1;
    dst.PlacedFootprint.Footprint.RowPitch = WIDTH * 4; /* already 256-aligned */
    src.pResource = backbuffer;
    src.Type = 0; /* SUBRESOURCE_INDEX 0 */
    transition(backbuffer, 0x4 /* RENDER_TARGET */, 0x800 /* COPY_SOURCE */);
    /* CopyTextureRegion (16) */
    COM(g_list, 16, void (*)(void *, const D3D12_TEXTURE_COPY_LOCATION *, UINT, UINT, UINT,
                             const D3D12_TEXTURE_COPY_LOCATION *, const void *))(g_list, &dst, 0, 0, 0, &src, 0);
    transition(backbuffer, 0x800, 0 /* PRESENT */);
}

static void *make_readback(void) {
    /* CreateCommittedResource (27): a READBACK heap buffer, which must start in COPY_DEST */
    D3D12_HEAP_PROPERTIES heapProps = {3, 0, 0, 0, 0};
    D3D12_RESOURCE_DESC desc;
    memset(&desc, 0, sizeof(desc));
    desc.Dimension = 1; /* BUFFER */
    desc.Width = (UINT64)WIDTH * 4 * HEIGHT;
    desc.Height = 1;
    desc.DepthOrArraySize = 1;
    desc.MipLevels = 1;
    desc.SampleDesc.Count = 1;
    desc.Layout = 1; /* ROW_MAJOR */
    void *readback = 0;
    HRESULT hr = COM(g_device, 27,
                     HRESULT (*)(void *, const D3D12_HEAP_PROPERTIES *, UINT, const D3D12_RESOURCE_DESC *, UINT,
                                 const void *, const GUID *, void **))(g_device, &heapProps, 0, &desc, 0x400, 0,
                                                                       &IID_ID3D12Resource, &readback);
    step_hr("create_readback", hr);
    return FAILED(hr) ? 0 : readback;
}

static void make_command_objects(void) {
    /* CreateCommandAllocator (9), CreateCommandList (12), which starts open, CreateFence (36) */
    HRESULT hr = 0;
    for (int i = 0; i < FRAMES_IN_FLIGHT && !FAILED(hr); i++)
        hr = COM(g_device, 9, HRESULT (*)(void *, UINT, const GUID *, void **))(
            g_device, 0, &IID_ID3D12CommandAllocator, &g_allocators[i]);
    if (!FAILED(hr))
        hr = COM(g_device, 12, HRESULT (*)(void *, UINT, UINT, void *, void *, const GUID *, void **))(
            g_device, 0, 0, g_allocators[0], 0, &IID_ID3D12GraphicsCommandList, &g_list);
    if (!FAILED(hr))
        hr = COM(g_device, 36, HRESULT (*)(void *, UINT64, UINT, const GUID *, void **))(
            g_device, 0, 0, &IID_ID3D12Fence, &g_fence);
    step_hr("create_command_objects", hr);
    if (FAILED(hr)) finish("status=command_objects_failed", 2);
    COM(g_list, 9, HRESULT (*)(void *))(g_list); /* Close */
    g_event = CreateEventW(0, 0, 0, 0);
}

void entry(void) {
    results_init();
    results_add("probe=d3d12");
    report_os_version();
    char line[160];

    /* min_fl= (decimal) is the minimum feature level asked for; 49152 is 12_0 */
    UINT minLevel = (UINT)arg_int("min_fl=", 0xb000);
    wsprintfA(line, "requested_feature_level=0x%x", minLevel);
    results_add(line);
    results_flush();

    /* Factory first, as games do to pick an adapter. device_first=1 creates
     * the device before dxgi has been touched, which a lazily forwarding dxgi
     * (the runtime's driver-version shim over Apple's) never sees coming. */
    int deviceFirst = arg_int("device_first=", 0);
    wsprintfA(line, "order=%s", deviceFirst ? "device_first" : "factory_first");
    results_add(line);
    void *factory = 0;
    HRESULT hr = 0;
    if (!deviceFirst) {
        hr = CreateDXGIFactory1(&IID_IDXGIFactory1, &factory);
        step_hr("create_factory", hr);
        if (FAILED(hr)) finish("status=factory_failed", 2);
        report_adapter(factory);
        results_flush();
    }
    hr = D3D12CreateDevice(0, minLevel, &IID_ID3D12Device, &g_device);
    step_hr("create_device", hr);
    if (FAILED(hr)) finish("status=device_failed", 2);
    report_feature_level();
    if (deviceFirst) {
        hr = CreateDXGIFactory1(&IID_IDXGIFactory1, &factory);
        step_hr("create_factory", hr);
        if (FAILED(hr)) finish("status=factory_failed", 2);
        report_adapter(factory);
    }
    results_flush();

    /* CreateCommandQueue (8), DIRECT */
    D3D12_COMMAND_QUEUE_DESC queueDesc = {0, 0, 0, 0};
    hr = COM(g_device, 8, HRESULT (*)(void *, const D3D12_COMMAND_QUEUE_DESC *, const GUID *, void **))(
        g_device, &queueDesc, &IID_ID3D12CommandQueue, &g_queue);
    step_hr("create_queue", hr);
    if (FAILED(hr)) finish("status=queue_failed", 2);

    static const WCHAR title[] = {'D', '3', 'D', '1', '2', ' ', 'P', 'r', 'o', 'b', 'e', 0};
    HWND hwnd = make_window(title, WIDTH, HEIGHT);
    DXGI_SWAP_CHAIN_DESC scDesc;
    memset(&scDesc, 0, sizeof(scDesc));
    scDesc.BufferDesc.Width = WIDTH;
    scDesc.BufferDesc.Height = HEIGHT;
    scDesc.BufferDesc.Format = 28; /* R8G8B8A8_UNORM */
    scDesc.SampleDesc.Count = 1;
    scDesc.BufferUsage = 0x20; /* RENDER_TARGET_OUTPUT */
    scDesc.BufferCount = FRAMES_IN_FLIGHT;
    scDesc.OutputWindow = hwnd;
    scDesc.Windowed = 1;
    scDesc.SwapEffect = 4; /* FLIP_DISCARD, the only kind Direct3D 12 takes */
    void *swapchain = 0, *swapchain3 = 0;
    /* IDXGIFactory::CreateSwapChain (10): a Direct3D 12 swapchain takes the queue */
    hr = COM(factory, 10, HRESULT (*)(void *, void *, DXGI_SWAP_CHAIN_DESC *, void **))(factory, g_queue, &scDesc,
                                                                                         &swapchain);
    step_hr("create_swapchain", hr);
    if (FAILED(hr)) finish("status=swapchain_failed", 2);
    COM(swapchain, 0, HRESULT (*)(void *, const GUID *, void **))(swapchain, &IID_IDXGISwapChain3, &swapchain3);

    /* CreateDescriptorHeap (14), RTV = 2; GetDescriptorHandleIncrementSize (15);
     * GetCPUDescriptorHandleForHeapStart (9) returns its struct through a
     * hidden pointer, as MSVC does for every member function. */
    D3D12_DESCRIPTOR_HEAP_DESC heapDesc = {2, FRAMES_IN_FLIGHT, 0, 0};
    void *heap = 0;
    hr = COM(g_device, 14, HRESULT (*)(void *, const D3D12_DESCRIPTOR_HEAP_DESC *, const GUID *, void **))(
        g_device, &heapDesc, &IID_ID3D12DescriptorHeap, &heap);
    step_hr("create_rtv_heap", hr);
    if (FAILED(hr)) finish("status=heap_failed", 2);
    UINT increment = COM(g_device, 15, UINT (*)(void *, UINT))(g_device, 2);
    D3D12_CPU_DESCRIPTOR_HANDLE base;
    COM(heap, 9, D3D12_CPU_DESCRIPTOR_HANDLE *(*)(void *, D3D12_CPU_DESCRIPTOR_HANDLE *))(heap, &base);
    void *buffers[FRAMES_IN_FLIGHT];
    D3D12_CPU_DESCRIPTOR_HANDLE rtv[FRAMES_IN_FLIGHT];
    for (UINT i = 0; i < FRAMES_IN_FLIGHT; i++) {
        /* IDXGISwapChain::GetBuffer (9), CreateRenderTargetView (20) */
        hr = COM(swapchain, 9, HRESULT (*)(void *, UINT, const GUID *, void **))(swapchain, i, &IID_ID3D12Resource,
                                                                                 &buffers[i]);
        if (FAILED(hr)) {
            step_hr("get_buffer", hr);
            finish("status=swapchain_failed", 2);
        }
        rtv[i].ptr = base.ptr + i * increment;
        COM(g_device, 20, void (*)(void *, void *, const void *, D3D12_CPU_DESCRIPTOR_HANDLE))(g_device, buffers[i],
                                                                                            0, rtv[i]);
    }

    make_command_objects();
    void *rootSignature = 0;
    void *pipeline = make_pipeline(&rootSignature);
    results_add(pipeline ? "draw=mandelbrot" : "draw=clear_only");
    void *readback = make_readback();
    results_flush();

    D3D12_VIEWPORT viewport = {0, 0, WIDTH, HEIGHT, 0, 1};
    D3D12_RECT scissor = {0, 0, WIDTH, HEIGHT};
    const float clear[4] = {0.1f, 0.2f, 0.4f, 1.0f};
    int seconds = arg_int("secs=", 10);
    int syncInterval = arg_int("sync=", 0);
    wsprintfA(line, "sync_interval=%d", syncInterval);
    results_add(line);

    UINT64 slotFence[FRAMES_IN_FLIGHT] = {0, 0};
    int pixelsExpected = 0, gpuHung = 0;
    double start = now_seconds(), end = start + seconds, t = start;
    long frames = 0;
    HRESULT presentHr = 0;
    while (!g_quit && (t = now_seconds()) < end) {
        pump();
        int slot = (int)(frames % FRAMES_IN_FLIGHT);
        if (!wait_for(slotFence[slot])) {
            gpuHung = 1;
            break;
        }
        /* IDXGISwapChain3::GetCurrentBackBufferIndex (36) */
        UINT index = swapchain3 ? COM(swapchain3, 36, UINT (*)(void *))(swapchain3) : (UINT)slot;
        void *backbuffer = buffers[index];
        /* Allocator Reset (8), list Reset (10) */
        COM(g_allocators[slot], 8, HRESULT (*)(void *))(g_allocators[slot]);
        COM(g_list, 10, HRESULT (*)(void *, void *, void *))(g_list, g_allocators[slot], pipeline);

        transition(backbuffer, 0 /* PRESENT */, 0x4 /* RENDER_TARGET */);
        /* OMSetRenderTargets (46), RSSetViewports (21), RSSetScissorRects (22), ClearRenderTargetView (48) */
        COM(g_list, 46, void (*)(void *, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE *, BOOL, const void *))(
            g_list, 1, &rtv[index], 0, 0);
        COM(g_list, 21, void (*)(void *, UINT, const D3D12_VIEWPORT *))(g_list, 1, &viewport);
        COM(g_list, 22, void (*)(void *, UINT, const D3D12_RECT *))(g_list, 1, &scissor);
        COM(g_list, 48, void (*)(void *, D3D12_CPU_DESCRIPTOR_HANDLE, const float *, UINT, const void *))(
            g_list, rtv[index], clear, 0, 0);
        if (pipeline) {
            /* SetGraphicsRootSignature (30), IASetPrimitiveTopology (20) TRIANGLELIST, DrawInstanced (12) */
            COM(g_list, 30, void (*)(void *, void *))(g_list, rootSignature);
            COM(g_list, 20, void (*)(void *, UINT))(g_list, 4);
            COM(g_list, 12, void (*)(void *, UINT, UINT, UINT, UINT))(g_list, 3, 1, 0, 0);
        }
        int checkThisFrame = frames == 0 && readback;
        if (checkThisFrame) {
            record_readback(backbuffer, readback);
        } else {
            transition(backbuffer, 0x4, 0);
        }
        COM(g_list, 9, HRESULT (*)(void *))(g_list); /* Close */
        /* ExecuteCommandLists (10), IDXGISwapChain::Present (8) */
        COM(g_queue, 10, void (*)(void *, UINT, void **))(g_queue, 1, &g_list);
        presentHr = COM(swapchain, 8, HRESULT (*)(void *, UINT, UINT))(swapchain, (UINT)syncInterval, 0);
        slotFence[slot] = signal_queue();
        if (FAILED(presentHr)) break;
        frames++;
        if (checkThisFrame) {
            if (!wait_for(slotFence[slot])) {
                gpuHung = 1;
                break;
            }
            pixelsExpected = check_pixels(readback, pipeline != 0);
            results_add(pixelsExpected ? "pixels=expected" : "pixels=unexpected");
            results_flush();
        }
    }
    if (!gpuHung && !wait_for(g_fence_value)) gpuHung = 1;
    step_hr("last_present", presentHr);
    report_fps(frames, t - start);
    if (gpuHung) finish("status=gpu_timeout", 3);
    if (FAILED(presentHr)) finish("status=present_failed", 3);
    if (!pixelsExpected) finish("status=pixels_unverified", 3);
    finish(pipeline ? "status=ok" : "status=clear_only", pipeline ? 0 : 3);
}

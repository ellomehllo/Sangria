/* D3D9 probe: HAL device, clear + present loop. DXMT does not translate
 * Direct3D 9, so this is the program Recommended should send to DXVK. */
#include "common.h"

typedef struct {
    UINT BackBufferWidth, BackBufferHeight, BackBufferFormat, BackBufferCount, MultiSampleType;
    DWORD MultiSampleQuality; UINT SwapEffect; HWND hDeviceWindow; BOOL Windowed, EnableAutoDepthStencil;
    UINT AutoDepthStencilFormat; DWORD Flags; UINT FullScreen_RefreshRateInHz, PresentationInterval;
} D3DPRESENT_PARAMETERS;
typedef struct {
    char Driver[512], Description[512], DeviceName[32]; LARGE_INTEGER DriverVersion;
    DWORD VendorId, DeviceId, SubSysId, Revision; GUID DeviceIdentifier; DWORD WHQLLevel;
} D3DADAPTER_IDENTIFIER9;

IMPORT void *Direct3DCreate9(UINT sdk);

void entry(void) {
    results_init();
    results_add("probe=d3d9");
    char line[640];
    static const WCHAR title[] = {'D', '3', 'D', '9', ' ', 'P', 'r', 'o', 'b', 'e', 0};
    HWND hwnd = make_window(title, 1280, 720);

    void *d3d = Direct3DCreate9(32);
    if (!d3d) {
        results_add("status=create9_failed");
        results_flush();
        ExitProcess(2);
    }
    /* IDirect3D9::GetAdapterIdentifier (5) */
    static D3DADAPTER_IDENTIFIER9 id;
    COM(d3d, 5, HRESULT (*)(void *, UINT, DWORD, D3DADAPTER_IDENTIFIER9 *))(d3d, 0, 0, &id);
    wsprintfA(line, "adapter=%s vendor=0x%04x", id.Description, id.VendorId);
    results_add(line);

    D3DPRESENT_PARAMETERS pp;
    memset(&pp, 0, sizeof(pp));
    pp.BackBufferWidth = 1280;
    pp.BackBufferHeight = 720;
    pp.BackBufferFormat = 22; /* D3DFMT_X8R8G8B8 */
    pp.BackBufferCount = 1;
    pp.SwapEffect = 1; /* DISCARD */
    pp.hDeviceWindow = hwnd;
    pp.Windowed = 1;
    pp.PresentationInterval = 0x80000000; /* IMMEDIATE */
    void *device = 0;
    /* IDirect3D9::CreateDevice (16), HAL, HARDWARE_VERTEXPROCESSING */
    HRESULT hr = COM(d3d, 16, HRESULT (*)(void *, UINT, UINT, HWND, DWORD, D3DPRESENT_PARAMETERS *, void **))(
        d3d, 0, 1, hwnd, 0x40, &pp, &device);
    results_hr("create_device", hr);
    results_flush();
    if (FAILED(hr)) {
        results_add("status=device_failed");
        results_flush();
        ExitProcess(2);
    }

    int seconds = arg_int("secs=", 10);
    double start = now_seconds(), end = start + seconds, t = start;
    long frames = 0;
    HRESULT presentHr = 0;
    while (!g_quit && (t = now_seconds()) < end) {
        pump();
        DWORD color = 0xff000000u | (DWORD)((frames * 3) & 0xff) << 8 | 0x40;
        /* Clear (43), BeginScene (41), EndScene (42), Present (17) */
        COM(device, 43, HRESULT (*)(void *, DWORD, const void *, DWORD, DWORD, float, DWORD))(device, 0, 0, 1,
                                                                                               color, 1.0f, 0);
        COM(device, 41, HRESULT (*)(void *))(device);
        COM(device, 42, HRESULT (*)(void *))(device);
        presentHr = COM(device, 17, HRESULT (*)(void *, const void *, const void *, HWND, const void *))(device, 0, 0,
                                                                                                       0, 0);
        if (FAILED(presentHr)) break;
        frames++;
    }
    results_hr("last_present", presentHr);
    report_fps(frames, t - start);
    results_add(FAILED(presentHr) ? "status=present_failed" : "status=ok");
    results_flush();
    ExitProcess(0);
}

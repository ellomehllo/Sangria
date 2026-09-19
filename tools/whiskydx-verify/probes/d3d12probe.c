/* D3D12 probe: imports d3d12.dll and creates a device. Its import table is
 * what the app's API check reads to refuse DXMT with a pointer to D3DMetal. */
#include "common.h"

IMPORT HRESULT D3D12CreateDevice(void *adapter, UINT minimumLevel, const GUID *riid, void **device);

static const GUID IID_ID3D12Device = {0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}};

void entry(void) {
    results_init();
    results_add("probe=d3d12");
    void *device = 0;
    HRESULT hr = D3D12CreateDevice(0, 0xb000, &IID_ID3D12Device, &device);
    results_hr("create_device", hr);
    results_add(FAILED(hr) ? "status=device_failed" : "status=ok");
    results_flush();
    ExitProcess(FAILED(hr) ? 2 : 0);
}

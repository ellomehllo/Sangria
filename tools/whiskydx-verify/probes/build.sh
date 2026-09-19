#!/bin/sh
# Builds the D3D probe executables into out/ with Xcode clang + pelink.py.
set -e
cd "$(dirname "$0")"
CFLAGS="-target x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector -mno-stack-arg-probe -fno-asynchronous-unwind-tables -Wall -Wno-unused-function"
K32=kernel32.dll:GetModuleHandleW,ExitProcess,QueryPerformanceCounter,QueryPerformanceFrequency,GetModuleFileNameW,CreateFileW,WriteFile,CloseHandle,GetCommandLineA,CreateEventW,WaitForSingleObject
U32=user32.dll:RegisterClassExW,CreateWindowExW,ShowWindow,PeekMessageW,TranslateMessage,DispatchMessageW,DefWindowProcW,PostQuitMessage,wsprintfA
mkdir -p out
for fl in b000:fl11_0 a100:fl10_1 a000:fl10_0; do
  lvl=${fl%%:*}; tag=${fl##*:}
  clang $CFLAGS -DPROBE_FL=0x$lvl -c d3d11probe.c -o out/d3d11-$tag.obj
  python3 pelink.py out/d3d11-$tag.obj out/D3D11Probe-${tag}.exe entry 2 $K32 $U32 d3d11.dll:D3D11CreateDeviceAndSwapChain d3dcompiler_47.dll:D3DCompile
done
clang $CFLAGS -c d3d9probe.c -o out/d3d9.obj
python3 pelink.py out/d3d9.obj out/D3D9Probe.exe entry 2 $K32 $U32 d3d9.dll:Direct3DCreate9
clang $CFLAGS -c d3d12probe.c -o out/d3d12.obj
python3 pelink.py out/d3d12.obj out/D3D12Probe.exe entry 2 $K32 $U32 d3d12.dll:D3D12CreateDevice,D3D12SerializeRootSignature \
  dxgi.dll:CreateDXGIFactory1 d3dcompiler_47.dll:D3DCompile ntdll.dll:RtlGetVersion

#!/bin/zsh
# usage: matrix.sh [bottle name]  (default "DX Tests")
DIR=${0:A:h}
H=$DIR/harness/.build/debug/Harness
B=${1:-"DX Tests"}
P="$($H bottle-path "$B")/drive_c/Probes"
[ -x "$H" ] || { echo "build the harness first: (cd $DIR/harness && swift build)"; exit 1; }
[ -d "$P" ] || { echo "copy probes/out/*.exe into $P first"; exit 1; }
# Functional + benchmark matrix for the Whisky DX build, through the harness.
BENCH="secs=10 iters=8192"
KEEP='preview:|launched:|LAUNCH|verification:|run log:|system32/d3d11|system32/dxgi|system32/d3d9|avg_fps|status=|feature_level=|adapter=|create_device|compile_ps|capture|wine log:|log dxmt|log dxvk|MTL|Found config|pixels=|os_version='
run() { echo "\n### $*"; $H run "$B" "$@" --wait 90 2>&1 | grep -E "$KEEP"; }

echo "===== 1. DXMT bottle (default)"
$H set-backend "$B" dxmt
for t in fl11_0 fl10_1 fl10_0; do run "$P/D3D11Probe-$t.exe" --args "$BENCH"; done
run "$P/D3D9Probe.exe" --args "secs=10"
run "$P/D3D12Probe.exe"

echo "\n===== 2. One-click switch: bottle -> DXVK, no rebuild"
$H set-backend "$B" dxvk
for t in fl11_0 fl10_1 fl10_0; do run "$P/D3D11Probe-$t.exe" --args "$BENCH"; done
run "$P/D3D9Probe.exe" --args "secs=10"
run "$P/D3D12Probe.exe"

echo "\n===== 3. Per-program override in a DXVK bottle: FL11 -> DXMT"
run "$P/D3D11Probe-fl11_0.exe" --program-backend dxmt --args "secs=5 iters=8192"
run "$P/D3D11Probe-fl11_0.exe" --program-backend inherit --args "secs=3"

echo "\n===== 4. Recommended bottle: D3D9 -> DXVK, D3D11 -> DXMT, D3D12 -> D3DMetal or WineD3D (vkd3d)"
$H set-backend "$B" recommended
run "$P/D3D9Probe.exe" --args "secs=4"
run "$P/D3D11Probe-fl11_0.exe" --args "secs=4"
run "$P/D3D12Probe.exe" --args "secs=4"

echo "\n===== 4b. Per-program Windows version: win7, then cleared"
run "$P/D3D12Probe.exe" --program-backend recommended --win-version win7 --args "secs=2 iters=256"
run "$P/D3D12Probe.exe" --program-backend inherit --win-version inherit --args "secs=2 iters=256"

echo "\n===== 5. Frame capture on DXMT (automatic, frame 30)"
$H set-backend "$B" dxmt
run "$P/D3D11Probe-fl11_0.exe" --capture D3D11Probe-fl11_0 --auto-frame 30 --args "secs=4 iters=256"

echo "\n===== 6. Metal API + shader validation on DXMT"
run "$P/D3D11Probe-fl11_0.exe" --api-validation --shader-validation --args "secs=4 iters=256"

echo "\n===== 7. dxmt.conf: 60 fps cap"
$H set-dxmt "$B" 60 off 2
run "$P/D3D11Probe-fl11_0.exe" --args "secs=6 iters=256"
echo "\n===== 8. dxmt.conf: MetalFX spatial 1.5x"
$H set-dxmt "$B" 0 on 1.5
run "$P/D3D11Probe-fl11_0.exe" --args "secs=4 iters=256"
$H set-dxmt "$B" 0 off 2

echo "\n===== 9. WineD3D backend"
$H set-backend "$B" wined3d
run "$P/D3D11Probe-fl11_0.exe" --args "secs=4 iters=256"
$H set-backend "$B" dxmt
echo "\n===== done"

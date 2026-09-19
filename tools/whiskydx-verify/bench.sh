#!/bin/zsh
# usage: bench.sh [bottle name]  (default "DX Tests")
DIR=${0:A:h}
H=$DIR/harness/.build/debug/Harness
B=${1:-"DX Tests"}
P="$($H bottle-path "$B")/drive_c/Probes"
[ -x "$H" ] || { echo "build the harness first: (cd $DIR/harness && swift build)"; exit 1; }
[ -d "$P" ] || { echo "copy probes/out/*.exe into $P first"; exit 1; }
for be in dxmt dxvk; do
  $H set-backend "$B" $be > /dev/null
  for t in fl11_0 fl10_1 fl10_0; do
    for rep in 1 2; do
      echo "### $be $t rep$rep"
      $H run "$B" "$P/D3D11Probe-$t.exe" --measure --args "secs=10 iters=8192" --wait 90 2>&1 | grep -E "verification|avg_fps|metal HUD|status=|feature_level=|adapter="
    done
  done
done
$H set-backend "$B" dxmt > /dev/null
echo "### dxmt d3d9"
$H run "$B" "$P/D3D9Probe.exe" --measure --args "secs=10" --wait 90 2>&1 | grep -E "preview|verification|avg_fps|metal HUD|status=|adapter="
echo "### done"

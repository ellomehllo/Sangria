# Whisky DX: verification

Run on 2026-09-19. Apple M5, macOS 26.6.2, Xcode 27.0, Whisky runtime 3.1.1 (Wine 11.0, DXMT 0.80,
DXVK-macOS 1.10.3, MoltenVK 1.4.1).

## How it was tested

No Windows games were installed on the test machine, and only the Wine runtime was downloaded. So the
test titles are five small Direct3D programs written for this purpose, in
[`tools/whiskydx-verify/probes`](../tools/whiskydx-verify/probes). They are compiled with Xcode's own
clang (`-target x86_64-pc-windows-msvc`) and linked by a ~200-line Python PE linker (`pelink.py`), since
no Windows linker was available.

| Probe | What it does |
|---|---|
| `D3D11Probe-fl11_0` | D3D11 device + swapchain at feature level 11_0, HLSL compiled at runtime (vs/ps_5_0), full-screen Mandelbrot pixel shader |
| `D3D11Probe-fl10_1` | Same at feature level 10_1 (vs/ps_4_0) |
| `D3D11Probe-fl10_0` | Same at feature level 10_0 (vs/ps_4_0) |
| `D3D9Probe` | D3D9 HAL device, clear and present |
| `D3D12Probe` | Imports `d3d12.dll`, creates a device |

Each probe writes `<exe>.results.txt` (device result, feature level, adapter, shader compile status,
frames, FPS). A headless harness ([`tools/whiskydx-verify/harness`](../tools/whiskydx-verify/harness))
links this repo's WhiskyKit and drives the app's own code: runtime install, bottle creation (the same
steps as the app's Create Bottle), `Program.launchWithUserMode`, environment composition, DXMT
deployment, log verification and HUD measurement. So what it reports is what the app does. The
benchmark uses 8,192 Mandelbrot iterations at 1280×720 to keep the GPU the bottleneck below the
120 Hz display rate.

To rerun:

```sh
cd tools/whiskydx-verify
(cd probes && ./build.sh)                       # builds probes/out/*.exe
(cd harness && swift build)
harness/.build/debug/Harness status
cp probes/out/*.exe "$(harness/.build/debug/Harness bottle-path 'DX Tests')/drive_c/Probes/"
./matrix.sh "DX Tests"                          # functional matrix
./bench.sh "DX Tests"                           # DXMT vs DXVK benchmark
```

## Functional results

| Check | Result |
|---|---|
| Unmodified upstream builds | Yes, after installing SwiftLint (the build phase requires it) |
| App launches | Yes, after switching the project to local signing. With a local identity, the hardened runtime's library validation refused `Whisky.debug.dylib` and dyld aborted at launch (this also affects the unmodified upstream build) |
| Runtime install (setup flow) | 3.1.1 downloaded, SHA-256 verified, installed |
| Bottle creation | Wine 11.0 prefix, **backend defaulted to DXMT**, `Z:` → `/` present |
| DXMT deployment | Native `d3d11`/`dxgi`/`d3d10core` in `system32`, builtin `winemetal` |
| Generated `dxmt.conf` reaches DXMT | DXMT logs `Found config file: Z:/…/dxmt.conf` |
| Per-program DXMT logs | Written to `…/Graphics/<bottle>/<program>/dxmt/` |
| Backend check | "DXMT confirmed" on DXMT runs, "DXVK confirmed" on DXVK runs, "not verifiable" on WineD3D |
| D3D11 at FL 11_0 / 10_1 / 10_0 on DXMT | Device, swapchain, runtime HLSL → DXMT shader translation, presents: all OK |
| D3D11 on DXVK | OK after the `dxgi.dll` fix. Before it, every D3D11 program failed to start once the bottle had run DXMT |
| One-click switching | DXMT → DXVK → DXMT → DXVK in one bottle, each run confirmed by logs, nothing reinstalled |
| Per-program override | FL11 probe on DXMT inside a DXVK bottle: DXMT confirmed |
| Recommended | D3D11 → DXMT, with the reason recorded in the run history. Launcher → DXVK and D3D12 → D3DMetal are covered by unit tests only (no launcher or D3DMetal here) |
| D3D12 on DXMT / DXVK | Refused before launch: "…Direct3D 12, which DXMT doesn't support yet… D3DMetal handles Direct3D 12, but its payload isn't installed…" |
| D3D9 on DXMT and DXVK | Runs through WineD3D (adapter "NVIDIA GeForce 6800" is WineD3D's placeholder). App shows a caution explaining so |
| WineD3D + D3D11 | Device creation fails (`0x80004005`), as upstream documents |
| Frame capture (automatic, frame 30) | `D3D11Probe-fl11_0_F.30_….gputrace` written beside the exe and listed |
| Metal API + shader validation | Run completes with both layers on |
| MetalFX spatial 1.5× | `DXMT_METALFX_SPATIAL_SWAPCHAIN=1` exported, run OK, no "not supported" warning |
| DXMT frame cap 60 / 30 | **Not enforced by DXMT 0.80**: the Metal HUD measured unchanged ~8.3 ms frame intervals |
| FPS via Metal HUD | Matches the probe's own counter within 1–2% |
| D3DMetal | GPTK 3.0 payload imports from the local GPTK app, but runtime 3.1.1 is not GPTK-capable, so it is not deployed (deploying it was tried once and reverted) |
| Run log keeps program output | Yes, after the log-name fix. Headers now carry `Graphics Backend:` and `Detected Graphics API:` |

## Benchmark (synthetic, GPU-bound)

Average of two 10-second runs. The probe's frame counter and the Metal HUD agreed within 2%. HUD
figures shown. The HUD overlay costs about 15% (DXMT at FL 11_0 was 73.8 fps without it).

| Probe | DXMT | DXVK | D3DMetal | WineD3D |
|---|---|---|---|---|
| D3D11 FL 11_0 (vs/ps_5_0) | **61.8 fps** ✅ confirmed | 7.1 fps ✅ confirmed | not deployable on runtime 3.1.1 | device creation fails |
| D3D11 FL 10_1 (vs/ps_4_0) | **61.3 fps** ✅ confirmed | 6.2 fps ✅ confirmed | not deployable | — |
| D3D11 FL 10_0 (vs/ps_4_0) | **56.8 fps** ✅ confirmed | 6.3 fps ✅ confirmed | not deployable | — |
| D3D9 (clear/present) | runs on WineD3D (1,257 fps, trivial load) | runs on WineD3D | — | same path |
| D3D12 (device) | refused before launch | refused before launch | not deployable | refused |

These ten results are the first entries in the Compatibility Notes database.

The DXVK gap is specific to this loop-heavy pixel shader: at a light load (256 iterations) both backends
reach the 120 Hz display rate (DXMT ~120, DXVK ~117). Treat it as evidence that DXMT's direct DXBC →
Metal compilation handles this shader far better than DXBC → SPIR-V → MSL, not as a game benchmark.

## Not verified

- Real games. None were installed and only the runtime download was approved. Record them from each
  program's page with *Add Note from Last Run…*, with **Measure FPS with the Metal HUD** on, per
  backend.
- Pressing F10 by hand. The automatic-frame path uses the same environment and was verified.
- The app's windows were not screenshotted, since that needs a Screen Recording permission. The app was
  launched, stayed up with its main window and no crash report, and its UI was verified by building
  (strict SwiftLint included) and through the WhiskyKit logic it displays.

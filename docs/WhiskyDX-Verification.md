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
| `D3D12Probe` | Imports `d3d12.dll`: device, queue, flip swapchain, the same Mandelbrot shader through a root signature and PSO, presented until time runs out. The first frame is read back and two pixels checked, so `status=ok` means the draw landed. Also reports the maximum feature level and the Windows version the program sees. `min_fl=` sets the minimum feature level asked for |

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
| Recommended | D3D11 → DXMT and D3D12 → WineD3D (vkd3d, no D3DMetal here), each with its reason recorded in the run history. Launcher → DXVK and D3D12 → D3DMetal are covered by unit tests only (no launcher or D3DMetal here) |
| D3D12 on DXMT / DXVK | Refused before launch: "…Direct3D 12, which DXMT doesn't support yet… D3DMetal (Apple's Game Porting Toolkit) isn't available in this runtime, but Wine's own Direct3D 12 (vkd3d…) can run it: use WineD3D for this program." |
| D3D12 on WineD3D (vkd3d) | Builtin `dxgi` and `d3d12` load, then `winevulkan` and MoltenVK 1.4.1 on the Apple M5 (`WINEDEBUG=+loaddll`). Device, swapchain, runtime HLSL (vs/ps_5_0), root signature, PSO, draw and present all OK. Read-back pixels as expected (centre 255,255,255, corner 0,0,0). Maximum feature level 11_0; asking for 12_0 fails with `0x80070057`. Adapter reported as "NVIDIA GeForce 6800" |
| Per-program Windows version | `win7` override: the probe sees 6.1.7601 and `user.reg` holds `"Version"="win7"` under `AppDefaults\\D3D12Probe.exe`. Override cleared: back to 10.0.19045 |
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
| D3D12 (draw + present) | refused before launch | refused before launch | not deployable | runs through vkd3d, see below |

These ten results are the first entries in the Compatibility Notes database.

The DXVK gap is specific to this loop-heavy pixel shader: at a light load (256 iterations) both backends
reach the 120 Hz display rate (DXMT ~120, DXVK ~117). Treat it as evidence that DXMT's direct DXBC →
Metal compilation handles this shader far better than DXBC → SPIR-V → MSL, not as a game benchmark.

Direct3D 12 on WineD3D's vkd3d was measured later the same day, in a single 8-second run at 8,192
iterations, by the probe's own counter with no HUD: **84.2 fps**. D3D11 FL 11_0 on DXMT, run right
after with the same settings, gave 75.6 fps. One run each, so read it as "comparable on this shader",
not as vkd3d being faster.

## GPTK-capable engine (v4.6.4-beta.1), later the same day

Upstream's prerelease engine was downloaded from `frankea/Whisky` release `v4.6.4-beta.1`
(481,348,675 bytes, SHA-256 `c8e6a10d…18cb12`, matching the release notes) and unpacked in place of
3.1.1, which is kept at `~/Libraries-3.1.1-backup`. It reports wine-11.16, `gptkCapable`, DXMT 0.80
(native, in `Libraries/DXMT/x64`) and DXVK 1.10.3, and the app treats all four backends as available.
The stored GPTK 3.0 payload deployed through `deployStoredPayloadIfCapable()`.

| Check | Result |
|---|---|
| D3D12 on D3DMetal, GPTK 3.0, device created before DXGI | Crash at address 0 inside Apple's `D3D12CreateDevice` (relay trace). The engine's dxgi shim had not loaded Apple's dxgi yet |
| Same, DXGI factory first | Adapter "AMD Compatibility Mode" (D3DMetal), device at **feature level 12_2**, queue OK, then a crash inside D3DMetal creating the swapchain |
| Control: same probe in the GPTK 3.0 app's own wine-7.7 | Adapter "AMD Compatibility Mode", feature level 12_2, swapchain, clear and present OK (118 fps). Its HLSL compiler fails the probe's shaders, so no draw |
| D3D12 on vkd3d | After `wineboot -u` so the prefix matched the engine: draw verified, 85–92 fps, adapter now reported as "Apple M5". Before it, the prefix still held Apple's DLLs from the deployed state and vkd3d crashed calling into them |
| D3D11 FL 11_0, 8,192 iterations | DXMT 74.3 fps (confirmed), DXVK 9.4 fps (confirmed), WineD3D still fails device creation (`0x80004005`) |
| D3D9 | Runs through WineD3D (adapter "NVIDIA GeForce 8800 GTX") |

So D3DMetal is blocked on the payload now, not the engine: upstream plays STALKER CoP Enhanced (DX12)
through D3DMetal on this engine lineage with GPTK 4.0 beta 2. GPTK 3.0 was then deployed again at the user's request, and a rerun gave the same result: device at
feature level 12_2 and queue OK, crash creating the swapchain.
The probe now creates its DXGI factory first (`device_first=1` restores the old order) and flushes its
results after every step, so a crash leaves the last step that worked on disk. "DX Tests" has Wine's
crash dialog turned off (`HKCU\Software\Wine\WineDbg\ShowCrashDialog=0`) so failed runs don't stop
on a modal.

## D3DMetal with GPTK 4.0 beta 2

The user's download, `Game_Porting_Toolkit_4.0_beta_2.dmg`, holds the evaluation environment image;
its `D3DMetal.framework` and `libd3dshared.dylib` pass `codesign -R="anchor apple"` and report 4.0b2.
It replaced the GPTK 3.0 payload, deployed, and both bottles were refreshed with `wineboot -u`.

| Probe on D3DMetal | Result |
|---|---|
| D3D12, factory first | Feature level 12_2, draw verified, 74.5 fps (8,192 iterations) |
| D3D12, device first | 73.1 fps, draw verified. Crashed at address 0 while the runtime's DXGI interposer was installed |
| D3D12, minimum feature level 12_0 | 74.5 fps, draw verified (vkd3d refuses 12_0) |
| D3D11 FL 11_0 / FL 10_0 | 75.6 / 69.3 fps. Crashed at address 0 while the DXGI interposer was installed |
| D3D11 FL 11_0 on DXMT, same session | 75.8 fps, confirmed |

Adapter on D3DMetal: "AMD Compatibility Mode" (0x1002:0x66af). All of it ran through the app's own
deploy path after the DXGI-interposer change, with no files swapped by hand.

## Frame rate limit

Light load (64 iterations), so an uncapped run sits at the 120 Hz display rate:

| Setting | D3DMetal D3D12 | D3DMetal D3D11 | DXMT D3D11 |
|---|---|---|---|
| No limit | 120.3 fps | 120.3 | 120.3 |
| `D3DM_MAX_FPS=60` | 120.3 (ignored) | 119.5 | — |
| `d3d11.preferredMaxFrameRate = 60` | — | — | 120.3 (ignored) |
| Sync interval 2 | 118.7 (ignored) | — | 120.3 (ignored) |
| Bottle frame rate limit 60 | **60.3**, draw verified | **60.3** | **60.4** |

A program limit of 30 under a bottle limit of 60 gave 30.5; a program limit of Off gave 120.3. Under
heavy load (8,192 iterations, ~74 fps uncapped) a limit of 60 held 60.3. These runs used the limiter
the Xcode build put in the app's Resources, through the harness's `set-fps` and `--fps-limit`. DXVK
was not measured: with D3DMetal deployed its `d3d11` fails to create a device (the known
`removeStaleNativeDXGI` gap: DXMT's native dxgi stays in the prefix when GPTK originals exist).

## Not verified

- Real games. None were installed and only the runtime download was approved. Record them from each
  program's page with *Add Note from Last Run…*, with **Measure FPS with the Metal HUD** on, per
  backend.
- Direct3D 12 with Shader Model 6 (DXIL) shaders, and 32-bit Direct3D 12. The probe compiles SM 5.
- Pressing F10 by hand. The automatic-frame path uses the same environment and was verified.
- The app's windows were not screenshotted, since that needs a Screen Recording permission. The app was
  launched, stayed up with its main window and no crash report, and its UI was verified by building
  (strict SwiftLint included) and through the WhiskyKit logic it displays.

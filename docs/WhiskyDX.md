# Whisky DX: personal build notes

A personal, non-commercial build of the [frankea/Whisky](https://github.com/frankea/Whisky) community
fork (GPL-3.0), which continues the archived [whisky-app/whisky](https://github.com/whisky-app/whisky).
Its differentiator is a first-class graphics backend story with **DXMT as the default**, D3DMetal and
DXVK kept as equal alternatives, and tooling to see and record what actually runs.

All upstream license notices are intact: GPL-3.0 headers on every Whisky-derived file, and DXMT's MIT
`LICENSE` ships inside the runtime payload at `Libraries/DXMT/LICENSE`.

## Identity

| | This build | Upstream |
|---|---|---|
| Bundle identifier | `local.bluevsh.WhiskyDX` | `com.franke.Whisky` |
| Display name | Whisky DX | Whisky |
| Runtime and app data | `~/Library/Application Support/local.bluevsh.WhiskyDX` | `.../com.franke.Whisky` |
| Bottles | `~/Library/Containers/local.bluevsh.WhiskyDX/Bottles` | `.../com.franke.Whisky/Bottles` |
| Logs | `~/Library/Logs/local.bluevsh.WhiskyDX` | `.../com.franke.Whisky` |
| Updates | Sparkle not started, menu item removed | Sparkle from frankea.github.io |
| Telemetry | No PostHog token, so it cannot send | Opt-in |

Sparkle is off on purpose: upstream releases are signed with upstream's key, so Sparkle would happily
install upstream Whisky over this build. The Wine runtime still downloads from upstream's GitHub
releases (SHA-256 verified), which is the runtime this build is tested against.

## Building

```sh
brew install swiftlint   # the app target's build phase runs `swiftlint --strict`
xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Whisky.app
```

Or open `Whisky.xcodeproj` in Xcode and press Run. The project signs locally (ad-hoc, no team) with
the hardened runtime off. Upstream's team ID isn't usable here, and with a local identity the hardened
runtime's library validation refuses the Debug build's `Whisky.debug.dylib` ("different Team IDs"), so
the app aborted at launch. Nothing here is notarized, so the hardened runtime buys nothing. To keep
macOS privacy permissions across rebuilds, sign with a stable local certificate instead:
`xcodebuild … CODE_SIGN_IDENTITY="Blue Local Dev" build`.

WhiskyKit's tests run with `swift test` in `WhiskyKit/`.

## Backends

| Backend | Translates | Notes |
|---|---|---|
| **DXMT** 0.80 (default) | Direct3D 10, 11 → Metal | MIT. The last MIT release; DXMT 1.0+ is LGPL. No Direct3D 12. |
| D3DMetal (GPTK) | Direct3D 10, 11, 12 → Metal | Apple's, imported from a Game Porting Toolkit payload. Needs a GPTK-capable Wine engine (see Limitations). |
| DXVK-macOS 1.10.3 | Direct3D 10, 11 → Vulkan → MoltenVK | This runtime's build has no `d3d9.dll`. Launcher UIs (Steam, Epic, …) render only on DXVK. |
| WineD3D | Direct3D 9 and older → OpenGL | Cannot create a Direct3D 11 device on current macOS. |

**New bottles** are created on DXMT when the installed runtime has a usable DXMT payload, otherwise on
Recommended. **Recommended** decides per launch, in this order: launchers → DXVK; Direct3D 12 →
D3DMetal when installed; Direct3D 9-only → DXVK when its payload ships `d3d9.dll`; otherwise DXMT, then
D3DMetal, then DXVK. The reason is shown on the program page and stored with every run.

**Per-program overrides** (program page → Program Settings → Graphics Backend) run one program on a
different backend inside the same bottle.

**Switching is a relaunch, not a rebuild.** Each launch deploys the chosen layer's DLLs into the
prefix and sets its overrides, so a bottle can go DXMT → DXVK → DXMT with nothing reinstalled. This was
verified end to end, after fixing the DXMT → DXVK `dxgi.dll` bug below.

## DXMT settings (bottle → Config → Graphics)

Written to `<bottle>/dxmt.conf` on every DXMT launch and passed as `DXMT_CONFIG_FILE=Z:/…`:

- **Frame rate limit**: `d3d11.preferredMaxFrameRate`. Offered values are factors of the display's
  refresh rate. *Caveat:* DXMT 0.80 confirms it loaded the file, but on macOS 26.6 / M5 the Metal HUD
  measured unchanged ~8.3 ms frame intervals with a 30 fps cap, so it is not enforced here.
- **MetalFX spatial upscaling**: exports `DXMT_METALFX_SPATIAL_SWAPCHAIN=1` and writes
  `d3d11.metalSpatialUpscaleFactor` (1.0–2.0).
- **Extra options**: raw `key = value` lines appended after the managed ones (later lines win).
- **Preview**: the exact file the next launch writes.

A `dxmt.conf` placed next to a game is ignored while `DXMT_CONFIG_FILE` is set. Put those lines in
Extra options.

## Program page

**Graphics**: detected API (from the import table and the D3D12 Agility SDK folder), the backend the
next launch will use and why, and the last run's backend with a log-based check:

| Check | Meaning |
|---|---|
| Confirmed | The expected layer wrote its log during the run. |
| Mismatch | A different layer wrote logs, so the backend in use isn't the one you picked. |
| Not logged yet | No log. The program may not have created a D3D device, or uses another API. |
| Not verifiable | D3DMetal and WineD3D write no log file; neither DXMT nor DXVK loaded. |

DXMT and DXVK write to per-program folders under `~/Library/Logs/local.bluevsh.WhiskyDX/Graphics/
<bottle>/<program>/{dxmt,dxvk}`, which is what makes a mismatch provable.

**Graphics Debug**:
- Log viewer that tails those files.
- Metal API validation (`MTL_DEBUG_LAYER=1`) and shader validation (`MTL_SHADER_VALIDATION=1`).
- DXMT log level (`DXMT_LOG_LEVEL`).
- **Measure FPS with the Metal HUD** (`MTL_HUD_ENABLED=1`, `MTL_HUD_LOG_ENABLED=1`). The run log's HUD
  frame counter gives the average FPS that reached the display on any backend. New compatibility notes
  pick it up. The HUD overlay itself cost about 15% in the synthetic test.
- **Launch with Frame Capture**: `MTL_CAPTURE_ENABLED=1` + `DXMT_CAPTURE_EXECUTABLE`. Press F10 in
  game, or set an automatic frame (`DXMT_CAPTURE_FRAME`). The `.gputrace` lands beside the rendering
  executable and is listed with Open (Xcode) and Reveal. DXMT only.

**Graphics API check**: launching a Direct3D 12 program on DXMT, DXVK or WineD3D stops with
*"Direct3D 12 isn't supported by DXMT yet"*. The options are **Use D3DMetal for This Program** (when
installed), **Launch Anyway**, or **Always Launch This Program Anyway**. Launches from other places
(library, pins, Run…) show the same message as an error toast. Detection reads import tables, so
engines that load Direct3D at runtime (most Unreal and Unity titles) show "Not detected" and are not
checked.

**Compatibility Notes**: *Add Note from Last Run…* prefills title, backend, date, API, bottle,
verification and measured FPS. The **Compatibility Notes** window (Window menu, ⇧⌘C) groups notes by
title so backends compare side by side, and marks the fastest measured one. Filter, search, edit,
duplicate-for-another-backend, and CSV export are available. Stored as JSON at
`~/Library/Application Support/local.bluevsh.WhiskyDX/CompatibilityNotes.json`. A file that fails to
decode is moved aside, never overwritten.

## Upstream bugs fixed here

- **Run logs lost the program's output.** Log names have one-second resolution, and every launch also
  runs `wine reg import` within that second. Its log file atomically replaced the program's, so the
  program wrote into an unlinked file, and the Console view and crash classifier read the import's
  output instead. Log files are now created exclusively, with `-2`, `-3` suffixes.
- **DXVK broke after a DXMT launch.** DXVK-macOS ships no `dxgi.dll`, and the cleanup of DXMT's
  leftover native `dxgi.dll` deleted it without restoring Wine's builtin copy. DXVK's `d3d11.dll` then
  failed to import `dxgi.dll`, so no Direct3D 11 program could start. The builtin copy is now restored.
- **PE32+ optional header**: stack and heap sizes were read as 4 bytes in 64-bit images, putting
  `NumberOfRvaAndSizes` 16 bytes early.

## Limitations found on this machine

- **D3DMetal can't be enabled with runtime 3.1.1.** The GPTK payload imports, but the app deploys it
  only onto a Wine engine with GPTK exception-unwind support, and 3.1.1's engine reports it lacks that.
  Direct3D 12 titles therefore have no backend in this setup yet.
- **Direct3D 9** renders through WineD3D on every backend with this runtime (no DXVK `d3d9.dll`, and
  DXMT and D3DMetal start at Direct3D 10).
- **DXMT frame rate limit** is not enforced by DXMT 0.80 here (see above).

## Verification

See [WhiskyDX-Verification.md](WhiskyDX-Verification.md).

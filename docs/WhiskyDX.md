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
| WineD3D | Direct3D 9 and older → OpenGL; Direct3D 12 → Vulkan → MoltenVK through Wine's vkd3d | Cannot create a Direct3D 11 device on current macOS. Its Direct3D 12 tops out at feature level 11_0 and reports the adapter as "NVIDIA GeForce 6800". |

WineD3D resets every translation DLL to builtin, and on this runtime the builtin `d3d12` is Wine's
vkd3d, with Wine's own `dxgi` beside it for the swapchain. That is the only Direct3D 12 available while
D3DMetal can't be deployed (see Limitations).

**New bottles** are created on DXMT when the installed runtime has a usable DXMT payload, otherwise on
Recommended. **Recommended** decides per launch, in this order: launchers → DXVK; Direct3D 12 →
D3DMetal when installed, otherwise WineD3D (vkd3d) for a program that imports `d3d12.dll`; Direct3D
9-only → DXVK when its payload ships `d3d9.dll`; otherwise DXMT, then D3DMetal, then DXVK. A program
that only ships the Agility SDK (`D3D12/D3D12Core.dll`) loads `d3d12` itself, so without D3DMetal it
stays on DXMT, whose preset disables `d3d12`: an engine with a Direct3D 11 renderer falls back to it.
The reason is shown on the program page and stored with every run.

**Per-program overrides** (program page → Program Settings → Graphics Backend) run one program on a
different backend inside the same bottle.

**Use D3DMetal** is a one-click version of that override for D3DMetal: a checkbox next to Run on the
program page, and a checkmark item in the right-click menu of the program list, pins and the library.
It is only offered when D3DMetal is deployed, and can always be turned off.

**Per-program Windows version** (Program Settings → Windows Version) is written to
`HKCU\Software\Wine\AppDefaults\<exe>` as `Version` on each launch, in the same `reg import` as the
per-program DLL overrides, and removed again when the override is turned off. It applies to that
executable only. Some games pick Direct3D 11 when they see Windows 7. Like the DLL overrides, it
replaces a per-application version set in `winecfg` for any executable launched from Whisky DX.

**Switching is a relaunch, not a rebuild.** Each launch deploys the chosen layer's DLLs into the
prefix and sets its overrides, so a bottle can go DXMT → DXVK → DXMT with nothing reinstalled. This was
verified end to end, after fixing the DXMT → DXVK `dxgi.dll` bug below.

## Frame rate limit (bottle → Config → Graphics, and Program Settings)

One cap for every backend. None of them can be asked to do it: DXMT ignores its own setting,
D3DMetal 4.0's `D3DM_MAX_FPS` belongs to its windowless render-to-file mode, and both present at the
display rate whatever sync interval a game passes. What they share, with MoltenVK under DXVK and
vkd3d, is Metal: every frame starts with `-[CAMetalLayer nextDrawable]`. `libsangriafps.dylib`, built
from `Whisky/FrameLimiter/sangria_fps.c` by the app target's *Build Frame Limiter* phase (x86_64, to
match Wine) into Resources, paces that call. A capped launch sets `DYLD_INSERT_LIBRARIES` to it and
`SANGRIA_MAX_FPS` to the rate; an uncapped one sets neither. Wine's binaries are unsigned x86_64, so
dyld honours the variable. The limiter hooks only once QuartzCore is loaded, so wineserver and other
non-graphics processes are untouched.

The bottle picker offers Off and the factors of the display's refresh rate. A program's own limit
(Program Settings → Frame Rate Limit) replaces the bottle's; Off there runs it uncapped.

## DXMT settings (bottle → Config → Graphics)

Written to `<bottle>/dxmt.conf` on every DXMT launch and passed as `DXMT_CONFIG_FILE=Z:/…`:

- **Frame rate limit**: no longer offered here. DXMT 0.80 reads `d3d11.preferredMaxFrameRate` but
  doesn't enforce it (still 120 fps with a 60 cap on the v4.6.4-beta.1 engine); the bottle-wide
  Frame rate limit below works on DXMT.
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

**Graphics API check**: launching a program that imports `d3d12.dll` on DXMT or DXVK stops with
*"Direct3D 12 isn't supported by DXMT yet"*. Both disable `d3d12`, so such a program could not even
load. The options are **Use D3DMetal for This Program** when D3DMetal is installed, otherwise **Use
WineD3D for This Program** (vkd3d), plus **Launch Anyway** and **Always Launch This Program Anyway**.
Launches from other places (library, pins, Run…) show the same message as an error toast. On WineD3D a
Direct3D 12 program gets a caution instead (vkd3d is slower and less complete than D3DMetal, and any
Direct3D 10/11 it also uses won't start there). A program that only ships the Agility SDK gets a
caution on DXMT and DXVK naming the engine switches that force Direct3D 11 (`-dx11` for Unreal,
`-force-d3d11` for Unity). Detection reads import tables, so engines that load Direct3D at runtime
(most Unreal and Unity titles) show "Not detected" and are not checked.

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

- **D3DMetal works with GPTK 4.0b2 on engine v4.6.4-beta.1.** Stock runtime 3.1.1 is not
  GPTK-capable, so this machine runs upstream's prerelease winecx engine (wine-11.16), installed by
  hand; 3.1.1 is kept at `~/Libraries-3.1.1-backup`. GPTK 3.0 does not work on it (device and queue,
  then a crash creating the swapchain: it hooks Wine's mac driver through an older interface), so the
  imported payload is Apple's GPTK 4.0 beta 2.
- **The runtime's DXGI interposer is not installed.** The engine ships `dxgishim.dll` to fix the
  driver version D3DMetal reports (-1, which Helldivers 2 refuses), but it loads Apple's DXGI only on
  the first DXGI call, and Apple's D3D11/D3D12 need it loaded already: every Direct3D 11 program on
  D3DMetal, and every Direct3D 12 program that created its device before touching DXGI, jumped to
  address 0. Deploy now installs only the D3D12 video-processor interposer and takes out a DXGI one an
  earlier deploy left behind.
- **Deploying or removing D3DMetal doesn't reach existing bottles.** Wine copies its builtins into each
  prefix's `system32` when the prefix is updated, and those copies are what loads afterwards. A bottle
  updated while D3DMetal was deployed keeps Apple's DLLs after removal (vkd3d then crashed calling into
  them), and a bottle updated before a deploy would keep Wine's. Run `wineboot -u` in the bottle after
  either change. The app doesn't do this yet.
- **32-bit Direct3D 12**: the GPTK payload carries 32-bit D3DMetal files, but deployment only fills
  the 64-bit directories. The runtime ships 32-bit vkd3d, which was not tested.
- **Direct3D 9** renders through WineD3D on every backend with this runtime (no DXVK `d3d9.dll`, and
  DXMT and D3DMetal start at Direct3D 10).
- **DXMT frame rate limit** is not enforced by DXMT 0.80 here (see above).

## Verification

See [WhiskyDX-Verification.md](WhiskyDX-Verification.md).

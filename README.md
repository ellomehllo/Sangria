<div align="center">

  # Sangria 🍷
  *A personal Wine wrapper for Apple Silicon, with DXMT first*

</div>

Sangria is a personal, non-commercial fork of the [frankea/Whisky](https://github.com/frankea/Whisky)
community fork of [Whisky](https://github.com/whisky-app/whisky), licensed under GPL-3.0. It runs
Windows games and apps on Apple Silicon Macs through Wine. Its focus is the graphics backend: **DXMT is
the default**, D3DMetal and DXVK stay as equal alternatives, and the app shows which backend actually
ran instead of assuming.

> Sangria is not affiliated with the Whisky projects, CodeWeavers, Apple or IO Interactive. It does not
> auto-update and does not send telemetry.

## Highlights

- **DXMT by default.** New bottles start on DXMT (Direct3D 10/11 straight to Metal). Recommended picks
  per launch: DXMT for Direct3D 10/11, D3DMetal for Direct3D 12 when installed, DXVK for launchers such
  as Steam. The reason is recorded with every run.
- **Per-bottle DXMT settings:** frame-rate limit, MetalFX upscaling and extra options, written to a
  generated `dxmt.conf` with a live preview.
- **Knows what really ran.** Each program page shows the detected graphics API, the backend the next
  launch will use and why, and the backend the last run used, checked against which translation layer
  actually wrote logs.
- **Graphics debugging:** DXMT/DXVK log viewer, Metal API and shader validation, one-click frame capture,
  and FPS measured with Apple's Metal HUD on any backend.
- **Honest failures:** Direct3D 12 on a backend that can't run it stops before launch with a clear
  message instead of a crash.
- **Compatibility Notes:** a personal database of what you tested, on which backend, how it ran and at
  what FPS, with CSV export.
- **Fixes over upstream:** switching DXMT → DXVK no longer breaks Direct3D 11; run logs keep the
  program's own output.

## Updates coming

Planned next, roughly in order:

- [ ] **Real-game testing.** Ghost Recon Wildlands (story mode, DirectX 11) first, recorded in
      Compatibility Notes.
- [ ] **Launcher on DXVK, game on DXMT.** Games started by Steam or Ubisoft Connect currently inherit the
      launcher's backend. Placing DXMT beside the game's own executable lets each run on its best backend.
- [ ] **DirectX 12 through D3DMetal**, once a Wine runtime with Game Porting Toolkit support is
      available. Today's runtime (3.1.1) can import D3DMetal but not run it.
- [ ] **Isolation without `Z:`.** Move DXMT's config and log paths inside each bottle, so a bottle's
      access to the whole Mac can be switched off without losing features.
- [ ] **Updates from this repository.** In-app updates from Sangria's own GitHub releases, signed with
      Sangria's own key.
- [ ] **Full rebrand.** A Sangria app icon, and "Sangria" throughout the app's text.
- [ ] **Newer DXMT.** Evaluate releases after 0.80, including frame pacing, which 0.80 doesn't enforce on
      macOS 26. Note that DXMT 1.0 and later are LGPL.

## Building

```sh
brew install swiftlint
xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Whisky.app
```

Or open `Whisky.xcodeproj` in Xcode and press Run. The source keeps upstream's `Whisky` names, so the
built bundle is `Whisky.app`, and it shows up as **Sangria**. On first launch it downloads the Wine
runtime (about 330 MB, SHA-256 verified).

## Documentation

- **[Sangria guide](docs/WhiskyDX.md):** backends, DXMT settings, program pages, limitations
- **[Verification](docs/WhiskyDX-Verification.md):** how it was tested, and the results
- **[Changelog](CHANGELOG.md)**
- **[Runtime dependencies](docs/DEPENDENCIES.md):** the bundled Wine, DXVK, DXMT and D3DMetal versions

## License

GPL-3.0, like Whisky. See [LICENSE](LICENSE). DXMT 0.80 is MIT-licensed, and its license ships in the
runtime at `Libraries/DXMT/LICENSE`.

## Credits & Acknowledgments

Sangria is built on [Whisky](https://github.com/whisky-app/whisky) by Isaac Marovitz and the
[frankea/Whisky](https://github.com/frankea/Whisky) community fork, and on the work of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [DXMT](https://github.com/3Shain/dxmt) by 3Shain
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, Nat Brown, and [Isaac Marovitz](https://github.com/IsaacMarovitz) (original author) for their support and contributions!

---

<table>
  <tr>
    <td>
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="./images/cw-dark.png">
          <img src="./images/cw-light.png" width="500">
        </picture>
    </td>
    <td>
        Whisky, and so Sangria, doesn't exist without CrossOver. If you want a fully-supported commercial Wine experience on macOS, check out <a href="https://www.codeweavers.com/crossover">CrossOver</a> from CodeWeavers. (This fork has no affiliate arrangement and receives nothing from CrossOver sales.)
    </td>
  </tr>
</table>

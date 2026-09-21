# Recon: simplifying Sangria for casual gamers

Written before any code changed, on branch `simple-ui` (cut from `sangria` at
`c4996f15`).

## Stack

| | |
|---|---|
| Language | Swift 6 (WhiskyKit is in Swift 6 language mode; the app target is Swift 5 mode) |
| UI | SwiftUI + AppKit, macOS 26 (Tahoe) deployment |
| Project | `Whisky.xcodeproj`, targets `Whisky`, `WhiskyCmd`, `WhiskyThumbnail`, `WhiskyUITests` |
| Local package | `WhiskyKit/` (all the non-UI logic) |
| Lint | SwiftLint runs as a build phase with `--strict`, so a lint warning fails the app build |

Build: `xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Debug -destination 'platform=macOS' build`

Tests: `swift test` from `WhiskyKit/`. UI tests exist (`WhiskyUITests`) and run
against a launch argument `-WhiskyUITestMode`.

### Baseline, recorded before changing anything

- Build: **BUILD SUCCEEDED**
- Tests: **346 tests in 46 suites passed**

## Where things are today

### Bottles

`BottleVM.shared` holds `[Bottle]`; `Bottle` is a `@MainActor ObservableObject`
wrapping a Wine prefix directory. Settings live in `Metadata.plist` inside the
prefix and are modelled by `BottleSettings` (a big `Codable` struct of nested
config structs), saved automatically on `didSet`.

**This machine has exactly one bottle**, `34045495-73FF-4D33-A145-55C4D8FB2997`,
named "Games XO", at

```
~/Library/Containers/local.bluevsh.WhiskyDX/Bottles/34045495-73FF-4D33-A145-55C4D8FB2997
```

### The real path behind `C:\Games`

```
~/Library/Containers/local.bluevsh.WhiskyDX/Bottles/34045495-73FF-4D33-A145-55C4D8FB2997/drive_c/Games
```

It currently holds `Euro Truck Simulator Gold`, `Metro Exodus` and `Resident`.
In general the Games root is `<bottle>/drive_c/Games`, which is also what Wine
maps to `C:\Games` — `dosdevices/c:` is a symlink to `drive_c`, so the two are
the same directory and no translation table is needed beyond swapping the
prefix and the separators.

### How a game is launched today

Three entry points, all converging on `Wine.runProgram`:

1. `LibraryModel.launchProgram(at:in:)` → `Program.launchWithUserMode(useTerminal:)`
   → `Wine.runProgram(...)`. This is the good path: it picks up the program's
   own overrides and settings, records the run log, and classifies crashes.
   Shift-click diverts to `runInTerminal()`.
2. `BottleActionBar`'s "Run Program…" → `NSOpenPanel` → `Wine.runProgram` /
   `Wine.runBatchFile` directly.
3. `ContentView`'s `.onOpenURL` and `.dropDestination` → `FileOpenView` sheet.

### How shortcuts/pins are stored today

`BottleSettings.info.pins: [PinnedProgram]`, where `PinnedProgram` is
`{ name: String, url: URL?, removable: Bool }` — an **absolute** URL into the
prefix. `Program.pinned`'s setter writes that list. `BottleInfo.unpinnedPrograms`
(added yesterday) records refusals so the Start Menu scan cannot re-pin them.

The library merges pins with Steam entries via `LibraryCatalogue.merge`.

### Every UI entry point that exposes Wine internals

| Where | What it exposes |
|---|---|
| Sidebar, "Bottles" section | bottle list, per-bottle context menu, rename/delete |
| Toolbar `+` | Create Bottle sheet |
| `ContentView` toolbar refresh | harmless |
| `BottleActionBar` | Open C: Drive, **Terminal**, **Winetricks**, Run Program… |
| `BottleView` | quick config panel, All Settings, Running Processes, Game Configurations, Duplicate Bottle |
| `ConfigView` and its ~15 sections | DLL overrides, DXVK, DXMT, Metal, wine version, resolution… |
| `ProgramsView` / `ProgramView` | per-program overrides, run with options, force DirectX version |
| Menu bar: File | Open Bottle…, Migrate from the Original Whisky… |
| Menu bar: File (after import/export) | Open Logs, Kill Bottles, Clear Shader Caches |
| Menu bar: Help | Run Diagnostics…, Troubleshoot… |
| Menu bar: Window | Compatibility Notes |
| `Settings` scene (⌘,) | terminal picker, default bottle location, GPTK section |
| `WhiskyMenuBarView` | menu-bar extra listing bottles |
| Drag and drop onto the window | opens the run-this-file sheet for any `.exe`/`.msi`/`.bat`/… |
| `.onOpenURL` | `whisky://` quick launch |

The word "Run" appears in `button.run` ("Run"), `button.runProgram`
("Run Program…"), `run.title` ("Run \"%@\""), `library.card.neverRun`
("Never run"), plus diagnostics strings ("Run Diagnostics…").

## Implementation plan

Everything below is additive or a gate; nothing existing is deleted.

1. **`AppSettings`** — one `ObservableObject` over `UserDefaults`, injected into
   every scene, holding the new app-wide settings and `developerMode`. Live
   updates come free from `@Published`/`objectWillChange`.
2. **`GamesRoot`** (WhiskyKit) — owns the real Games directory, the `C:\Games\…`
   display mapping, and the single `resolve(_:)` funnel that canonicalizes,
   resolves symlinks and refuses anything outside the root. Every path the
   browser produces goes through it. Tests first: `..`, absolute paths, symlink
   escape, unicode, spaces.
3. **Bottle role** — `BottleInfo.role` (`main` / `compatibility` / `unset`),
   plus `MainBottle.resolve(from:)` which prefers an explicit `.main`, then the
   bottle that has a `drive_c/Games`, then the first available one. No bottle is
   created, moved, merged or deleted.
4. **Relative shortcuts** — add `relativePath: String?` to `PinnedProgram`,
   filled in when the target is under the Games root, and resolve through it
   when present. The absolute `url` stays for pins outside Games and for
   backwards compatibility, so old bottles keep working and a downgrade loses
   nothing.
5. **Sidebar** — replace the `URL?` selection with a `SidebarItem` enum
   (`library` / `games` / `settings` / `bottle(URL)`), showing only the first
   three unless `developerMode`.
6. **Games browser** — a new view over `GamesRoot`: breadcrumb starting at
   "Games", no way up from the root, New Folder, Install a Game, and a
   context menu that differs for `.exe` and everything else.
7. **Play and Install** — reuse `Program.launchWithUserMode` and
   `Wine.runProgram`; nothing in the launch path itself changes.
8. **Settings pane** — General / Display / Performance / Storage / Advanced,
   with the Wine-facing rows (terminal, bottle location, GPTK) moved under
   Developer Mode.
9. **Gate the rest** — menus, keyboard shortcuts, drag-and-drop, the menu-bar
   extra, and `FileOpenView` all check `developerMode`.

Each slice: build, test, verify, log in `DEBUG_LOG.md`, commit.

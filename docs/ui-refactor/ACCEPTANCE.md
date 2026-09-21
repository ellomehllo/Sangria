# Acceptance checklist

Branch `simple-ui`. Evidence for each item, or a plain statement that there
isn't any.

| | Item | Evidence |
|---|---|---|
| ✅ | App builds and all tests pass | `xcodebuild … build` → **BUILD SUCCEEDED**; `swift test` in `WhiskyKit/` → **406 tests in 50 suites passed** (baseline was 346) |
| ✅ | Normal mode: sidebar shows only Library, Games, Settings | Screenshot: sidebar has exactly those three rows, no Bottles section |
| ✅ | "Run", bottle, winetricks, terminal appear nowhere in normal mode | Every localized key reachable from a normal-mode view audited (22 hits, all either behind Developer Mode or reworded); screenshots of all three panes; `library.card.neverRun` now reads "Never played". **One deliberate exception:** the Advanced section's warning names all three words, which the requirements ask for. |
| ✅ | Library cards use "Play" | Screenshot of the card context menu: **Play / Rename / Remove from Library** |
| ✅ | Existing shortcuts survived migration | All three of this machine's real pins now carry a relative path and still resolve: `RE → Resident/RESIDENT EVIL 2 DX12/re2.exe`, `MetroExodus → Metro Exodus/MetroExodus.exe`, `Truck Simulator → Euro Truck Simulator Gold/game.exe` |
| ✅ | File browser cannot leave the Games root by any route | 39 tests in `GamesRootTests` + `GamesBrowsingTests`, against a real directory tree with real symlinks: `..` in URLs and in stored relative paths, absolute paths, a Windows drive letter posing as a folder name, a symlink to a file outside, a symlink to a folder outside, a sibling folder whose name merely starts with the root's, unicode names in four scripts, names with spaces. Rename and New Folder are covered too, and each refusal asserts the file on disk is unchanged. |
| ✅ | New Folder works and the user can navigate into the new folder | `newFolderIsReachable`, `newFolder` (creates, lists, breadcrumbs into it). Navigation into an existing folder confirmed live — screenshot shows `C:\Games\Euro Truck Simulator Gold` with breadcrumb `‹ Games › Euro Truck Simulator Gold` |
| ⚠️ | Right-click on a .exe offers Play, Install, Add to Library | **Code, not a screenshot.** The equivalent menu on a library card was captured live, which proves `contextMenu` works; I ran out of safe ways to capture the browser's menu (see Blocker). Covered by a UI test that compiles but has not run. |
| ✅ | Add to Library creates a shortcut without moving the file | `GamesBrowserModel.addToLibrary` appends a `PinnedProgram` and touches nothing else; `RelativeShortcutTests` covers the pin it creates. No file API is called on that path. |
| ⚠️ | Install runs a setup from the Games folder | **Not exercised end to end** — I have no installer to run and would not install software on this machine without asking. The picker refuses anything resolving outside the root (`GamesRoot.resolve`), and the code path is the same `Wine.runProgram` the old Run Program… button used. |
| ✅ | Settings persist across restarts | `developerMode` written to `local.bluevsh.WhiskyDX` by the switch and read back after a relaunch: toggling it on made the Bottles section and the bottle screen appear, toggling it off removed them, and `defaults read` tracked both |
| ✅ | Developer Mode ON reveals all previous features; OFF hides them again live | Screenshots of both states, no restart between them: ON showed the Bottles section, the bottle screen with Open C: Drive / Terminal / Winetricks / Run Program…, and the + toolbar button; OFF showed three sidebar rows and no + button |
| ✅ | No user game files were moved or deleted | `drive_c/Games` still holds Euro Truck Simulator Gold, Metro Exodus and Resident; Euro Truck still has its 33 entries. Nothing in this change calls a destructive file API except `GamesRoot.moveToTrash`, which is only reachable from the browser's own menu and refuses the root. |
| ✅ | Regression: Play still launches a game exactly as before | Euro Truck Simulator launched and drew its loading screen, via `whisky://launch?pin=Truck Simulator` → `Program.launchWithUserMode` — the same call the Play button makes. `git diff sangria..HEAD` touches **no** file in `WhiskyKit/Wine/`, nor `LibraryModel.swift`, `Program.swift` or `Program+Extensions.swift`. All Wine processes closed afterwards. |

## Blocker: UI automation is not authorized on this machine

`xcodebuild test` fails with:

```
The test runner failed to initialize for UI testing.
(Underlying Error: Timed out while enabling automation mode.)
```

macOS then shows **"XCTest is trying to Enable UI Automation — enter the
password for the user bluevsh"**. I cancelled that prompt rather than typing
anything into it. Until it is answered once, no XCUITest can run here.

`WhiskyUITests/CasualModeUITests.swift` encodes most of this checklist and
**compiles** (`build-for-testing` → TEST BUILD SUCCEEDED), but has not been
run. To run it:

```bash
xcodebuild test -project Whisky.xcodeproj -scheme Whisky -destination 'platform=macOS' -only-testing:WhiskyUITests/CasualModeUITests
```

## Manual checklist for the two unverified items

1. **Right-click a .exe in Games.** Open Games → Euro Truck Simulator Gold →
   right-click `game.exe`. Expect **Play**, **Install**, **Add to Library**,
   then Rename / Show in Finder / Move to Trash. Choose Add to Library, go back
   to Library, and check the card appeared. Right-click `game.exe` again: the
   third item should now read **Already in Library** and be greyed out.
2. **Install a game.** Put any setup `.exe` or `.msi` inside `C:\Games`, then
   use the download button in the Games toolbar (or right-click the file →
   Install). Expect the installer to run. When it exits, if it left new
   executables under `C:\Games`, a sheet should offer to add them to the
   Library with everything pre-ticked.

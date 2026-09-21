# Debug log: casual-gamer UI

One entry per slice. What changed, what failed, why, and how it was fixed.

## Slice 0 — baseline

Branch `simple-ui` cut from `sangria` at `c4996f15`.

- `xcodebuild … -scheme Whisky -configuration Debug build` → **BUILD SUCCEEDED**
- `swift test` in `WhiskyKit/` → **346 tests in 46 suites passed**

Nothing failed. Recorded so later regressions have something to be measured
against.

## Slice 1 — `GamesRoot`, the path-safety funnel

Added `WhiskyKit/Sources/WhiskyKit/Games/GamesRoot.swift` and 22 tests in
`GamesRootTests.swift`, against a real temporary directory tree with real
symlinks — a containment check that never meets a symlink has not been tested.

**Failed first:** three tests comparing a resolved URL to the URL they had just
created. `resolvingSymlinksInPath()` marks a path that exists *and is a
directory* with a trailing slash and leaves one that does not exist without it,
so the same folder compared unequal to itself depending on whether it had been
created yet. Containment was never wrong — only equality was — but a type whose
values do not compare equal to themselves is a trap for every caller after this
one.

**Fixed** by rebuilding every canonical URL from the resolved path string with
`directoryHint: .notDirectory`, so there is one spelling per file whatever its
state on disk.

`swift test --filter GamesRootTests` → **22 tests passed**. SwiftLint clean.

## Slice 2 — a bottle role, and choosing the main bottle

`BottleInfo.role` (`unset` / `main` / `compatibility`) with a lenient decode, and
`MainBottleResolver`, a pure function over `BottleCandidate` facts: an explicit
`.main` first, then whichever bottle already holds `drive_c/Games`, then
whatever is left, and `nil` when there is nothing available. Ties sort by path
so the answer does not depend on registry order.

`compatibility` is a reserved case with nothing that assigns it, as asked —
room for a second prefix later, no feature built now.

Nothing failed. 10 tests.

## Slice 3 — shortcuts that survive a move

`PinnedProgram.relativePath`, filled in when the target is under the Games root,
plus `resolvedURL(gamesRoot:)` which prefers it and falls back to the absolute
URL. `BottleSettings.migratePinsToRelativePaths(gamesRoot:)` is additive only:
it writes the new field and touches nothing else, so no pin is dropped,
reordered or rewritten, and an older build that reads only `url` still works.

**Failed first, twice:**

1. `#expect(settings.migratePinsToRelativePaths(…))` — the macro captures its
   operand immutably, so a mutating method cannot be called inside one. Hoisted
   the call out and expected the result.
2. The test fixture is a noncopyable struct, and its `init` did throwing work
   *after* the last stored property was assigned: "conditional initialization or
   destruction of noncopyable types is not supported". Moved every `try` ahead
   of the first assignment.

`swift test` → **389 tests in 49 suites passed** (was 346).

## Slice 4 — the app-wide settings store

`AppSettings` (one `ObservableObject` over `UserDefaults`) and `GameDefaults`
(the thin layer that writes those switches onto the main bottle).

`@AppStorage` was rejected for this: it is a `DynamicProperty` and only works
inside a `View`, and Developer Mode has to be readable from the sidebar, the
menus and the launch path alike. One observable object gives every reader live
updates without a restart, which is what "toggling updates the UI live" needs.

Booleans are read with `object(forKey:) as? Bool ?? fallback` rather than
`bool(forKey:)`, because the latter cannot tell "off" from "never set" and
three of these default to on.

**Failed first:** `WineRegistry` is internal to WhiskyKit; the public spelling
is `Wine.changeRetinaMode`. `Logger.wineKit` also needed `import os.log`.
Fixed both.

Build → **BUILD SUCCEEDED**. No behaviour change yet: nothing reads these.

## Slice 5 — the sidebar, the Games browser, and the Settings pane

The big one. `SidebarItem` replaces the old `URL?` selection (an optional
cannot hold both "no bottle" and "the Games folder"), `GamesBrowserView` and
`GamesBrowserModel` give `C:\Games` a front end, `GameSettingsView` becomes the
one settings surface for both the sidebar row and ⌘,, and the Wine-facing rows
move into `DeveloperSettingsSection`.

**Failed, and what it taught:**

1. `WineRegistry` is internal to WhiskyKit — the public spelling is
   `Wine.changeRetinaMode`.
2. **The whole project stopped parsing**: `xcodebuild: error: Unable to read
   project`. Adding `BottleVM+MainBottle.swift` wrote `path =
   BottleVM+MainBottle.swift;` unquoted, and a pbxproj only leaves a value bare
   when it matches `[A-Za-z0-9_./]`. Xcode itself writes
   `path = "Bottle+Extensions.swift";`. Quoted it and taught the helper script
   the rule.
3. `mainBottleURL` is `private(set)`, so an extension *in another file* cannot
   assign it. Rather than widening the setter, `chosenMainBottleURL()` now
   returns a value and `loadBottles()` — the one place it can change — assigns
   it.
4. SwiftLint `--strict` failed the build twice on `BottleVM.swift`: 430 lines
   (limit 400) and a 263-line type body (limit 250). Both were fixed by
   splitting, not by silencing: the main-bottle choice went to
   `BottleVM+MainBottle.swift` and the failure-report builder to
   `BottleVM+CreationDiagnostics.swift`. Neither reads state the view model
   owns.

Wording swept for the banned words: `library.card.neverRun` now reads "Never
played", `library.card.hint` "Plays this game", the empty state points at Games
instead of at creating a bottle, and search says "games" not "programs". The
"Bottle" sort option is filtered out unless Developer Mode is on.

Build → **BUILD SUCCEEDED**. `swift test` → **406 tests in 50 suites passed**.

## Slice 6 — the vocabulary sweep, and the bottle nobody asks for

Audited every localized key reachable from a normal-mode view for the words
bottle / winetricks / terminal / wine. 22 hits. Most were already behind
Developer Mode; four were not:

- `cleanup.zombies.toast` ("leftover Wine processes") → "leftover game
  processes". Fires at startup in any mode.
- `setup.uninstall.confirm.body` and `setup.telemetry.consent.help`, both in
  the first-run setup flow, reworded off "bottles" and "first bottle created".
- The corrupt-registry and orphaned-bottle alerts fire at startup regardless of
  mode and ask a question no player can answer. In normal mode the orphan
  recovery now just happens — re-importing adds back paths that already exist
  and changes nothing on disk — and neither alert is shown.

`settings.developerMode.warning` still names all three words. That is required:
Advanced is meant to be the only place that does.

**A gap the requirements imply but do not state:** normal mode has no way to
create a bottle, and a fresh install has none — so there would be nowhere to
put a game and no way to ask for one without saying the word. `BottleVM
.ensureMainBottleExists()` makes exactly one, named "Games", once the runtime
is installed. It creates nothing when a bottle already exists, and is guarded
against being started twice by two passes of the same startup.

`FileOpenView` (Finder's "Open With", and the `whisky://` scheme) asked which
bottle to use. In normal mode it now runs in the main bottle and dismisses
without ever being seen.

Build → **BUILD SUCCEEDED**.

## Slice 7 — verification, and what could not be verified

**A folder row now opens on one click.** Found while driving the UI: a folder
row draws a chevron, and a disclosure arrow that does nothing until you
double-click it is a lie about what the row is. Files keep the double-click —
starting a game takes over the screen for an hour and should not happen by
accident.

**The blocker.** `xcodebuild test` cannot run here: the runner fails with
"Timed out while enabling automation mode", and macOS puts up a password
prompt — *"XCTest is trying to Enable UI Automation"* — that only the user can
answer. I cancelled it rather than typing anything into it.

Screenshot-driven verification worked instead, with two lessons worth keeping:

- The process is named **Whisky**, not Sangria (the bundle's display name
  differs from its executable). `tell process "Sangria"` fails with "Invalid
  index", which looks exactly like a flaky accessibility bridge and is not.
- The window only appears in the accessibility tree while the app is
  **frontmost**. Two of my clicks went into other applications' windows before
  I added a guard that refuses to click or screenshot unless Sangria is
  genuinely in front. Anything that injects input needs that check first.

SwiftUI's `.accessibilityIdentifier` is not exposed through the System Events
bridge on macOS 26 — 78 elements, not one identifier — so precise element
targeting really does need XCUITest.

**The launch regression was checked without the GUI**, through the app's own
`whisky://launch?pin=…` scheme, which calls the same
`Program.launchWithUserMode` the Play button does. Euro Truck Simulator
started and drew its loading screen; every Wine process was closed afterwards.

`swift test` → **406 tests in 50 suites passed**. Build → **BUILD SUCCEEDED**.
`build-for-testing` → **TEST BUILD SUCCEEDED** (the UI tests compile; they have
not been run).

## Slice 8 — windows, the escaping pointer, and ⌥⌘C

Three requests, and one of them found a defect from slice 4.

**"Start games fullscreen" was a no-op.** It wrote
`bottle.settings.virtualDesktopEnabled`, and nothing read it: `Wine.runProgram`
only consulted the *per-program* override, and the bottle-level flag was
applied solely by the Developer-Mode resolution section. The setting persisted
and did nothing. `GameDefaults.seedIfNeeded` was dead code too — written in
slice 4, never called.

Both fixed. The launch now asks `Wine.wantsOwnWindow(override:bottleDefault:)`,
which is a nil-coalesce rather than an `||` so a game told explicitly *not* to
be windowed is not windowed by the bottle's default. `GameDefaults.synchronise`
seeds then applies, once, at startup.

Also found: `ResolutionPreset.matchDisplay` returned a hardcoded `1920x1080` —
the one answer "Match Mac Display" promises not to give.

**The double-cursor bug.** `strings` on the Wine mac driver shows two clipping
strategies — `WineConfinementClipCursorHandler` and
`WineEventTapClipCursorHandler` — and a registry switch between them,
`HKCU\Software\Wine\Mac Driver\UseConfinementCursorClipping`. Confinement is
the default and only holds while Wine's window is key and active; the event tap
does not care, but needs Accessibility permission. Exposed as a setting, with
an in-line notice when the permission is missing, because a `CGEventTap`
without it creates nothing and reports nothing.

**⌥⌘C** uses Carbon's `RegisterEventHotKey` — `NSEvent`'s global monitor needs
Accessibility and this has to work for someone who has granted nothing. It
brings Sangria forward, and Wine's driver releases the pointer on
`APP_DEACTIVATED`.

It is claimed only while a game runs. First attempt hooked `GameLauncher.play`,
which was wrong: there are five launch sites and `QuickLaunch` (the `whisky://`
scheme and the Dock menu) is not one of them. Moved to a
`.wineProcessesChanged` notification from `ProcessRegistry`, which every launch
path reaches. `LibraryModel` now goes through `GameLauncher` as well — it had
been skipping the launcher fixes the other paths applied.

**Verified:** the bottle flag flips to `true` at startup; RE2's launch log
shows `explorer /desktop=re2.exe,1470x956`; the window is a real Mac window
titled "RESIDENT EVIL 2"; `"UseConfinementCursorClipping"="n"` lands in
`user.reg` (written and then removed again). 412 tests, build clean.

**Not verified:** that ⌥⌘C fires inside a running game, and that forcing the
event tap actually cures the escaping pointer — that is a mechanism with
evidence behind it, not a demonstrated fix.

**A limitation with evidence.** A virtual-desktop window's green button is
*disabled* (`AXFullScreenButton` greyed), while a plain Wine window's is
enabled — checked against Notepad. So a game in its own window can be closed,
minimised, moved and Mission-Controlled, but not put into native macOS
fullscreen. Filling the screen is the closest equivalent, and the desktop is
already sized to the display.

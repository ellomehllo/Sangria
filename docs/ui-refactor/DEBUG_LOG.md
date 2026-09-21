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

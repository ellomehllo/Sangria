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

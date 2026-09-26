<div align="center">

# Sangria 🍷

**Play Windows games on your Mac.**

*A personal Wine wrapper for Apple Silicon.*

</div>

---

<div align="center">

### ***Message from the founder***

</div>

> ### ***"Try running your fav games from Steam or Epic Games. If you are trying to run a cracked game, make sure it is pre-installed, then transfer the files to your Mac.***
>
> ### ***I have tested Pragmata, all the Resident Evil games, and Truck Simulator. I'm still testing more games on it — if something comes up, let me know and I'll fix it."***

---

## What is this?

Sangria runs Windows games on Apple Silicon Macs (M1 and newer). It uses **Wine**, which
translates what a Windows game asks for into something macOS understands — so the game thinks
it's on Windows, and your Mac never has to pretend.

You do not need to know what any of that means to use it.

**What you need**

- A Mac with Apple Silicon — M1, M2, M3, M4 or newer. (Check: Apple menu → About This Mac.
  If it says "Intel", Sangria will not work.)
- macOS 15 (Sequoia) or newer.
- About 2 GB of free space for Sangria itself, plus whatever your games need.

---

## Installing Sangria

There is no ready-made download yet, so you build it once on your own Mac. **You do not need to
know how to code, and you do not need to use the Terminal.** It takes about fifteen minutes,
most of which is waiting.

### Step 1 — Get Xcode

Xcode is Apple's free app for building Mac apps. Open the **App Store**, search for **Xcode**,
and install it. It's a big download (around 10 GB), so start it and go make a coffee.

Once it's installed, **open Xcode once** and accept the licence agreement it shows you. It may
ask for your password to finish setting itself up. That's normal — that's Apple's installer, not
Sangria.

### Step 2 — Download Sangria

On this page, click the green **`Code`** button near the top, then click **Download ZIP**.

Find the file in your **Downloads** folder and double-click it to unzip it. You'll get a folder
called `Sangria-sangria` or similar. Move that folder somewhere sensible — your Documents folder
is fine.

> You may have seen "clone the repository" elsewhere. That's just another way of downloading the
> same thing, and you don't need it. Download ZIP is fine.

### Step 3 — Open it in Xcode

Inside that folder, double-click **`Whisky.xcodeproj`**. Xcode will open.

> **Why does it say Whisky?** Sangria is built on top of an open-source project called Whisky.
> The internal filenames still say Whisky; the app you get is Sangria. Nothing is wrong.

### Step 4 — Press Play

At the top-left of the Xcode window there's a **▶ Play** button. Click it.

Xcode will spend a few minutes building. When it finishes, **Sangria opens by itself**. That's it.

### Step 5 — Put it in your Applications folder

So you can open it normally from now on:

1. In Xcode's left sidebar, scroll to the bottom and open the **Products** folder.
2. Right-click **`Whisky.app`** → **Show in Finder**.
3. Drag it into your **Applications** folder, then rename it to **Sangria** if you like.

From now on, just open it from Applications or Spotlight.

### First launch

The first time Sangria opens, it downloads the Wine runtime — about 330 MB. Let it finish. After
that it works offline.

---

## Playing your first game

1. Open Sangria. You'll see three things in the sidebar: **Library**, **Games** and **Settings**.
2. Click **Games**. This is a folder on your Mac that your games live in — Sangria shows it as
   `C:\Games`, because that's what the game sees.
3. Put your game's folder in there. The easiest way: click **Reveal in Finder** in
   **Settings → Storage**, then drag the game's folder in.
4. Back in Sangria, click **Games**, click into your game's folder, and find the file ending in
   **`.exe`** — that's the game itself.
5. **Right-click it → Play.**
6. Right-click it → **Add to Library** to get a poster tile on the Library screen, so next time
   you just press **Play** there.

**Installing a game from a setup file?** Put the installer in the Games folder, then use the
**Install a Game** button in the Games toolbar. When it finishes, Sangria offers to add whatever
it installed to your Library.

---

## If something goes wrong

Games are unpredictable. A few things that fix most problems:

| What you see | Try this |
|---|---|
| Two mouse cursors, or your Mac pointer floating over the game | **Settings → Display → Hold the mouse inside the game.** It needs Accessibility permission — Sangria shows a button that takes you straight to the right place in System Settings. |
| The game has your mouse and you want it back | Press **⌥⌘C** (Option-Command-C). |
| A game runs slowly | **Settings → Performance → MetalFX upscaling.** |
| Your screen goes black when a game starts | **Settings → Display → Wrap games in a Sangria window.** |
| A game won't start at all | Some games simply don't work yet. That's usually the translation layer missing something the game needs, not a setting you got wrong. |

**Developer Mode** (Settings → Advanced) unlocks everything underneath — per-game settings, logs,
the terminal and so on. You don't need it to play games, and turning it on can stop a game working.
Leave it off unless you're comfortable poking around.

---

## ☕ Buying me a coffee

Sangria is free, and it stays free.

What it costs *me* is evenings spent reading Wine debug logs to work out why a twelve-year-old
truck simulator draws a black rectangle where a truck should be. The answer turned out to be one
environment variable. It took a while to find.

If Sangria got one of your games running: **[ko-fi.com/ellomehllo](https://ko-fi.com/ellomehllo)**

*Wine is free. The person translating it runs on caffeine.*

---

## Get in touch

Found a game that doesn't work? Open an
**[issue](https://github.com/ellomehllo/Sangria/issues)** and say which game and what happened.
That's the fastest way to get it looked at.

---

## For developers

<details>
<summary>Building from the command line, and the technical docs</summary>

```sh
brew install swiftlint
xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Whisky.app
```

Tests: `swift test` from `WhiskyKit/`.

The source keeps upstream's `Whisky` names and its bundle id, so bottles and settings carry over
from the fork it came from. The built bundle is `Whisky.app` and displays as Sangria.

**Graphics backends.** D3DMetal handles Direct3D 12, DXMT takes Direct3D 10/11 straight to Metal,
DXVK covers launchers, and Wine's own WineD3D handles Direct3D 9 — nothing else on this stack
translates D3D9, so legacy titles are routed there automatically with `WINED3DMETAL=0`. The app
records which backend actually ran rather than assuming.

- **[Sangria guide](docs/WhiskyDX.md):** backends, DXMT settings, program pages, limitations
- **[Verification](docs/WhiskyDX-Verification.md):** how it was tested, and the results
- **[Changelog](CHANGELOG.md)**
- **[Runtime dependencies](docs/DEPENDENCIES.md):** bundled Wine, DXVK, DXMT and D3DMetal versions

</details>

---

## Honest limitations

- **Games with kernel anti-cheat do not work** — not in Sangria, not in any Wine wrapper. That
  rules out most competitive online games.
- **Some Direct3D 12 games still crash.** The translation layer is Apple's, and when a game asks
  it for something it hasn't implemented, there is nothing Sangria can do about it.
- **No auto-updates.** To update, download the code again and rebuild.
- **No telemetry.** Sangria doesn't phone home.

Sangria is not affiliated with the Whisky projects, CodeWeavers or Apple.

---

## License

GPL-3.0, like Whisky. See [LICENSE](LICENSE). DXMT 0.80 is MIT-licensed, and its license ships in
the runtime at `Libraries/DXMT/LICENSE`.

## Credits & Acknowledgments

Sangria is a fork of [frankea/Whisky](https://github.com/frankea/Whisky), itself a community fork
of [Whisky](https://github.com/whisky-app/whisky) by Isaac Marovitz, and stands on the work of
several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [DXMT](https://github.com/3Shain/dxmt) by 3Shain
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, Nat Brown, and
[Isaac Marovitz](https://github.com/IsaacMarovitz) (original author) for their support and
contributions!

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

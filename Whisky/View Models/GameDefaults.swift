//
//  GameDefaults.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os.log
import WhiskyKit

/// Carries the app-wide switches onto the bottle everything runs in.
///
/// This is the whole of the "thin orchestration layer": it writes existing
/// ``BottleSettings`` properties and calls the existing registry helper.
/// Nothing here decides how a game is launched, which backend it gets, or what
/// DLLs it loads — that stays where it was.
///
/// Write-through happens when the user changes a switch, not on every launch.
/// A player who turns Developer Mode on and sets something in the bottle's own
/// configuration should not find it quietly reverted the next time they press
/// Play.
@MainActor
enum GameDefaults {
    /// Which app-wide settings reach the bottle, and where they land.
    ///
    /// | Setting | Bottle property |
    /// |---|---|
    /// | Show FPS overlay | `metalHud` |
    /// | MetalFX upscaling | `metalFX` |
    /// | Sync optimization | `enhancedSync` (`.msync` / `.none`) |
    /// | Limit background activity | `disableAppNap` |
    /// | Run games in a window | `virtualDesktopEnabled` |
    ///
    /// High-resolution mode and the pointer lock are not here: both are
    /// registry values, so they need ``applyRetinaMode(_:to:)`` and
    /// ``applyPointerLock(_:to:)`` and a running wineserver.
    static func apply(_ settings: AppSettings, to bottle: Bottle) {
        bottle.settings.metalHud = settings.showFPSOverlay
        bottle.settings.metalFX = settings.metalFXUpscaling
        bottle.settings.enhancedSync = settings.syncOptimization ? .msync : .none
        bottle.settings.disableAppNap = settings.limitBackgroundActivity
        // A virtual desktop *is* the windowed mode: the game gets one real Mac
        // window to draw into — title bar, green fullscreen button, ⌘W —
        // instead of changing the display mode out from under everything.
        //
        // This is the bottle's default. A game with its own answer keeps it:
        // `Wine.wantsOwnWindow` only falls back here when a program has stated
        // no preference of its own.
        bottle.settings.virtualDesktopEnabled = settings.windowedMode
    }

    /// How firmly Wine holds the mouse pointer inside a game.
    ///
    /// Also a registry value, and also only written when the user changes it —
    /// it starts a wineserver.
    static func applyPointerLock(_ settings: AppSettings, to bottle: Bottle) async {
        do {
            try await Wine.changeCursorClipping(
                bottle: bottle,
                // The switch is worded for what it does, not for how: "hold the
                // mouse in the game" means give up the default confinement and
                // use the event tap that survives a click.
                useConfinement: !settings.holdMouseInGame
            )
        } catch {
            Logger.wineKit.warning(
                "Could not set the pointer lock: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// High-resolution mode, which lives in the prefix's registry.
    ///
    /// Separate because it starts a wineserver, so it runs only when the user
    /// actually changes it.
    static func applyRetinaMode(_ settings: AppSettings, to bottle: Bottle) async {
        do {
            try await Wine.changeRetinaMode(bottle: bottle, retinaMode: settings.retinaMode)
        } catch {
            Logger.wineKit.warning(
                "Could not set high-resolution mode: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// On a first run, takes the switches' starting positions from the bottle
    /// rather than from the app's defaults.
    ///
    /// Without this, an existing install would open Settings to a set of
    /// toggles that disagree with how its games are actually configured, and
    /// the first change to any unrelated switch would look like it had changed
    /// several.
    ///
    /// Only fills in what has never been written, so it cannot overwrite a
    /// choice the user has already made.
    static func seedIfNeeded(_ settings: AppSettings, from bottle: Bottle, defaults: UserDefaults = .standard) {
        func seed(_ key: String, _ value: Bool, _ assign: (Bool) -> Void) {
            guard defaults.object(forKey: key) == nil else { return }
            assign(value)
        }

        seed(AppSettings.Key.showFPSOverlay, bottle.settings.metalHud) { settings.showFPSOverlay = $0 }
        seed(AppSettings.Key.metalFXUpscaling, bottle.settings.metalFX) { settings.metalFXUpscaling = $0 }
        seed(AppSettings.Key.syncOptimization, bottle.settings.enhancedSync != .none) {
            settings.syncOptimization = $0
        }
        seed(AppSettings.Key.limitBackgroundActivity, bottle.settings.disableAppNap) {
            settings.limitBackgroundActivity = $0
        }
        // `windowedMode` is deliberately not seeded. The bottle flag it maps
        // onto was never read by anything until now, so its value records no
        // decision anybody made — seeding from it would spread a dead default
        // instead of adopting a real setting.
    }

    /// Brings the app's switches and the main bottle into agreement, once, at
    /// startup.
    ///
    /// Seed first, then apply: seeding adopts the bottle's value for anything
    /// the user has never set, so applying afterwards writes back what was
    /// already there and changes nothing. The one setting that does move is
    /// the one seeding skips — which is the point.
    static func synchronise(_ settings: AppSettings, with bottle: Bottle) {
        seedIfNeeded(settings, from: bottle)
        apply(settings, to: bottle)
    }
}

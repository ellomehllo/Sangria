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
    /// One app-wide switch, and the single bottle property it owns.
    ///
    /// Each case writes *only* its own property. Writing the whole set
    /// whenever any one of them changed is what let a value chosen in the
    /// bottle's Graphics, Performance or Resolution section be discarded by
    /// touching an unrelated switch in Settings — the same five properties are
    /// reachable from both places, so a blanket rewrite silently won every
    /// time.
    ///
    /// High-resolution mode and the pointer lock are not here: both are
    /// registry values, so they need ``applyRetinaMode(_:to:)`` and
    /// ``applyPointerLock(_:to:)`` and a running wineserver.
    enum Switch: CaseIterable {
        /// Show FPS overlay → `metalHud`.
        case fpsOverlay
        /// MetalFX upscaling → `metalFX`.
        case metalFX
        /// Sync optimization → `enhancedSync`.
        case sync
        /// Limit background activity → `disableAppNap`.
        case backgroundActivity
        /// Run games in a window → `virtualDesktopEnabled`. A game with its
        /// own answer keeps it: `Wine.wantsOwnWindow` only falls back to the
        /// bottle when a program has stated no preference.
        case windowed

        /// Reads this switch's value out of the app settings.
        @MainActor
        func value(in settings: AppSettings) -> Bool {
            switch self {
            case .fpsOverlay: settings.showFPSOverlay
            case .metalFX: settings.metalFXUpscaling
            case .sync: settings.syncOptimization
            case .backgroundActivity: settings.limitBackgroundActivity
            case .windowed: settings.windowedMode
            }
        }

        /// Writes it onto the bottle, and nothing else.
        @MainActor
        func write(_ isOn: Bool, to bottle: Bottle) {
            switch self {
            case .fpsOverlay: bottle.settings.metalHud = isOn
            case .metalFX: bottle.settings.metalFX = isOn
            case .sync: bottle.settings.enhancedSync = isOn ? .msync : .none
            case .backgroundActivity: bottle.settings.disableAppNap = isOn
            case .windowed: bottle.settings.virtualDesktopEnabled = isOn
            }
        }
    }

    /// Writes one switch through to the bottle.
    static func apply(_ change: Switch, _ isOn: Bool, to bottle: Bottle) {
        change.write(isOn, to: bottle)
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
    /// Seeding adopts the bottle's value for every switch the user has never
    /// set, which is the whole of the job for four of the five. Only
    /// ``Switch/windowed`` is pushed, because seeding deliberately skips it —
    /// the bottle flag it maps onto was dead until recently and records no
    /// decision anybody made.
    ///
    /// Nothing else is written. Pushing the full set here would undo a value
    /// set in the bottle's own configuration screens on the next launch, which
    /// is the startup half of the bug ``apply(_:_:to:)`` fixes on the toggle.
    static func synchronise(_ settings: AppSettings, with bottle: Bottle) {
        seedIfNeeded(settings, from: bottle)
        apply(.windowed, settings.windowedMode, to: bottle)
    }
}

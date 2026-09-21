//
//  AppSettings.swift
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

import AppKit
import SwiftUI
import WhiskyKit

/// How the app looks.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: "settings.theme.system"
        case .light: "settings.theme.light"
        case .dark: "settings.theme.dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Every setting that applies to the whole app, in one observable place.
///
/// These are *app-wide* on purpose: a casual player has one library and wants
/// one set of switches, not a copy per game and another per prefix. Where a
/// switch maps onto something the existing bottle settings already do, it is
/// written through to the main bottle by ``GameDefaults``; where nothing
/// supports it yet, the value is still persisted and the code says so.
///
/// `@AppStorage` is not used here because these have to be readable from
/// non-`View` code (the launch path, the sidebar's gating) and writable from
/// several places at once. One `ObservableObject` over `UserDefaults` gives
/// live updates everywhere without a restart, which is what Developer Mode
/// needs.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: - General

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.theme)
            applyTheme()
        }
    }

    /// Covers both the app and the Wine runtime: one question, because a
    /// casual player does not know there are two things to update.
    @Published var automaticUpdates: Bool {
        didSet {
            defaults.set(automaticUpdates, forKey: Key.automaticUpdates)
            // The existing keys, kept in step so nothing behind them changes.
            defaults.set(automaticUpdates, forKey: "SUEnableAutomaticChecks")
            defaults.set(automaticUpdates, forKey: "checkWhiskyWineUpdates")
        }
    }

    /// Whether closing Sangria stops whatever is still running inside it.
    @Published var quitGamesOnExit: Bool {
        didSet {
            defaults.set(quitGamesOnExit, forKey: Key.quitGamesOnExit)
            defaults.set(quitGamesOnExit, forKey: "killOnTerminate")
        }
    }

    // MARK: - Display

    /// Whether to wrap every game in a Wine desktop window.
    ///
    /// **Off by default, and it stays off until a game asks for it.** It is a
    /// compatibility tool, not the way to get a Mac-like window: it helps an
    /// old title that would otherwise change the display mode out from under
    /// everything, and it hurts a modern one. Resident Evil 2 — Direct3D 12
    /// through D3DMetal — renders nothing but black inside one, while running
    /// perfectly without.
    ///
    /// A game left to manage its own window gets a *better* Mac window than
    /// this produces: a plain Wine window has a working green fullscreen
    /// button, and the desktop window's is disabled.
    @Published var windowedMode: Bool {
        didSet { defaults.set(windowedMode, forKey: Key.windowedMode) }
    }

    /// Whether to use the stronger of Wine's two ways of keeping the pointer
    /// inside a game.
    ///
    /// Off by default because the stronger one needs Accessibility permission,
    /// which is the user's to grant and nobody should be nagged for until the
    /// weaker one has actually failed them.
    @Published var holdMouseInGame: Bool {
        didSet { defaults.set(holdMouseInGame, forKey: Key.holdMouseInGame) }
    }

    @Published var retinaMode: Bool {
        didSet { defaults.set(retinaMode, forKey: Key.retinaMode) }
    }

    @Published var showFPSOverlay: Bool {
        didSet { defaults.set(showFPSOverlay, forKey: Key.showFPSOverlay) }
    }

    // MARK: - Performance

    @Published var metalFXUpscaling: Bool {
        didSet { defaults.set(metalFXUpscaling, forKey: Key.metalFXUpscaling) }
    }

    @Published var syncOptimization: Bool {
        didSet { defaults.set(syncOptimization, forKey: Key.syncOptimization) }
    }

    @Published var limitBackgroundActivity: Bool {
        didSet { defaults.set(limitBackgroundActivity, forKey: Key.limitBackgroundActivity) }
    }

    // MARK: - Advanced

    /// Everything Wine-shaped is behind this, and nothing else in the app
    /// mentions a bottle, a terminal or winetricks while it is off.
    @Published var developerMode: Bool {
        didSet { defaults.set(developerMode, forKey: Key.developerMode) }
    }

    // MARK: - Lifetime

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read straight through, with the app's own defaults where the key has
        // never been written. `object(forKey:)` rather than `bool(forKey:)`
        // because the latter cannot tell "off" from "never set", and three of
        // these default to on.
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        automaticUpdates = defaults.flag(Key.automaticUpdates, default: true)
        quitGamesOnExit = defaults.flag(Key.quitGamesOnExit, default: true)
        // Off unless asked for. Defaulting it on black-screened a Direct3D 12
        // title that had worked for months, so the default follows the
        // evidence rather than the ambition.
        windowedMode = defaults.flag(Key.windowedMode, default: false)
        holdMouseInGame = defaults.flag(Key.holdMouseInGame, default: false)
        retinaMode = defaults.flag(Key.retinaMode, default: false)
        showFPSOverlay = defaults.flag(Key.showFPSOverlay, default: false)
        metalFXUpscaling = defaults.flag(Key.metalFXUpscaling, default: false)
        syncOptimization = defaults.flag(Key.syncOptimization, default: true)
        limitBackgroundActivity = defaults.flag(Key.limitBackgroundActivity, default: false)
        developerMode = defaults.flag(Key.developerMode, default: false)
    }

    /// Applies the stored theme to the running app.
    func applyTheme() {
        NSApp?.appearance = theme.appearance
    }

    enum Key {
        static let theme = "appTheme"
        static let automaticUpdates = "automaticUpdates"
        static let quitGamesOnExit = "quitGamesOnExit"
        static let windowedMode = "runGamesWindowed"
        static let holdMouseInGame = "holdMouseInGame"
        static let retinaMode = "highResolutionMode"
        static let showFPSOverlay = "showFPSOverlay"
        static let metalFXUpscaling = "metalFXUpscaling"
        static let syncOptimization = "syncOptimization"
        static let limitBackgroundActivity = "limitBackgroundActivity"
        static let developerMode = "developerMode"
    }
}

private extension UserDefaults {
    /// A boolean that can tell "never written" from "written false".
    func flag(_ key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }
}

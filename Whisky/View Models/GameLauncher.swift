//
//  GameLauncher.swift
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
import WhiskyKit

/// One way to start a program, for the library and the Games browser alike.
///
/// This adds nothing to how a launch works — it finds or makes the ``Program``
/// and calls the same `launchWithUserMode` the library has always used, so the
/// program's own overrides, its run log and its crash classification all apply
/// exactly as before. It exists so that two screens cannot drift into two
/// different ideas of what Play means.
@MainActor
enum GameLauncher {
    /// The bottle's own `Program` for this executable, or a fresh one.
    ///
    /// The bottle's list comes from a scan that only covers some of the
    /// prefix, so a perfectly good executable the user picked in the browser
    /// may not be in it. Making one on demand is what the programs list does
    /// itself, and it is what gives the launch its per-program settings.
    static func program(for url: URL, in bottle: Bottle) -> Program {
        bottle.programs.first { $0.url == url } ?? Program(url: url, bottle: bottle)
    }

    /// Starts a program and reports how it went.
    ///
    /// - Parameter useTerminal: Opens it in a terminal instead. Capture
    ///   `NSEvent.modifierFlags` at the call site, before any `await`.
    static func play(_ url: URL, in bottle: Bottle, useTerminal: Bool = false) async -> LaunchResult {
        // Same order as every other launch path: detect the launcher and let
        // its fixes be written before anything reads the settings.
        LauncherFixes.detectAndApply(from: url, for: bottle)
        Telemetry.capture(.firstProgramLaunchAttempted)
        // ⌥⌘C, for as long as something is running. Claimed here because a
        // game about to take the mouse pointer is exactly when it has to
        // exist, and released again once every prefix has gone quiet.
        if !useTerminal {
            MouseReleaseHotkey.shared.gameStarted()
        }
        return await program(for: url, in: bottle).launchWithUserMode(useTerminal: useTerminal)
    }
}

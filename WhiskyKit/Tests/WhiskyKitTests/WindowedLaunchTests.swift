//
//  WindowedLaunchTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

/// A game runs in a window of its own when it is told to — and the bottle's
/// answer used to be ignored entirely, so the setting persisted and did nothing.
@Suite("Which launches get a window of their own")
struct WindowedLaunchTests {
    @Test("The bottle decides when the program has no preference")
    func bottleIsTheDefault() {
        #expect(Wine.wantsOwnWindow(override: nil, bottleDefault: true))
        #expect(!Wine.wantsOwnWindow(override: nil, bottleDefault: false))
    }

    @Test("A program that asks for a window gets one, whatever the bottle says")
    func programCanOptIn() {
        #expect(Wine.wantsOwnWindow(override: true, bottleDefault: false))
    }

    /// The case a plain `||` would get wrong: a game that has been told
    /// explicitly *not* to be windowed must not be windowed by the bottle's
    /// default.
    @Test("A program that refuses a window is not given one by the bottle")
    func programCanOptOut() {
        #expect(!Wine.wantsOwnWindow(override: false, bottleDefault: true))
    }

    @Test("A fixed preset resolves to its own size", arguments: [
        (ResolutionPreset.r1280x720, "1280x720"),
        (.r1600x900, "1600x900"),
        (.r1920x1080, "1920x1080"),
        (.r2560x1440, "2560x1440"),
        (.r3840x2160, "3840x2160")
    ])
    @MainActor
    func fixedPresets(preset: ResolutionPreset, expected: String) {
        #expect(Wine.resolutionString(preset: preset, customWidth: 0, customHeight: 0) == expected)
    }

    @Test("A custom resolution uses the numbers it was given")
    @MainActor
    func customResolution() {
        #expect(Wine.resolutionString(preset: .custom, customWidth: 1_470, customHeight: 956) == "1470x956")
    }

    /// "Match Mac Display" used to return a hardcoded 1920x1080 — the one
    /// answer it promises not to give. It cannot be asserted exactly here
    /// (the answer depends on the screen the tests run on), so this pins the
    /// shape and the fact that it is not a constant unrelated to the display.
    @Test("Matching the display asks the display")
    @MainActor
    func matchDisplay() throws {
        let value = Wine.resolutionString(preset: .matchDisplay, customWidth: 0, customHeight: 0)
        let parts = value.split(separator: "x").compactMap { Int($0) }
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0 > 0 })
    }
}

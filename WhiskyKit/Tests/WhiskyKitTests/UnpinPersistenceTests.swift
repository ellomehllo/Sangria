//
//  UnpinPersistenceTests.swift
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

/// Unpinning has to survive the Start Menu scan, which re-pins everything it
/// finds every time a bottle screen opens and after every launch. Euro Truck
/// Simulator has a Start Menu shortcut, so unpinning it appeared to do nothing.
@Suite("An unpin is remembered")
struct UnpinPersistenceTests {
    private let exe = URL(filePath: "/bottle/drive_c/Games/Euro Truck Simulator Gold/game.exe")

    @Test("Unpinning records the program so a later scan leaves it alone")
    func unpinIsRecorded() {
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Truck Simulator", url: exe)]

        settings.pins.removeAll { $0.url == exe }
        settings.unpinnedPrograms.append(exe)

        #expect(settings.pins.isEmpty)
        #expect(settings.unpinnedPrograms.contains(exe))
    }

    @Test("The record round-trips through the bottle's plist")
    func survivesEncoding() throws {
        var settings = BottleSettings()
        settings.unpinnedPrograms = [exe]

        let encoded = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: encoded)

        #expect(decoded.unpinnedPrograms == [exe])
    }

    @Test("A bottle written before this existed decodes with an empty record")
    func decodesLegacySettings() throws {
        // No `unpinnedPrograms` key at all, which is every bottle on disk today.
        let legacy = """
        {"info": {"name": "Games XO", "pins": [], "blocklist": []}}
        """
        let decoded = try JSONDecoder().decode(BottleSettings.self, from: Data(legacy.utf8))
        #expect(decoded.unpinnedPrograms.isEmpty)
        #expect(decoded.name == "Games XO")
    }

    @Test("Pinning again clears the record, so it never blocks a deliberate pin")
    func repinClearsTheRecord() {
        var settings = BottleSettings()
        settings.unpinnedPrograms = [exe]

        settings.unpinnedPrograms.removeAll { $0 == exe }
        settings.pins.append(PinnedProgram(name: "Truck Simulator", url: exe))

        #expect(settings.unpinnedPrograms.isEmpty)
        #expect(settings.pins.count == 1)
    }

    /// The regression itself: the Start Menu scan runs on every bottle-screen
    /// appearance and after every launch, so this is the call that used to undo
    /// the unpin.
    @Test("The Start Menu scan will not re-pin what the user unpinned")
    func scanRespectsTheUnpin() {
        var settings = BottleSettings()
        let metro = URL(filePath: "/bottle/drive_c/Games/Metro Exodus/MetroExodus.exe")
        settings.unpinnedPrograms = [exe]

        // Both have Start Menu shortcuts; only the one not refused gets pinned.
        #expect(settings.startMenuPinsToAdd(candidates: [exe, metro]) == [metro])
    }

    @Test("The scan is idempotent: an already-pinned program is not added twice")
    func scanDoesNotDuplicate() {
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Truck Simulator", url: exe)]

        #expect(settings.startMenuPinsToAdd(candidates: [exe]).isEmpty)
    }

    @Test("With nothing refused and nothing pinned, the scan pins everything it found")
    func scanPinsFreshFindings() {
        let settings = BottleSettings()
        #expect(settings.startMenuPinsToAdd(candidates: [exe]) == [exe])
    }

    @Test("Only the unpinned program is affected")
    func othersUntouched() {
        let other = URL(filePath: "/bottle/drive_c/Games/Metro Exodus/MetroExodus.exe")
        var settings = BottleSettings()
        settings.pins = [
            PinnedProgram(name: "Truck Simulator", url: exe),
            PinnedProgram(name: "MetroExodus", url: other)
        ]

        settings.pins.removeAll { $0.url == exe }
        settings.unpinnedPrograms.append(exe)

        #expect(settings.pins.map(\.url) == [other])
        #expect(!settings.unpinnedPrograms.contains(other))
    }
}

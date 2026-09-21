//
//  DLLOverrideMergeTests.swift
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

@Suite("WINEDLLOVERRIDES merging")
struct DLLOverrideMergeTests {
    @Test("Wine's own format parses, including multi-DLL entries and disabled")
    func parsing() {
        let entries = DLLOverrideResolver.parse("d3d11,dxgi=n,b;xaudio2_7=b;winemenubuilder.exe=")
        #expect(entries.count == 4)
        #expect(entries[0] == DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin))
        #expect(entries[1] == DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin))
        #expect(entries[2] == DLLOverrideEntry(dllName: "xaudio2_7", mode: .builtin))
        #expect(entries[3] == DLLOverrideEntry(dllName: "winemenubuilder.exe", mode: .disabled))
    }

    @Test("Whitespace is tolerated and malformed entries are skipped, not fatal")
    func parsingEdgeCases() {
        #expect(DLLOverrideResolver.parse(" d3d11 = b ") == [DLLOverrideEntry(dllName: "d3d11", mode: .builtin)])
        #expect(DLLOverrideResolver.parse("nonsense").isEmpty)
        #expect(DLLOverrideResolver.parse("d3d11=zzz").isEmpty)
        #expect(DLLOverrideResolver.parse("").isEmpty)
        // One bad entry doesn't take the good one with it.
        #expect(DLLOverrideResolver.parse("bogus;d3d9=n") == [DLLOverrideEntry(dllName: "d3d9", mode: .native)])
    }

    /// The regression: a caller's WINEDLLOVERRIDES was replaced by the
    /// composed one, so a program's own override silently did nothing.
    @Test("A caller's WINEDLLOVERRIDES survives and beats the backend preset")
    @MainActor func callerOverrideWins() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        bottle.settings.graphicsBackend = .dxmt

        // Without a caller value, the DXMT preset stands.
        let preset = Wine.constructWineEnvironment(for: bottle)["WINEDLLOVERRIDES"] ?? ""
        #expect(preset.contains("d3d11=n,b"))

        // With one, that DLL follows the caller and the rest of the preset stays.
        let merged = Wine.constructWineEnvironment(
            for: bottle, environment: ["WINEDLLOVERRIDES": "d3d11=b;xaudio2_7=n"]
        )["WINEDLLOVERRIDES"] ?? ""
        #expect(merged.contains("d3d11=b"))
        #expect(!merged.contains("d3d11=n,b"))
        #expect(merged.contains("xaudio2_7=n"))
        #expect(merged.contains("winemetal=b"), "the rest of the DXMT preset is untouched")
    }
}

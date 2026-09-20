//
//  FrameRateLimiterTests.swift
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

@Suite("Frame rate limiter")
struct FrameRateLimiterTests {
    /// A stand-in limiter: the environment only checks that the file exists.
    private func makeLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "libsangriafps-\(UUID().uuidString).dylib")
        try Data([0]).write(to: url)
        return url
    }

    @Test("A limit loads the limiter and names the rate")
    func limitSetsBothVariables() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let env = Dictionary(uniqueKeysWithValues: FrameRateLimiter.environment(limit: 60, library: library)
            .map { ($0.key, $0.value) })
        #expect(env[FrameRateLimiter.insertVariable] == library.path(percentEncoded: false))
        #expect(env[FrameRateLimiter.rateVariable] == "60")
    }

    @Test("Off, or no limiter to load, sets nothing")
    func offOrMissingSetsNothing() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        #expect(FrameRateLimiter.environment(limit: 0, library: library).isEmpty)
        #expect(FrameRateLimiter.environment(limit: -5, library: library).isEmpty)
        #expect(FrameRateLimiter.environment(limit: 60, library: nil).isEmpty)
        let missing = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID().uuidString).dylib")
        #expect(FrameRateLimiter.environment(limit: 60, library: missing).isEmpty)
    }

    @Test("A tool can name the limiter; otherwise it comes from the bundle")
    func libraryLocation() {
        let named = FrameRateLimiter.libraryURL(
            environment: [FrameRateLimiter.libraryOverrideVariable: "/tmp/libsangriafps.dylib"]
        )
        #expect(named?.path(percentEncoded: false) == "/tmp/libsangriafps.dylib")
        // The test bundle ships no limiter.
        #expect(FrameRateLimiter.libraryURL(bundle: Bundle(for: BundleMarker.self), environment: [:]) == nil)
    }

    // MARK: - Settings

    @Test("Bottles default to no limit and clamp negatives")
    func bottleSetting() throws {
        var settings = BottleSettings()
        #expect(settings.frameRateLimit == 0)
        settings.frameRateLimit = -1
        #expect(settings.frameRateLimit == 0)
        settings.frameRateLimit = 60
        let data = try PropertyListEncoder().encode(settings)
        #expect(try PropertyListDecoder().decode(BottleSettings.self, from: data).frameRateLimit == 60)
    }

    @Test("A program's limit counts as an override and round-trips")
    func programSetting() throws {
        var overrides = ProgramOverrides()
        overrides.frameRateLimit = 30
        #expect(!overrides.isEmpty)
        let data = try PropertyListEncoder().encode(overrides)
        #expect(try PropertyListDecoder().decode(ProgramOverrides.self, from: data).frameRateLimit == 30)
    }

    // MARK: - Program overrides over a bottle limit

    private func resolved(bottleLimit: Int, programLimit: Int?, library: URL) -> [String: String] {
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        for entry in FrameRateLimiter.environment(limit: bottleLimit, library: library) {
            builder.set(entry.key, entry.value, layer: .bottleManaged)
        }
        var overrides = ProgramOverrides()
        overrides.frameRateLimit = programLimit
        Wine.applyProgramOverrides(
            overrides, frameLimiterLibrary: library, builder: &builder, dllResolver: &dllResolver
        )
        return builder.resolve().environment
    }

    @Test("A program inherits the bottle's limit, replaces it, or turns it off")
    func programOverridesBottle() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library) }

        #expect(resolved(bottleLimit: 60, programLimit: nil, library: library)[FrameRateLimiter.rateVariable] == "60")
        #expect(resolved(bottleLimit: 60, programLimit: 30, library: library)[FrameRateLimiter.rateVariable] == "30")
        #expect(resolved(bottleLimit: 0, programLimit: 30, library: library)[FrameRateLimiter.rateVariable] == "30")

        let off = resolved(bottleLimit: 60, programLimit: 0, library: library)
        #expect(off[FrameRateLimiter.rateVariable] == nil)
        #expect(off[FrameRateLimiter.insertVariable] == nil)
    }
}

/// Anchors `Bundle(for:)` on the test bundle.
private final class BundleMarker {}

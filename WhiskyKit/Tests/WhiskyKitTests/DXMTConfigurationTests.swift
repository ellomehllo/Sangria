//
//  DXMTConfigurationTests.swift
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

@Suite("DXMT configuration")
struct DXMTConfigurationTests {
    @Test("Default settings render a comment-only file")
    func defaultsRenderNoOptions() {
        let body = DXMTConfiguration.render(settings: BottleSettings())
        let options = body.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        #expect(options.isEmpty)
    }

    @Test("Frame pacing and MetalFX render the options DXMT 0.80 reads")
    func renderManagedOptions() {
        let body = DXMTConfiguration.render(
            frameRateLimit: 60, metalFXSpatial: true, upscaleFactor: 1.33, extraOptions: ""
        )
        #expect(body.contains("d3d11.preferredMaxFrameRate = 60\n"))
        #expect(body.contains("d3d11.metalSpatialUpscaleFactor = 1.33\n"))
    }

    @Test("The upscale factor is only written when MetalFX spatial is on")
    func upscaleFactorNeedsMetalFX() {
        let body = DXMTConfiguration.render(
            frameRateLimit: 0, metalFXSpatial: false, upscaleFactor: 1.5, extraOptions: ""
        )
        #expect(!body.contains("metalSpatialUpscaleFactor"))
    }

    @Test("Extra options are appended after managed ones, trimmed, blank lines dropped")
    func extraOptionsAppended() {
        let body = DXMTConfiguration.render(
            frameRateLimit: 30, metalFXSpatial: false, upscaleFactor: 2,
            extraOptions: "  dxgi.customVendorId = 10de  \n\n d3d11.preferredMaxFrameRate = 40\n"
        )
        let lines = body.split(separator: "\n").map(String.init)
        let managed = lines.firstIndex(of: "d3d11.preferredMaxFrameRate = 30")
        let extra = lines.firstIndex(of: "d3d11.preferredMaxFrameRate = 40")
        #expect(lines.contains("dxgi.customVendorId = 10de"))
        #expect(managed != nil && extra != nil)
        if let managed, let extra {
            #expect(managed < extra)
        }
    }

    @Test("Upscale factor clamps to DXMT's documented 1.0-2.0 range")
    func clamp() {
        #expect(DXMTConfiguration.clampUpscaleFactor(0.5) == 1.0)
        #expect(DXMTConfiguration.clampUpscaleFactor(3) == 2.0)
        #expect(DXMTConfiguration.clampUpscaleFactor(.nan) == 2.0)
        var settings = BottleSettings()
        settings.dxmtUpscaleFactor = 9
        #expect(settings.dxmtUpscaleFactor == 2.0)
        settings.dxmtFrameRateLimit = -5
        #expect(settings.dxmtFrameRateLimit == 0)
    }

    @Test("Environment points at the file only once it exists, with a Z: path")
    func environmentEntries() {
        let bottle = URL(filePath: "/tmp/Bottle One")
        var settings = BottleSettings()
        #expect(DXMTConfiguration.environment(settings: settings, bottleURL: bottle) { _ in false }.isEmpty)

        settings.dxmtMetalFXSpatial = true
        let entries = DXMTConfiguration.environment(settings: settings, bottleURL: bottle) { _ in true }
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
        #expect(byKey["DXMT_CONFIG_FILE"] == "Z:/tmp/Bottle One/dxmt.conf")
        #expect(byKey["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == "1")
    }

    @Test("Writing produces the rendered file in the bottle root")
    func writeFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = BottleSettings()
        settings.dxmtFrameRateLimit = 120
        let url = try DXMTConfiguration.write(settings: settings, bottleURL: dir)
        #expect(url.lastPathComponent == "dxmt.conf")
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == DXMTConfiguration.render(settings: settings))
    }

    @Test("DXMT settings survive a settings round trip, and old files decode to defaults")
    func settingsRoundTrip() throws {
        var settings = BottleSettings()
        settings.dxmtFrameRateLimit = 40
        settings.dxmtMetalFXSpatial = true
        settings.dxmtUpscaleFactor = 1.5
        settings.dxmtExtraOptions = "dxgi.forceSDR = True"

        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        #expect(decoded.dxmtFrameRateLimit == 40)
        #expect(decoded.dxmtMetalFXSpatial)
        #expect(decoded.dxmtUpscaleFactor == 1.5)
        #expect(decoded.dxmtExtraOptions == "dxgi.forceSDR = True")

        // A settings file from before the DXMT group existed.
        var plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        plist.removeValue(forKey: "dxmtConfig")
        let legacy = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let old = try PropertyListDecoder().decode(BottleSettings.self, from: legacy)
        #expect(old.dxmtFrameRateLimit == 0)
        #expect(!old.dxmtMetalFXSpatial)
        #expect(old.dxmtUpscaleFactor == 2.0)
    }

    @Test("constructWineEnvironment exports the DXMT tuning")
    @MainActor func constructCarriesDXMT() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)
        bottle.settings.dxmtMetalFXSpatial = true
        try DXMTConfiguration.write(settings: bottle.settings, bottleURL: dir)

        let env = Wine.constructWineEnvironment(for: bottle)
        #expect(env["DXMT_CONFIG_FILE"] == "Z:\(dir.appending(path: "dxmt.conf").path(percentEncoded: false))")
        #expect(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == "1")
    }
}

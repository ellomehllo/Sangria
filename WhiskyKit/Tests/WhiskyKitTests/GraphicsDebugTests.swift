//
//  GraphicsDebugTests.swift
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

@Suite("Graphics debugging")
struct GraphicsDebugTests {
    private let bottleURL = URL(filePath: "/tmp/bottles/ABCD-1234")
    private let programURL = URL(filePath: "/tmp/bottles/ABCD-1234/drive_c/Games/Game.exe")

    private func env(
        _ settings: ProgramGraphicsDebugSettings,
        capture: FrameCaptureRequest? = nil
    ) -> [String: String] {
        let result = GraphicsDebugEnvironment.variables(
            settings: settings, capture: capture, programURL: programURL, bottleURL: bottleURL
        )
        return Dictionary(uniqueKeysWithValues: result.variables.map { ($0.key, $0.value) })
    }

    @Test("Defaults: per-program DXMT and DXVK log paths, nothing else")
    func defaults() {
        let vars = env(ProgramGraphicsDebugSettings())
        #expect(Set(vars.keys) == ["DXMT_LOG_PATH", "DXVK_LOG_PATH"])
        #expect(vars["DXMT_LOG_PATH"]?.hasPrefix("Z:/") == true)
        #expect(vars["DXMT_LOG_PATH"]?.hasSuffix("/dxmt") == true)
        #expect(vars["DXVK_LOG_PATH"]?.hasSuffix("/dxvk") == true)
    }

    @Test("Log directories are returned for creation, one per layer, per program")
    func directories() {
        let result = GraphicsDebugEnvironment.variables(
            settings: ProgramGraphicsDebugSettings(), capture: nil, programURL: programURL, bottleURL: bottleURL
        )
        #expect(result.directoriesToCreate.count == 2)
        let parent = GraphicsLogLocations.programDirectory(programURL: programURL, bottleURL: bottleURL)
        #expect(parent.path.contains("ABCD-1234"))
        #expect(parent.lastPathComponent.hasPrefix("Game-"))
        for dir in result.directoriesToCreate {
            #expect(dir.deletingLastPathComponent().path == parent.path)
        }
        let other = URL(filePath: "/tmp/bottles/ABCD-1234/drive_c/Other/Game.exe")
        #expect(GraphicsLogLocations.programDirectory(programURL: other, bottleURL: bottleURL) != parent)
    }

    @Test("Logging off exports no log paths")
    func loggingOff() {
        var settings = ProgramGraphicsDebugSettings()
        settings.writeGraphicsLogs = false
        #expect(env(settings).isEmpty)
    }

    @Test("Validation toggles and log level map to their variables")
    func validationAndLevel() {
        var settings = ProgramGraphicsDebugSettings()
        settings.metalAPIValidation = true
        settings.metalShaderValidation = true
        settings.dxmtLogLevel = .debug
        let vars = env(settings)
        #expect(vars["MTL_DEBUG_LAYER"] == "1")
        #expect(vars["MTL_SHADER_VALIDATION"] == "1")
        #expect(vars["DXMT_LOG_LEVEL"] == "debug")
    }

    @Test("Frame capture arms Metal capture for the named executable")
    func frameCapture() {
        let vars = env(
            ProgramGraphicsDebugSettings(),
            capture: FrameCaptureRequest(executableName: " Game-Win64-Shipping ", automaticFrame: 300)
        )
        #expect(vars["MTL_CAPTURE_ENABLED"] == "1")
        #expect(vars["DXMT_CAPTURE_EXECUTABLE"] == "Game-Win64-Shipping")
        #expect(vars["DXMT_CAPTURE_FRAME"] == "300")
        #expect(FrameCaptureRequest.defaultExecutableName(for: programURL) == "Game")

        let manual = env(ProgramGraphicsDebugSettings(), capture: FrameCaptureRequest(executableName: "Game"))
        #expect(manual["DXMT_CAPTURE_FRAME"] == nil)
    }

    @Test("Debug variables beat the platform layer's MTL_DEBUG_LAYER=0")
    @MainActor func debugBeatsPlatform() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bottle = Bottle(bottleUrl: dir, inFlight: false, isAvailable: true)

        #expect(Wine.constructWineEnvironment(for: bottle)["MTL_DEBUG_LAYER"] == "0")
        let env = Wine.constructWineEnvironment(
            for: bottle,
            graphicsDebugVariables: [LaunchEnvironmentEntry("MTL_DEBUG_LAYER", "1", reason: "test")]
        )
        #expect(env["MTL_DEBUG_LAYER"] == "1")
    }

    @Test("Old program settings decode with graphics logging on")
    func programSettingsDefaults() throws {
        let data = try PropertyListEncoder().encode(ProgramSettings())
        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)
        #expect(decoded.graphicsDebug == nil)
        #expect(decoded.effectiveGraphicsDebug.writeGraphicsLogs)
        #expect(decoded.allowUnsupportedGraphicsAPI == nil)

        var settings = ProgramSettings()
        settings.effectiveGraphicsDebug.metalShaderValidation = true
        settings.allowUnsupportedGraphicsAPI = true
        let again = try PropertyListDecoder().decode(
            ProgramSettings.self, from: PropertyListEncoder().encode(settings)
        )
        #expect(again.effectiveGraphicsDebug.metalShaderValidation)
        #expect(again.allowUnsupportedGraphicsAPI == true)
    }

    // MARK: - Verification

    @Test("Verification matrix")
    func verification() {
        #expect(GraphicsLogInspector.verify(expected: .dxmt, observed: [.dxmt]) == .confirmed(.dxmt))
        #expect(GraphicsLogInspector.verify(expected: .dxmt, observed: [.dxvk])
            == .mismatch(expected: .dxmt, observed: .dxvk))
        #expect(GraphicsLogInspector.verify(expected: .dxmt, observed: []) == .noEvidence(expected: .dxmt))
        #expect(GraphicsLogInspector.verify(expected: .dxvk, observed: [.dxvk]) == .confirmed(.dxvk))
        #expect(GraphicsLogInspector.verify(expected: .d3dMetal, observed: []) == .notVerifiable(expected: .d3dMetal))
        #expect(GraphicsLogInspector.verify(expected: .d3dMetal, observed: [.dxmt])
            == .mismatch(expected: .d3dMetal, observed: .dxmt))
        #expect(GraphicsLogInspector.verify(expected: .dxmt, observed: [.dxvk]).isMismatch)
    }

    @Test("Only logs written since the run started count as evidence")
    func freshnessFromDisk() throws {
        // The log root is the real one, so the bottle folder name is unique and
        // its whole log subtree is removed afterwards.
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bottle = root.appending(path: UUID().uuidString)
        let program = bottle.appending(path: "drive_c/Game.exe")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: GraphicsLogLocations.root.appending(path: bottle.lastPathComponent))
        }

        let dxmtDir = try #require(GraphicsLogLocations.directory(for: .dxmt, programURL: program, bottleURL: bottle))
        let dxvkDir = try #require(GraphicsLogLocations.directory(for: .dxvk, programURL: program, bottleURL: bottle))
        for dir in [dxmtDir, dxvkDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let stale = dxvkDir.appending(path: "Game_d3d11.log")
        try Data("old".utf8).write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: stale.path
        )
        let start = Date()
        try Data("info: DXMT".utf8).write(to: dxmtDir.appending(path: "Game_d3d11.log"))

        let result = GraphicsLogInspector.verify(
            expected: .dxmt, since: start, programURL: program, bottleURL: bottle, loggingEnabled: true
        )
        #expect(result == .confirmed(.dxmt))
        #expect(GraphicsLogInspector.logFiles(programURL: program, bottleURL: bottle).count == 2)
        #expect(GraphicsLogInspector.verify(
            expected: .dxmt, since: start, programURL: program, bottleURL: bottle, loggingEnabled: false
        ) == .loggingDisabled)
    }

    @Test("Tail returns whole lines from the end of a file")
    func tail() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = (1 ... 1_000).map { "line \($0)" }.joined(separator: "\n")
        try Data(lines.utf8).write(to: url)
        let tail = GraphicsLogInspector.tail(of: url, maxBytes: 100)
        #expect(tail.hasSuffix("line 1000"))
        #expect(tail.hasPrefix("line "))
        #expect(tail.utf8.count <= 100)
        #expect(GraphicsLogInspector.tail(of: url.appendingPathExtension("missing")).isEmpty)
    }

    @Test("Frame captures are found below the program's folder, newest first")
    func captureLocator() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appending(path: "Game/Binaries/Win64")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let older = root.appending(path: "Game.gputrace")
        let newer = nested.appending(path: "Game-Win64-Shipping.gputrace")
        for url in [older, newer] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: older.path
        )
        let found = FrameCaptureLocator.captures(near: root.appending(path: "Game.exe"))
        #expect(found.map(\.lastPathComponent) == ["Game-Win64-Shipping.gputrace", "Game.gputrace"])
    }

    @Test("Log files created in the same second get distinct names, and a handle keeps its own file")
    func uniqueLogFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try Wine.createUniqueLogFile(in: dir, baseName: "2026-09-19T00:00:00Z")
        let handle = try FileHandle(forWritingTo: first)
        let second = try Wine.createUniqueLogFile(in: dir, baseName: "2026-09-19T00:00:00Z")
        let third = try Wine.createUniqueLogFile(in: dir, baseName: "2026-09-19T00:00:00Z")
        #expect(first.lastPathComponent == "2026-09-19T00:00:00Z.log")
        #expect(second.lastPathComponent == "2026-09-19T00:00:00Z-2.log")
        #expect(third.lastPathComponent == "2026-09-19T00:00:00Z-3.log")

        try handle.write(contentsOf: Data("Graphics Backend: DXMT".utf8))
        try handle.close()
        #expect(try String(contentsOf: first, encoding: .utf8) == "Graphics Backend: DXMT")
        #expect(try String(contentsOf: second, encoding: .utf8).isEmpty)
    }

    @Test("FPS measurement turns on the Metal HUD and its log")
    func measureFrameRateEnv() {
        var settings = ProgramGraphicsDebugSettings()
        settings.measureFrameRate = true
        let vars = env(settings)
        #expect(vars["MTL_HUD_ENABLED"] == "1")
        #expect(vars["MTL_HUD_LOG_ENABLED"] == "1")
    }

    @Test("Metal HUD lines yield frames over wall time, per process")
    func metalHUDMeasurement() throws {
        // Captured from a DXMT run on this build; per-frame fields trimmed.
        let lines = [
            "2026-09-19 07:43:11.217 wine[41023:2768978] [libMTLHud] Metric com.apple.hud-stat.fps already exist",
            "2026-09-19 07:43:11.626 wine[41023:2768862] metal-HUD: 50,21.27,146.83,0.26,0.00,0.26,0.00",
            "0120:fixme:something unrelated",
            "2026-09-19 07:43:12.034 wine[41023:2768862] metal-HUD: 99,21.27,146.83,8.14,0.00,8.14,0.00",
            "2026-09-19 07:43:15.626 wine[41023:2768862] metal-HUD: 530,24.44,130.31,8.05,0.00,8.05,0.00",
            "2026-09-19 07:43:12.000 wine[500:1] metal-HUD: 10,1,1",
            "2026-09-19 07:43:13.000 wine[500:1] metal-HUD: 40,1,1"
        ]
        let measurement = try #require(MetalHUDLog.measurement(lines: lines))
        #expect(measurement.processID == 41023)
        #expect(measurement.frames == 480)
        #expect(abs(measurement.seconds - 4.0) < 0.001)
        #expect(abs(measurement.averageFPS - 120) < 0.01)
        #expect(measurement.summary == "120.0 fps over 4 s")

        #expect(MetalHUDLog.measurement(lines: [lines[1]]) == nil)
        #expect(MetalHUDLog.measurement(lines: ["no hud here"]) == nil)
    }

    @Test("Run log entries without graphics fields still decode")
    func runLogBackCompat() throws {
        let entry = RunLogEntry(programName: "Game.exe", logFileName: "x.log")
        var dict = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        )
        dict.removeValue(forKey: "graphicsBackendName")
        let decoded = try JSONDecoder().decode(RunLogEntry.self, from: JSONSerialization.data(withJSONObject: dict))
        #expect(decoded.graphicsBackend == nil)

        var recorded = entry
        recorded.graphicsBackendName = "dxmt"
        recorded.graphicsBackendChoiceName = "somethingNewer"
        #expect(recorded.graphicsBackend == .dxmt)
        #expect(recorded.graphicsBackendChoice == nil)
    }
}

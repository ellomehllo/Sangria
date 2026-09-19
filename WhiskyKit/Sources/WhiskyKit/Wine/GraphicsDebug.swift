//
//  GraphicsDebug.swift
//  WhiskyKit
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

// MARK: - Settings

/// DXMT's `DXMT_LOG_LEVEL` values.
public enum DXMTLogLevel: String, Codable, CaseIterable, Sendable {
    case none
    case error
    case warn
    case info
    case debug
    case trace

    /// DXMT's own default, which Whisky leaves unexported.
    public static let dxmtDefault: DXMTLogLevel = .info
}

/// Per-program graphics debugging switches, stored on ``ProgramSettings``.
public struct ProgramGraphicsDebugSettings: Codable, Equatable, Sendable {
    /// `MTL_DEBUG_LAYER=1`: Metal API validation. Catches CPU-side misuse of
    /// the Metal API, at a noticeable CPU cost.
    public var metalAPIValidation: Bool = false
    /// `MTL_SHADER_VALIDATION=1`: Metal shader validation. Catches GPU-side
    /// out-of-bounds access in translated shaders, at a large GPU cost.
    public var metalShaderValidation: Bool = false
    /// Whether DXMT and DXVK write per-program log files the app can show.
    ///
    /// On by default: the files are small, and they are how the app confirms
    /// which translation layer actually loaded.
    public var writeGraphicsLogs: Bool = true
    /// `DXMT_LOG_LEVEL`.
    public var dxmtLogLevel: DXMTLogLevel = .dxmtDefault
    /// Shows the Metal Performance HUD and logs its frame counter, from
    /// which ``MetalHUDLog`` measures the run's average FPS on any backend.
    public var measureFrameRate: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.metalAPIValidation = (try? container.decodeIfPresent(Bool.self, forKey: .metalAPIValidation)) ?? false
        self.metalShaderValidation = (try? container.decodeIfPresent(Bool.self, forKey: .metalShaderValidation))
            ?? false
        self.writeGraphicsLogs = (try? container.decodeIfPresent(Bool.self, forKey: .writeGraphicsLogs)) ?? true
        self.dxmtLogLevel = container.decodeLenientIfPresent(DXMTLogLevel.self, forKey: .dxmtLogLevel)
            ?? .dxmtDefault
        self.measureFrameRate = (try? container.decodeIfPresent(Bool.self, forKey: .measureFrameRate)) ?? false
    }
}

/// A one-shot request to arm DXMT's Metal frame capture for a launch.
public struct FrameCaptureRequest: Equatable, Sendable {
    /// The executable DXMT should capture, without extension. DXMT compares it
    /// against the process that creates the device, which for a launcher stub
    /// is not the file that was double-clicked.
    public var executableName: String
    /// `DXMT_CAPTURE_FRAME`: capture this frame automatically instead of
    /// waiting for F10.
    public var automaticFrame: Int?

    public init(executableName: String, automaticFrame: Int? = nil) {
        self.executableName = executableName
        self.automaticFrame = automaticFrame
    }

    /// The default target for a program: its own file name without extension.
    public static func defaultExecutableName(for programURL: URL) -> String {
        programURL.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Log locations

/// Where DXMT and DXVK write their per-program logs.
///
/// Each program gets its own directory, with one subdirectory per translation
/// layer. Both layers name their files `<exe>_d3d11.log`, `<exe>_dxgi.log`, so
/// the subdirectory is what tells a DXMT log from a DXVK one, and a fresh file
/// in the wrong one is proof of a backend mismatch.
public enum GraphicsLogLocations {
    /// The root of all graphics logs.
    public static var root: URL {
        Wine.logsFolder.appending(path: "Graphics")
    }

    /// A program's log directory.
    public static func programDirectory(programURL: URL, bottleURL: URL) -> URL {
        root
            .appending(path: bottleURL.lastPathComponent)
            .appending(path: Program.settingsIdentity(for: programURL, bottleURL: bottleURL))
    }

    /// The directory a given translation layer logs to for a program.
    ///
    /// - Returns: `nil` for backends that do not write log files.
    public static func directory(
        for backend: GraphicsBackend,
        programURL: URL,
        bottleURL: URL
    ) -> URL? {
        guard let name = subdirectoryName(for: backend) else { return nil }
        return programDirectory(programURL: programURL, bottleURL: bottleURL).appending(path: name)
    }

    static func subdirectoryName(for backend: GraphicsBackend) -> String? {
        switch backend {
        case .dxmt: "dxmt"
        case .dxvk: "dxvk"
        case .d3dMetal, .wined3d, .recommended: nil
        }
    }

    /// A host path as the Windows side sees it. Wine maps the host root to
    /// `Z:`, and DXMT's and DXVK's PE builds accept forward slashes.
    public static func windowsPath(for url: URL) -> String {
        "Z:\(url.path(percentEncoded: false))"
    }
}

// MARK: - Environment

/// One environment variable a feature contributes to a launch, with the
/// reason recorded in the launch provenance.
public struct LaunchEnvironmentEntry: Equatable, Sendable {
    public let key: String
    public let value: String
    public let reason: String

    public init(_ key: String, _ value: String, reason: String) {
        self.key = key
        self.value = value
        self.reason = reason
    }
}

/// Builds the per-launch graphics debugging environment.
public enum GraphicsDebugEnvironment {
    /// The variables a launch needs for the given debug settings and capture
    /// request, as (key, value, reason).
    ///
    /// Log directories are returned in `directoriesToCreate`: DXMT and DXVK
    /// open their files with `std::ofstream`, which does not create parents,
    /// so a missing directory silently means no log.
    public static func variables(
        settings: ProgramGraphicsDebugSettings,
        capture: FrameCaptureRequest?,
        programURL: URL,
        bottleURL: URL
    ) -> (variables: [LaunchEnvironmentEntry], directoriesToCreate: [URL]) {
        var vars: [LaunchEnvironmentEntry] = []
        var dirs: [URL] = []

        if settings.writeGraphicsLogs {
            for (backend, key) in [(GraphicsBackend.dxmt, "DXMT_LOG_PATH"), (.dxvk, "DXVK_LOG_PATH")] {
                guard let dir = GraphicsLogLocations.directory(
                    for: backend, programURL: programURL, bottleURL: bottleURL
                ) else { continue }
                dirs.append(dir)
                vars.append(LaunchEnvironmentEntry(
                    key,
                    GraphicsLogLocations.windowsPath(for: dir),
                    reason: "Per-program \(backend.displayName) log directory"
                ))
            }
        }
        if settings.dxmtLogLevel != .dxmtDefault {
            vars.append(LaunchEnvironmentEntry(
                "DXMT_LOG_LEVEL", settings.dxmtLogLevel.rawValue, reason: "Program graphics debug setting"
            ))
        }
        if settings.metalAPIValidation {
            vars.append(LaunchEnvironmentEntry("MTL_DEBUG_LAYER", "1", reason: "Metal API validation"))
        }
        if settings.measureFrameRate {
            vars.append(contentsOf: MetalHUDLog.environment)
        }
        if settings.metalShaderValidation {
            vars.append(LaunchEnvironmentEntry("MTL_SHADER_VALIDATION", "1", reason: "Metal shader validation"))
        }
        if let capture {
            let name = capture.executableName.trimmingCharacters(in: .whitespaces)
            vars.append(LaunchEnvironmentEntry("MTL_CAPTURE_ENABLED", "1", reason: "Frame capture armed"))
            vars.append(LaunchEnvironmentEntry(
                "DXMT_CAPTURE_EXECUTABLE", name, reason: "Frame capture target (press F10 in game)"
            ))
            if let frame = capture.automaticFrame, frame > 0 {
                vars.append(LaunchEnvironmentEntry(
                    "DXMT_CAPTURE_FRAME", String(frame), reason: "Automatic frame capture"
                ))
            }
        }
        return (vars, dirs)
    }
}

// MARK: - Verification

/// What the log directories say about which translation layer a run loaded.
public enum BackendVerification: Equatable, Sendable {
    /// The expected layer wrote logs during the run.
    case confirmed(GraphicsBackend)
    /// A different layer than the one the launch asked for wrote logs.
    case mismatch(expected: GraphicsBackend, observed: GraphicsBackend)
    /// The expected layer writes logs but none appeared. The program may not
    /// have created a Direct3D device yet, may use another API, or may have
    /// failed before rendering.
    case noEvidence(expected: GraphicsBackend)
    /// The expected backend writes no log files, and neither DXMT nor DXVK
    /// logged either, which is consistent with it.
    case notVerifiable(expected: GraphicsBackend)
    /// Graphics logging was off for the run.
    case loggingDisabled

    /// A one-line description for the UI.
    public var summary: String {
        switch self {
        case let .confirmed(backend):
            "\(backend.displayName) confirmed: it wrote its log during this run."
        case let .mismatch(expected, observed):
            "Mismatch: launched for \(expected.displayName), but \(observed.displayName) wrote the logs."
        case let .noEvidence(expected):
            "\(expected.displayName) has not logged yet. The program may not have created a D3D device, " +
                "may use a different graphics API, or may have exited early."
        case let .notVerifiable(expected):
            "\(expected.displayName) writes no log file to confirm with; neither DXMT nor DXVK loaded."
        case .loggingDisabled:
            "Graphics logging is off for this program, so the backend can't be confirmed."
        }
    }

    /// Whether this outcome contradicts the launch.
    public var isMismatch: Bool {
        if case .mismatch = self { return true }
        return false
    }
}

/// Inspects a program's log directories.
public enum GraphicsLogInspector {
    /// A log file with its modification date.
    public struct LogFile: Identifiable, Hashable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let backend: GraphicsBackend
        public let modified: Date
        public let size: Int
    }

    /// All log files for a program, newest first.
    public static func logFiles(programURL: URL, bottleURL: URL) -> [LogFile] {
        [GraphicsBackend.dxmt, .dxvk].flatMap { backend -> [LogFile] in
            guard let dir = GraphicsLogLocations.directory(
                for: backend, programURL: programURL, bottleURL: bottleURL
            ) else { return [] }
            return files(in: dir, backend: backend)
        }
        .sorted { $0.modified > $1.modified }
    }

    static func files(in dir: URL, backend: GraphicsBackend) -> [LogFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "log",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { return nil }
            return LogFile(
                url: url,
                backend: backend,
                modified: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0
            )
        }
    }

    /// Compares what a run asked for against the logs written since it started.
    ///
    /// - Parameters:
    ///   - expected: The concrete backend the launch resolved to.
    ///   - since: The run's start time. A small tolerance absorbs filesystem
    ///     timestamp granularity.
    ///   - loggingEnabled: Whether the run exported the log paths.
    public static func verify(
        expected: GraphicsBackend,
        since: Date,
        programURL: URL,
        bottleURL: URL,
        loggingEnabled: Bool
    ) -> BackendVerification {
        guard loggingEnabled else { return .loggingDisabled }
        let threshold = since.addingTimeInterval(-2)
        let fresh = Set(
            logFiles(programURL: programURL, bottleURL: bottleURL)
                .filter { $0.modified >= threshold }
                .map(\.backend)
        )
        return verify(expected: expected, observed: fresh)
    }

    /// The decision behind ``verify(expected:since:programURL:bottleURL:loggingEnabled:)``,
    /// on the set of layers that logged.
    public static func verify(expected: GraphicsBackend, observed: Set<GraphicsBackend>) -> BackendVerification {
        let logsItself = GraphicsLogLocations.subdirectoryName(for: expected) != nil
        if logsItself {
            if observed.contains(expected) { return .confirmed(expected) }
            if let other = observed.first { return .mismatch(expected: expected, observed: other) }
            return .noEvidence(expected: expected)
        }
        if let other = [GraphicsBackend.dxmt, .dxvk].first(where: observed.contains) {
            return .mismatch(expected: expected, observed: other)
        }
        return .notVerifiable(expected: expected)
    }

    /// The last `maxBytes` of a text file, starting at a line boundary.
    public static func tail(of url: URL, maxBytes: Int = 256 * 1_024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        // Lossy on purpose: a tail cut mid-character must still display.
        var text = String(bytes: data, encoding: .utf8)
            ?? String(bytes: data.map { $0 < 0x80 ? $0 : 0x3F }, encoding: .ascii) ?? ""
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }
}

// MARK: - Frame captures

/// Finds the `.gputrace` bundles DXMT's frame capture leaves behind.
///
/// DXMT writes a capture next to the executable that captured it, which for a
/// launcher stub is somewhere below the program's folder rather than beside it.
public enum FrameCaptureLocator {
    /// Capture bundles at or below `programURL`'s folder, newest first.
    ///
    /// The walk is bounded in depth and entry count so a program sitting in
    /// a large game install does not stall the UI.
    public static func captures(near programURL: URL, maxDepth: Int = 4, maxEntries: Int = 20_000) -> [URL] {
        let root = programURL.deletingLastPathComponent()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [(URL, Date)] = []
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            if seen > maxEntries { break }
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "gputrace" {
                let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
                found.append((url, date))
            }
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

//
//  MetalHUDLog.swift
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

/// An average frame rate measured from a run's Metal HUD log.
public struct FrameRateMeasurement: Equatable, Sendable {
    /// Frames presented between the first and last HUD sample.
    public let frames: Int
    /// Seconds between the first and last HUD sample.
    public let seconds: Double
    /// The process the samples came from.
    public let processID: Int

    public var averageFPS: Double {
        seconds > 0 ? Double(frames) / seconds : 0
    }

    /// For example "73.8 fps over 42 s".
    public var summary: String {
        String(format: "%.1f fps over %.0f s", averageFPS, seconds)
    }
}

/// Reads frame rates out of Apple's Metal Performance HUD log.
///
/// With `MTL_HUD_ENABLED=1` and `MTL_HUD_LOG_ENABLED=1`, Metal writes a line
/// like `2026-09-19 07:43:11.626 wine[41023:2768862] metal-HUD: 50,21.27,...`
/// to stderr, which Whisky captures in the run log. The first field is a
/// running count of presented frames. Frames over wall time between the first
/// and last line is the frame rate that actually reached the display, on any
/// backend, since DXMT, DXVK (through MoltenVK) and D3DMetal all present
/// through Metal. The per-frame fields that follow are not relied on.
public enum MetalHUDLog {
    /// The environment that turns the HUD and its log on.
    public static let environment = [
        LaunchEnvironmentEntry("MTL_HUD_ENABLED", "1", reason: "Measure FPS with the Metal HUD"),
        LaunchEnvironmentEntry("MTL_HUD_LOG_ENABLED", "1", reason: "Measure FPS with the Metal HUD")
    ]

    private static let marker = "metal-HUD: "

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// The measurement in a run log, or `nil` without at least two samples.
    public static func measurement(inLogAt url: URL) -> FrameRateMeasurement? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        return measurement(lines: text.split(separator: "\n"))
    }

    /// The measurement in a sequence of log lines. When several processes
    /// logged (a launcher and its game), the one with the most frames wins.
    public static func measurement<S: Sequence>(lines: S) -> FrameRateMeasurement? where S.Element: StringProtocol {
        var first: [Int: (Date, Int)] = [:]
        var last: [Int: (Date, Int)] = [:]
        for line in lines {
            guard let sample = parse(String(line)) else { continue }
            if first[sample.pid] == nil {
                first[sample.pid] = (sample.time, sample.count)
            }
            last[sample.pid] = (sample.time, sample.count)
        }
        let measurements = first.compactMap { pid, start -> FrameRateMeasurement? in
            guard let end = last[pid] else { return nil }
            let frames = end.1 - start.1
            let seconds = end.0.timeIntervalSince(start.0)
            guard frames > 0, seconds > 0 else { return nil }
            return FrameRateMeasurement(frames: frames, seconds: seconds, processID: pid)
        }
        return measurements.max { $0.frames < $1.frames }
    }

    /// One HUD log line: when, from which process, and the running frame count.
    struct Sample: Equatable {
        let time: Date
        let pid: Int
        let count: Int
    }

    static func parse(_ line: String) -> Sample? {
        guard let markerRange = line.range(of: marker), line.count > 23 else { return nil }
        guard let time = timestampFormatter.date(from: String(line.prefix(23))) else { return nil }
        let fields = line[markerRange.upperBound...].split(separator: ",", maxSplits: 1)
        guard let countField = fields.first, let count = Int(countField.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        // "wine[41023:2768862]" -> 41023
        var pid = 0
        if let open = line.range(of: "["), let colon = line[open.upperBound...].firstIndex(of: ":") {
            pid = Int(line[open.upperBound ..< colon]) ?? 0
        }
        return Sample(time: time, pid: pid, count: count)
    }
}

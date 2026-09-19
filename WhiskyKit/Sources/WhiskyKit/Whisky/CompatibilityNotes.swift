//
//  CompatibilityNotes.swift
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
import os.log

/// How well a title ran on a backend.
public enum CompatibilityStatus: String, Codable, CaseIterable, Sendable {
    case working
    case partial
    case broken

    public var displayName: String {
        switch self {
        case .working: "Working"
        case .partial: "Partial"
        case .broken: "Broken"
        }
    }
}

/// One test result in the personal compatibility database: a title, the
/// backend it ran on, and how that went.
///
/// A title tested on three backends is three notes, which is what makes the
/// database a backend comparison rather than a single verdict per game.
public struct CompatibilityNote: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// The concrete backend the test ran on.
    public var backend: GraphicsBackend
    public var status: CompatibilityStatus
    public var notes: String
    public var lastTested: Date
    /// Rough average frame rate, when measured.
    public var averageFPS: Double?
    /// The API the program was detected to use, e.g. "Direct3D 11".
    public var graphicsAPI: String?
    /// The bottle the test ran in, for reference.
    public var bottleName: String?
    /// The executable's path, which links a note back to its program.
    public var programPath: String?
    /// What log verification said about the backend at the time, if known.
    public var backendVerification: String?

    public init(
        id: UUID = UUID(),
        title: String,
        backend: GraphicsBackend,
        status: CompatibilityStatus,
        notes: String = "",
        lastTested: Date = Date(),
        averageFPS: Double? = nil,
        graphicsAPI: String? = nil,
        bottleName: String? = nil,
        programPath: String? = nil,
        backendVerification: String? = nil
    ) {
        self.id = id
        self.title = title
        self.backend = backend
        self.status = status
        self.notes = notes
        self.lastTested = lastTested
        self.averageFPS = averageFPS
        self.graphicsAPI = graphicsAPI
        self.bottleName = bottleName
        self.programPath = programPath
        self.backendVerification = backendVerification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        // Lenient so a note written by a build with more backends or statuses
        // still loads instead of failing the whole database.
        self.backend = container.decodeLenientIfPresent(GraphicsBackend.self, forKey: .backend) ?? .recommended
        self.status = container.decodeLenientIfPresent(CompatibilityStatus.self, forKey: .status) ?? .partial
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.lastTested = try container.decodeIfPresent(Date.self, forKey: .lastTested) ?? .distantPast
        self.averageFPS = try container.decodeIfPresent(Double.self, forKey: .averageFPS)
        self.graphicsAPI = try container.decodeIfPresent(String.self, forKey: .graphicsAPI)
        self.bottleName = try container.decodeIfPresent(String.self, forKey: .bottleName)
        self.programPath = try container.decodeIfPresent(String.self, forKey: .programPath)
        self.backendVerification = try container.decodeIfPresent(String.self, forKey: .backendVerification)
    }
}

/// The personal compatibility database, persisted as one JSON file.
public struct CompatibilityDatabase: Codable, Equatable, Sendable {
    static let currentVersion = 1

    public var version: Int
    public var notes: [CompatibilityNote]

    public init(notes: [CompatibilityNote] = []) {
        self.version = Self.currentVersion
        self.notes = notes
    }

    /// `~/Library/Application Support/<bundle id>/CompatibilityNotes.json`.
    public static var defaultURL: URL {
        WhiskyWineInstaller.applicationFolder.appending(path: "CompatibilityNotes.json")
    }

    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "CompatibilityNotes")

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Loads the database. A missing file is an empty database.
    ///
    /// A file that exists but will not decode is moved aside, never
    /// overwritten, so a bad write or a hand edit gone wrong costs nothing
    /// that cannot be recovered from the `.corrupt` copy.
    public static func load(from url: URL = defaultURL) -> CompatibilityDatabase {
        guard let data = try? Data(contentsOf: url) else { return CompatibilityDatabase() }
        do {
            return try decoder.decode(CompatibilityDatabase.self, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            logger.error(
                "Compatibility notes did not decode; moved to \(aside.lastPathComponent, privacy: .public)"
            )
            return CompatibilityDatabase()
        }
    }

    /// Writes the database atomically, creating its folder if needed.
    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Inserts a note, or replaces the one with the same id.
    public mutating func upsert(_ note: CompatibilityNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
    }

    public mutating func remove(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Notes for one executable, newest test first.
    public func notes(forProgramPath path: String) -> [CompatibilityNote] {
        notes.filter { $0.programPath == path }.sorted { $0.lastTested > $1.lastTested }
    }

    /// Notes grouped by title (case-insensitive), titles sorted, each group
    /// newest test first. This is the per-title backend comparison.
    public func groupedByTitle() -> [(title: String, notes: [CompatibilityNote])] {
        let groups = Dictionary(grouping: notes) { $0.title.lowercased() }
        return groups.values
            .map { group in
                let sorted = group.sorted { $0.lastTested > $1.lastTested }
                return (title: sorted[0].title, notes: sorted)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The database as CSV, for a spreadsheet.
    public func csv() -> String {
        let formatter = ISO8601DateFormatter()
        let header = "Title,Backend,Status,Average FPS,Graphics API,Last Tested,Bottle,Verification,Notes"
        let rows = notes.sorted { $0.lastTested > $1.lastTested }.map { note in
            [
                note.title,
                note.backend.displayName,
                note.status.displayName,
                note.averageFPS.map { String(format: "%.1f", $0) } ?? "",
                note.graphicsAPI ?? "",
                formatter.string(from: note.lastTested),
                note.bottleName ?? "",
                note.backendVerification ?? "",
                note.notes
            ]
            .map(Self.csvField)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

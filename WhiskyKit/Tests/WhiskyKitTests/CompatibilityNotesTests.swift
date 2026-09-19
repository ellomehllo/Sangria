//
//  CompatibilityNotesTests.swift
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

@Suite("Compatibility notes")
struct CompatibilityNotesTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "CompatibilityNotes.json")
    }

    @Test("A missing file loads as an empty database")
    func missingFile() {
        #expect(CompatibilityDatabase.load(from: tempFile()).notes.isEmpty)
    }

    @Test("Notes round-trip through the JSON file, creating its folder")
    func roundTrip() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let tested = Date(timeIntervalSince1970: 1_790_000_000)
        var database = CompatibilityDatabase()
        database.upsert(CompatibilityNote(
            title: "Test Game", backend: .dxmt, status: .working, notes: "Smooth at 1440p",
            lastTested: tested, averageFPS: 92.5, graphicsAPI: "Direct3D 11", bottleName: "Games",
            programPath: "/x/Game.exe", backendVerification: "DXMT confirmed"
        ))
        try database.save(to: url)

        let loaded = CompatibilityDatabase.load(from: url)
        #expect(loaded == database)
        #expect(loaded.notes.first?.lastTested == tested)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains("\"backend\" : \"dxmt\""))
    }

    @Test("Upsert replaces by id; remove deletes")
    func upsertAndRemove() {
        var database = CompatibilityDatabase()
        var note = CompatibilityNote(title: "A", backend: .dxmt, status: .broken)
        database.upsert(note)
        note.status = .working
        database.upsert(note)
        #expect(database.notes.count == 1)
        #expect(database.notes[0].status == .working)
        database.remove(id: note.id)
        #expect(database.notes.isEmpty)
    }

    @Test("Grouping by title makes a per-title backend comparison, newest first")
    func grouping() {
        let old = Date(timeIntervalSinceNow: -86_400)
        let database = CompatibilityDatabase(notes: [
            CompatibilityNote(title: "zeta", backend: .dxvk, status: .partial),
            CompatibilityNote(title: "Alpha", backend: .d3dMetal, status: .working, lastTested: old),
            CompatibilityNote(title: "alpha", backend: .dxmt, status: .working)
        ])
        let groups = database.groupedByTitle()
        #expect(groups.map { $0.notes.count } == [2, 1])
        #expect(groups[0].notes.map(\.backend) == [.dxmt, .d3dMetal])
        #expect(groups[1].title == "zeta")
    }

    @Test("Notes for a program are matched by executable path")
    func notesForProgram() {
        let database = CompatibilityDatabase(notes: [
            CompatibilityNote(title: "A", backend: .dxmt, status: .working, programPath: "/a.exe"),
            CompatibilityNote(title: "B", backend: .dxmt, status: .working, programPath: "/b.exe")
        ])
        #expect(database.notes(forProgramPath: "/a.exe").map(\.title) == ["A"])
    }

    @Test("CSV quotes fields with commas, quotes and newlines")
    func csv() {
        let database = CompatibilityDatabase(notes: [
            CompatibilityNote(
                title: "Game, The", backend: .dxmt, status: .partial,
                notes: "Says \"hi\"\nthen crashes", averageFPS: 59.94
            )
        ])
        let csv = database.csv()
        #expect(csv.hasPrefix("Title,Backend,Status,Average FPS"))
        #expect(csv.contains("\"Game, The\",DXMT,Partial,59.9,"))
        #expect(csv.contains("\"Says \"\"hi\"\"\nthen crashes\""))
    }

    @Test("A corrupt file is moved aside, never overwritten")
    func corruptFile() throws {
        let url = tempFile()
        let dir = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        #expect(CompatibilityDatabase.load(from: url).notes.isEmpty)
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!contents.contains("CompatibilityNotes.json"))
        #expect(contents.contains { $0.hasPrefix("CompatibilityNotes.corrupt-") })
    }

    @Test("Unknown backend or status values decode leniently")
    func lenientDecoding() throws {
        let json = """
        {"version": 1, "notes": [{"id": "\(UUID().uuidString)", "title": "Future",
          "backend": "vkd3dMetal", "status": "sparkling", "lastTested": "2026-09-19T00:00:00Z"}]}
        """
        let database = try CompatibilityDatabase.decoder.decode(CompatibilityDatabase.self, from: Data(json.utf8))
        #expect(database.notes.first?.backend == .recommended)
        #expect(database.notes.first?.status == .partial)
    }
}

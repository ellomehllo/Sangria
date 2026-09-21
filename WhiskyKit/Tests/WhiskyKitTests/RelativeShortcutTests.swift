//
//  RelativeShortcutTests.swift
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

/// A shortcut has to survive the bottle moving, and the migration that gives it
/// that ability has to lose nothing on the way.
@Suite("Shortcuts point at the game, not at the path it used to have")
struct RelativeShortcutTests {
    /// A Games folder with one game in it, under a directory that can be moved.
    private struct Sandbox: ~Copyable {
        let base: URL
        let bottle: URL
        let root: GamesRoot
        let exe: URL

        /// Everything that can throw happens before the first stored property
        /// is set: a noncopyable value cannot be conditionally destroyed, so a
        /// `try` after the last assignment will not compile.
        init(bottleName: String = "Bottle A") throws {
            let base = FileManager.default.temporaryDirectory
                .appending(path: "RelativeShortcutTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            let bottle = base.appending(path: bottleName)
            let root = try GamesRoot(bottleURL: bottle).createIfNeeded()
            let exe = root.url.appending(path: "Euro Truck Simulator Gold/bin/game.exe")
            try FileManager.default.createDirectory(
                at: exe.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("MZ".utf8).write(to: exe)

            self.base = base
            self.bottle = bottle
            self.root = root
            self.exe = exe
        }

        deinit {
            try? FileManager.default.removeItem(at: base)
        }
    }

    @Test("A new pin records where the game sits inside Games")
    func newPinIsRelative() throws {
        let sandbox = try Sandbox()
        let pin = PinnedProgram(name: "Euro Truck", url: sandbox.exe, gamesRoot: sandbox.root)
        #expect(pin.relativePath == "Euro Truck Simulator Gold/bin/game.exe")
        #expect(pin.url == sandbox.exe)
    }

    @Test("A pin to something outside Games gets no relative path, and still works")
    func pinOutsideGames() throws {
        let sandbox = try Sandbox()
        let outside = sandbox.bottle.appending(path: "drive_c/Program Files/Thing/thing.exe")
        try FileManager.default.createDirectory(
            at: outside.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: outside)

        let pin = PinnedProgram(name: "Thing", url: outside, gamesRoot: sandbox.root)
        #expect(pin.relativePath == nil)
        #expect(pin.resolvedURL(gamesRoot: sandbox.root) == outside)
    }

    @Test("A pin made without a Games folder still resolves by its absolute path")
    func pinWithoutRoot() throws {
        let sandbox = try Sandbox()
        let pin = PinnedProgram(name: "Euro Truck", url: sandbox.exe)
        #expect(pin.relativePath == nil)
        #expect(pin.resolvedURL(gamesRoot: nil) == sandbox.exe)
    }

    // MARK: - The point of the exercise

    @Test("A shortcut survives the bottle being moved")
    func survivesAMove() throws {
        let sandbox = try Sandbox()
        let pin = PinnedProgram(name: "Euro Truck", url: sandbox.exe, gamesRoot: sandbox.root)

        // The same bottle, reached at a different path — a rename, a restore, a
        // container that moved. The absolute URL in the pin is now wrong.
        let moved = sandbox.base.appending(path: "Bottle Renamed")
        try FileManager.default.moveItem(at: sandbox.bottle, to: moved)
        let movedRoot = GamesRoot(bottleURL: moved)

        let resolved = try #require(pin.resolvedURL(gamesRoot: movedRoot))
        #expect(resolved == movedRoot.url.appending(path: "Euro Truck Simulator Gold/bin/game.exe"))
        #expect(FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)))
    }

    @Test("A shortcut to a game that was deleted reports the path it knew, not a lie")
    func deletedGame() throws {
        let sandbox = try Sandbox()
        let pin = PinnedProgram(name: "Euro Truck", url: sandbox.exe, gamesRoot: sandbox.root)
        try FileManager.default.removeItem(at: sandbox.exe)

        // Falls back to the absolute URL, which also does not exist. The caller
        // checks existence and drops the pin; what matters is that it is not
        // handed some other file that happens to be at that relative path.
        #expect(pin.resolvedURL(gamesRoot: sandbox.root) == sandbox.exe)
    }

    // MARK: - Migration

    @Test("Existing pins gain a relative path without losing anything")
    func migrationIsAdditive() throws {
        let sandbox = try Sandbox()
        var settings = BottleSettings()
        // Written the old way: absolute URL, no relative path.
        settings.pins = [PinnedProgram(name: "Euro Truck", url: sandbox.exe)]
        settings.pins[0].relativePath = nil

        // Called outside `#expect`: the macro captures its operand immutably,
        // so a mutating method cannot run inside one.
        let changed = settings.migratePinsToRelativePaths(gamesRoot: sandbox.root)
        #expect(changed)

        #expect(settings.pins.count == 1)
        #expect(settings.pins[0].name == "Euro Truck")
        #expect(settings.pins[0].url == sandbox.exe)
        #expect(settings.pins[0].relativePath == "Euro Truck Simulator Gold/bin/game.exe")
    }

    @Test("Migration leaves a pin outside Games exactly as it found it")
    func migrationSkipsOutsiders() throws {
        let sandbox = try Sandbox()
        let outside = sandbox.bottle.appending(path: "drive_c/windows/notepad.exe")
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Notepad", url: outside)]
        let before = settings.pins

        let changed = settings.migratePinsToRelativePaths(gamesRoot: sandbox.root)
        #expect(!changed)
        #expect(settings.pins == before)
    }

    @Test("Migration is idempotent, so it can run on every load")
    func migrationRunsTwice() throws {
        let sandbox = try Sandbox()
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Euro Truck", url: sandbox.exe)]
        settings.pins[0].relativePath = nil

        let first = settings.migratePinsToRelativePaths(gamesRoot: sandbox.root)
        #expect(first)
        let afterFirst = settings.pins
        let second = settings.migratePinsToRelativePaths(gamesRoot: sandbox.root)
        #expect(!second)
        #expect(settings.pins == afterFirst)
    }

    @Test("Migration never drops a pin, even one whose file is gone")
    func migrationKeepsBrokenPins() throws {
        let sandbox = try Sandbox()
        let missing = sandbox.root.url.appending(path: "Deleted Game/game.exe")
        var settings = BottleSettings()
        settings.pins = [
            PinnedProgram(name: "Euro Truck", url: sandbox.exe),
            PinnedProgram(name: "Deleted", url: missing)
        ]
        settings.pins[0].relativePath = nil
        settings.pins[1].relativePath = nil

        settings.migratePinsToRelativePaths(gamesRoot: sandbox.root)
        #expect(settings.pins.count == 2)
        #expect(settings.pins[1].relativePath == "Deleted Game/game.exe")
    }

    // MARK: - Storage

    @Test("The relative path round-trips through the bottle's plist")
    func survivesEncoding() throws {
        let sandbox = try Sandbox()
        var settings = BottleSettings()
        settings.pins = [PinnedProgram(name: "Euro Truck", url: sandbox.exe, gamesRoot: sandbox.root)]

        let encoded = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: encoded)
        #expect(decoded.pins[0].relativePath == "Euro Truck Simulator Gold/bin/game.exe")
        #expect(decoded.pins[0].url == sandbox.exe)
    }

    @Test("A pin written before relative paths existed decodes without one")
    func legacyPinDecodes() throws {
        let legacy = """
        {"info": {"name": "Games XO", "pins": [
          {"name": "RE", "url": "file:///Bottles/A/drive_c/Games/Resident/re.exe", "removable": false}
        ]}}
        """
        let decoded = try JSONDecoder().decode(BottleSettings.self, from: Data(legacy.utf8))
        #expect(decoded.pins.count == 1)
        #expect(decoded.pins[0].name == "RE")
        #expect(decoded.pins[0].relativePath == nil)
    }
}

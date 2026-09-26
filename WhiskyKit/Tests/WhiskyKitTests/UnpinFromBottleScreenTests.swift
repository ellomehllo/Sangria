//
//  UnpinFromBottleScreenTests.swift
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

/// The bottle screen unpins through `Program.pinned`, the library through
/// `BottleSettings` directly. Two routes to one outcome is two chances to
/// diverge, so this pins down what the `Program` route actually does to the
/// store and to the file.
@Suite("Unpinning from the bottle screen")
@MainActor
struct UnpinFromBottleScreenTests {
    /// A real bottle directory, because the question is whether the change
    /// reaches disk.
    /// A struct rather than a tuple: three members is one past what reads
    /// clearly at the call site.
    private struct Fixture {
        let bottle: Bottle
        let exe: URL
        let root: URL
    }

    private func makeBottle() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "UnpinTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let exe = root.appending(path: "drive_c/Games/Metro Exodus/MetroExodus.exe")
        try FileManager.default.createDirectory(
            at: exe.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: exe)
        return Fixture(
            bottle: Bottle(bottleUrl: root, inFlight: false, isAvailable: true), exe: exe, root: root
        )
    }

    @Test("Unpinning removes the pin, records the refusal, and lands on disk")
    func unpinPersists() throws {
        let fixture = try makeBottle()
        let bottle = fixture.bottle
        let exe = fixture.exe
        let root = fixture.root
        defer { try? FileManager.default.removeItem(at: root) }

        let program = Program(url: exe, bottle: bottle)
        program.pinned = true
        #expect(bottle.settings.pins.count == 1)

        program.pinned = false

        // In memory.
        #expect(bottle.settings.pins.isEmpty)
        #expect(bottle.settings.unpinnedPrograms.contains(exe))

        // On disk — the bottle saves on every settings mutation, so the file
        // should already agree without an explicit save.
        let onDisk = try BottleSettings.decode(from: root.appending(path: "Metadata.plist"))
        #expect(onDisk.pins.isEmpty)
        #expect(onDisk.unpinnedPrograms.contains(exe))
    }

    @Test("A fresh Bottle read back from disk still shows it unpinned")
    func survivesRelaunch() throws {
        let fixture = try makeBottle()
        let bottle = fixture.bottle
        let exe = fixture.exe
        let root = fixture.root
        defer { try? FileManager.default.removeItem(at: root) }

        let program = Program(url: exe, bottle: bottle)
        program.pinned = true
        program.pinned = false

        // What the next launch sees.
        let reopened = Bottle(bottleUrl: root, inFlight: false, isAvailable: true)
        #expect(reopened.settings.pins.isEmpty)
        #expect(reopened.settings.unpinnedPrograms.contains(exe))
        #expect(Program(url: exe, bottle: reopened).pinned == false)
    }

    @Test("The bottle screen's own list drops it")
    func pinnedProgramsListDrops() throws {
        let fixture = try makeBottle()
        let bottle = fixture.bottle
        let exe = fixture.exe
        let root = fixture.root
        defer { try? FileManager.default.removeItem(at: root) }

        let program = Program(url: exe, bottle: bottle)
        program.pinned = true
        bottle.programs = [program]
        #expect(bottle.pinnedPrograms.count == 1)

        program.pinned = false
        #expect(bottle.pinnedPrograms.isEmpty)
    }

    /// Both routes have to agree, or unpinning in one place leaves the other
    /// still showing it.
    @Test("The library's route and the bottle screen's route reach the same state")
    func routesAgree() throws {
        let fixtureA = try makeBottle()
        let bottleA = fixtureA.bottle
        let exeA = fixtureA.exe
        let rootA = fixtureA.root
        let fixtureB = try makeBottle()
        let bottleB = fixtureB.bottle
        let exeB = fixtureB.exe
        let rootB = fixtureB.root
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        // Bottle screen: through Program.
        let program = Program(url: exeA, bottle: bottleA)
        program.pinned = true
        program.pinned = false

        // Library: straight at the settings.
        bottleB.settings.pins = [PinnedProgram(name: "Metro Exodus", url: exeB)]
        bottleB.settings.pins.removeAll { $0.url == exeB }
        bottleB.settings.unpinnedPrograms.append(exeB)

        #expect(bottleA.settings.pins.isEmpty == bottleB.settings.pins.isEmpty)
        #expect(bottleA.settings.unpinnedPrograms.count == bottleB.settings.unpinnedPrograms.count)
    }
}

//
//  ProgramScanRootsTests.swift
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

/// The scan used to walk only the two Program Files folders, so every game in
/// `C:\Games` — which is where this app puts them — was invisible to the
/// Installed Programs list, and to the pin controls that list offers.
@Suite("What the program scan walks")
struct ProgramScanRootsTests {
    private struct Sandbox: ~Copyable {
        let driveC: URL

        init(_ relativePaths: [String]) throws {
            let driveC = FileManager.default.temporaryDirectory
                .appending(path: "ScanRoots-\(UUID().uuidString)/drive_c")
                .resolvingSymlinksInPath()
            for relative in relativePaths {
                let url = driveC.appending(path: relative)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data("MZ".utf8).write(to: url)
            }
            self.driveC = driveC
        }

        deinit {
            try? FileManager.default.removeItem(at: driveC.deletingLastPathComponent())
        }
    }

    private func scan(_ sandbox: borrowing Sandbox) -> [String] {
        Bottle.discoverInstalledExecutables(driveC: sandbox.driveC, blocklist: [])
            .map(\.lastPathComponent)
            .sorted()
    }

    @Test("A game in C:\\Games is found")
    func gamesFolderIsScanned() throws {
        let sandbox = try Sandbox([
            "Games/Metro Exodus/MetroExodus.exe",
            "Games/PRAGMATA/PRAGMATA.exe"
        ])
        #expect(scan(sandbox) == ["MetroExodus.exe", "PRAGMATA.exe"])
    }

    @Test("The Program Files folders are still scanned")
    func programFilesStillScanned() throws {
        let sandbox = try Sandbox([
            "Program Files/Thing/thing.exe",
            "Program Files (x86)/Old/old.exe",
            "Games/A Game/game.exe"
        ])
        #expect(scan(sandbox) == ["game.exe", "old.exe", "thing.exe"])
    }

    @Test("Nothing outside the scan roots is picked up")
    func otherFoldersIgnored() throws {
        let sandbox = try Sandbox([
            "windows/system32/notepad.exe",
            "users/someone/Downloads/installer.exe",
            "Games/A Game/game.exe"
        ])
        #expect(scan(sandbox) == ["game.exe"])
    }

    /// Inno Setup leaves these beside the game, numbered, and a game folder
    /// usually holds several. They would otherwise outnumber the games.
    @Test("Uninstallers are left out", arguments: [
        "unins000.exe", "unins001.exe", "UNINS002.exe", "uninstall.exe", "Uninstaller.exe"
    ])
    func uninstallersSkipped(name: String) throws {
        let sandbox = try Sandbox(["Games/A Game/game.exe", "Games/A Game/\(name)"])
        #expect(scan(sandbox) == ["game.exe"])
    }

    @Test("A crash reporter beside a game is still left out")
    func noiseStillSkipped() throws {
        let sandbox = try Sandbox([
            "Games/A Game/game.exe",
            "Games/A Game/CrashReport.exe"
        ])
        #expect(scan(sandbox) == ["game.exe"])
    }

    @Test("A blocked executable stays blocked wherever it lives")
    func blocklistApplies() throws {
        let sandbox = try Sandbox(["Games/A Game/game.exe", "Games/A Game/other.exe"])
        let blocked = sandbox.driveC.appending(path: "Games/A Game/other.exe")
        let found = Bottle.discoverInstalledExecutables(driveC: sandbox.driveC, blocklist: [blocked])
        #expect(found.map(\.lastPathComponent) == ["game.exe"])
    }
}

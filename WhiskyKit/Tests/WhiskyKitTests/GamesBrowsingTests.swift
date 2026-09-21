//
//  GamesBrowsingTests.swift
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

/// Listing and changing things, with the same rule as navigation: if it is not
/// inside `C:\Games`, it does not exist as far as this browser is concerned.
@Suite("Browsing the Games folder")
struct GamesBrowsingTests {
    private struct Sandbox: ~Copyable {
        let base: URL
        let root: GamesRoot

        init() throws {
            let base = FileManager.default.temporaryDirectory
                .appending(path: "GamesBrowsingTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let root = try GamesRoot(directory: base.appending(path: "Games")).createIfNeeded()
            self.base = base
            self.root = root
        }

        @discardableResult
        func makeFile(_ relative: String, bytes: Int = 4) throws -> URL {
            let url = root.url.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(repeating: 0x4D, count: bytes).write(to: url)
            return url
        }

        @discardableResult
        func makeFolder(_ relative: String) throws -> URL {
            let url = root.url.appending(path: relative)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        deinit {
            try? FileManager.default.removeItem(at: base)
        }
    }

    // MARK: - Listing

    @Test("Folders come before files, then names sort the way Finder sorts them")
    func listingOrder() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("zeta.exe")
        try sandbox.makeFile("alpha.exe")
        try sandbox.makeFolder("Metro Exodus")
        try sandbox.makeFolder("Euro Truck Simulator Gold")

        let names = try sandbox.root.contents(of: sandbox.root.url).map(\.name)
        #expect(names == ["Euro Truck Simulator Gold", "Metro Exodus", "alpha.exe", "zeta.exe"])
    }

    @Test("A symlink pointing outside the root is not listed at all")
    func escapingSymlinkIsHidden() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("game.exe")
        let outside = sandbox.base.appending(path: "Secrets")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sandbox.root.url.appending(path: "escape"), withDestinationURL: outside
        )

        let names = try sandbox.root.contents(of: sandbox.root.url).map(\.name)
        #expect(names == ["game.exe"])
    }

    @Test("Listing a folder outside the root returns nothing rather than its contents")
    func listingOutsideIsEmpty() throws {
        let sandbox = try Sandbox()
        let outside = sandbox.base.appending(path: "Secrets")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: outside.appending(path: "loot.txt"))

        #expect(try sandbox.root.contents(of: outside).isEmpty)
    }

    @Test("An executable is recognised, a folder and a data file are not")
    func executableDetection() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("Metro Exodus/MetroExodus.exe")
        try sandbox.makeFile("Metro Exodus/readme.txt")
        try sandbox.makeFolder("Metro Exodus/content")

        let entries = try sandbox.root.contents(of: sandbox.root.url.appending(path: "Metro Exodus"))
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
        #expect(byName["MetroExodus.exe"]?.isExecutable == true)
        #expect(byName["readme.txt"]?.isExecutable == false)
        #expect(byName["content"]?.isExecutable == false)
        #expect(byName["content"]?.isDirectory == true)
    }

    @Test("An installer is offered as one", arguments: [
        ("setup.exe", true),
        ("Setup.exe", true),
        ("install_game.exe", true),
        ("GameInstaller.exe", true),
        ("thing.msi", true),
        ("MetroExodus.exe", false),
        ("game.exe", false),
        ("readme.txt", false)
    ])
    func installerDetection(name: String, expected: Bool) throws {
        let sandbox = try Sandbox()
        let url = try sandbox.makeFile(name)
        let entry = GamesEntry(url: url, isDirectory: false)
        #expect(entry.isInstaller == expected)
    }

    @Test("Used space counts the files, not the folders")
    func usedSpace() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("Metro Exodus/MetroExodus.exe", bytes: 1000)
        try sandbox.makeFile("Metro Exodus/content/pack.dat", bytes: 2000)
        try sandbox.makeFile("readme.txt", bytes: 24)

        #expect(sandbox.root.usedBytes() == 3024)
    }

    // MARK: - New Folder

    @Test("A new folder is created and can be navigated into")
    func newFolder() throws {
        let sandbox = try Sandbox()
        let made = try sandbox.root.createFolder(named: "My Games", in: sandbox.root.url)
        #expect(made == sandbox.root.url.appending(path: "My Games"))
        #expect(sandbox.root.resolve(made) == made)

        // And it is somewhere you can keep going.
        let nested = try sandbox.root.createFolder(named: "Saves", in: made)
        #expect(try sandbox.root.contents(of: made).map(\.name) == ["Saves"])
        #expect(sandbox.root.breadcrumb(to: nested).map(\.name) == ["Games", "My Games", "Saves"])
    }

    @Test("A folder name that is really a path is refused", arguments: [
        "../Escape", "a/b", "a\\b", "C:", "..", ".", "", "   ", ".hidden"
    ])
    func refusedFolderNames(name: String) throws {
        let sandbox = try Sandbox()
        #expect(throws: GamesRootError.self) {
            try sandbox.root.createFolder(named: name, in: sandbox.root.url)
        }
    }

    @Test("A new folder cannot be made outside the root")
    func newFolderOutside() throws {
        let sandbox = try Sandbox()
        #expect(throws: GamesRootError.outsideRoot) {
            try sandbox.root.createFolder(named: "Loot", in: sandbox.base)
        }
        #expect(!FileManager.default.fileExists(atPath: sandbox.base.appending(path: "Loot").path))
    }

    @Test("Creating a folder that is already there says so instead of failing silently")
    func duplicateFolder() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFolder("Metro Exodus")
        #expect(throws: GamesRootError.alreadyExists("Metro Exodus")) {
            try sandbox.root.createFolder(named: "Metro Exodus", in: sandbox.root.url)
        }
    }

    // MARK: - Rename

    @Test("Renaming moves the file and leaves it inside the root")
    func rename() throws {
        let sandbox = try Sandbox()
        let exe = try sandbox.makeFile("Metro Exodus/old.exe")
        let renamed = try sandbox.root.rename(exe, to: "MetroExodus.exe")
        #expect(renamed.lastPathComponent == "MetroExodus.exe")
        #expect(sandbox.root.relativePath(for: renamed) == "Metro Exodus/MetroExodus.exe")
        #expect(!FileManager.default.fileExists(atPath: exe.path(percentEncoded: false)))
    }

    @Test("A rename cannot be used to move something out", arguments: ["../loot.exe", "/tmp/loot.exe"])
    func renameCannotEscape(name: String) throws {
        let sandbox = try Sandbox()
        let exe = try sandbox.makeFile("game.exe")
        #expect(throws: GamesRootError.self) {
            try sandbox.root.rename(exe, to: name)
        }
        #expect(FileManager.default.fileExists(atPath: exe.path(percentEncoded: false)))
    }

    @Test("The root itself cannot be renamed")
    func rootCannotBeRenamed() throws {
        let sandbox = try Sandbox()
        #expect(throws: GamesRootError.outsideRoot) {
            try sandbox.root.rename(sandbox.root.url, to: "Not Games")
        }
    }

    @Test("Renaming something outside the root is refused")
    func renameOutside() throws {
        let sandbox = try Sandbox()
        let outside = sandbox.base.appending(path: "loot.txt")
        try Data("x".utf8).write(to: outside)
        #expect(throws: GamesRootError.outsideRoot) {
            try sandbox.root.rename(outside, to: "renamed.txt")
        }
        #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    }

    @Test("Renaming onto a name already in use says so")
    func renameCollision() throws {
        let sandbox = try Sandbox()
        let one = try sandbox.makeFile("one.exe")
        try sandbox.makeFile("two.exe")
        #expect(throws: GamesRootError.alreadyExists("two.exe")) {
            try sandbox.root.rename(one, to: "two.exe")
        }
    }

    // MARK: - Trash

    @Test("The root itself cannot be trashed")
    func rootCannotBeTrashed() throws {
        let sandbox = try Sandbox()
        #expect(throws: GamesRootError.outsideRoot) {
            try sandbox.root.moveToTrash(sandbox.root.url)
        }
        #expect(sandbox.root.exists)
    }

    @Test("Nothing outside the root can be trashed")
    func trashOutside() throws {
        let sandbox = try Sandbox()
        let outside = sandbox.base.appending(path: "loot.txt")
        try Data("x".utf8).write(to: outside)
        #expect(throws: GamesRootError.outsideRoot) {
            try sandbox.root.moveToTrash(outside)
        }
        #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    }
}

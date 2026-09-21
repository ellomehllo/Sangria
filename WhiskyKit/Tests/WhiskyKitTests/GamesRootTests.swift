//
//  GamesRootTests.swift
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

/// A real directory tree, because a containment check that never meets a
/// symlink has not been tested.
private struct Sandbox: ~Copyable {
    let base: URL
    let root: GamesRoot

    init() throws {
        // `resolvingSymlinksInPath` because the system temp directory is itself
        // reached through a symlink (`/var` -> `/private/var`), and half of
        // what these tests check is that such a thing cannot confuse the root.
        base = FileManager.default.temporaryDirectory
            .appending(path: "GamesRootTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = try GamesRoot(directory: base.appending(path: "Games")).createIfNeeded()
    }

    /// Makes a directory inside the Games root and returns it.
    @discardableResult
    func makeFolder(_ relative: String) throws -> URL {
        let url = root.url.appending(path: relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func makeFile(_ relative: String, contents: String = "") throws -> URL {
        let url = root.url.appending(path: relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Something outside the root entirely — the place an escape would land.
    @discardableResult
    func makeOutsider(_ relative: String) throws -> URL {
        let url = base.appending(path: "Outside").appending(path: relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("secret".utf8).write(to: url)
        return url
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }
}

@Suite("The Games folder is the only folder")
struct GamesRootTests {
    // MARK: - What is allowed

    @Test("The root itself resolves")
    func rootResolves() throws {
        let sandbox = try Sandbox()
        #expect(sandbox.root.resolve(sandbox.root.url) == sandbox.root.url)
        #expect(sandbox.root.isInside(sandbox.root.url))
    }

    @Test("A folder inside resolves")
    func childResolves() throws {
        let sandbox = try Sandbox()
        let game = try sandbox.makeFolder("Metro Exodus")
        #expect(sandbox.root.resolve(game) == game)
    }

    @Test("A folder the user just made is reachable")
    func newFolderIsReachable() throws {
        let sandbox = try Sandbox()
        let made = try sandbox.makeFolder("My Games/Saves")
        #expect(sandbox.root.resolve(made) == made)
        #expect(sandbox.root.relativePath(for: made) == "My Games/Saves")
    }

    @Test("A path that does not exist yet still resolves, so New Folder can check before creating")
    func absentPathResolves() throws {
        let sandbox = try Sandbox()
        let planned = sandbox.root.url.appending(path: "Not Yet")
        #expect(sandbox.root.resolve(planned) == planned)
    }

    // MARK: - Names people actually use

    @Test("Names with spaces survive the round trip")
    func spacesInNames() throws {
        let sandbox = try Sandbox()
        let exe = try sandbox.makeFile("Euro Truck Simulator Gold/game.exe")
        #expect(sandbox.root.relativePath(for: exe) == "Euro Truck Simulator Gold/game.exe")
        #expect(sandbox.root.resolve(relativePath: "Euro Truck Simulator Gold/game.exe") == exe)
    }

    @Test("Unicode names survive the round trip", arguments: [
        "Ведьмак 3/witcher3.exe",
        "デモンズソウル/game.exe",
        "Café Français/jeu.exe",
        "🎮 Games/play.exe"
    ])
    func unicodeNames(relative: String) throws {
        let sandbox = try Sandbox()
        let exe = try sandbox.makeFile(relative)
        let readBack = sandbox.root.relativePath(for: exe)
        #expect(readBack != nil)
        // Compared after normalization: the filesystem hands back decomposed
        // forms on some volumes, and a shortcut that points at the same file
        // is the same shortcut whichever way the accents are spelled.
        #expect(readBack?.precomposedStringWithCanonicalMapping
            == relative.precomposedStringWithCanonicalMapping)
        #expect(sandbox.root.resolve(relativePath: relative) != nil)
    }

    // MARK: - Escapes

    @Test("A relative path climbing with .. is refused")
    func dotDotInRelativePath() throws {
        let sandbox = try Sandbox()
        try sandbox.makeOutsider("loot.txt")
        #expect(sandbox.root.resolve(relativePath: "../Outside/loot.txt") == nil)
        #expect(sandbox.root.resolve(relativePath: "Metro Exodus/../../Outside/loot.txt") == nil)
        #expect(sandbox.root.resolve(relativePath: "..") == nil)
    }

    @Test("A URL climbing with .. is refused even though it lands back inside")
    func dotDotInURL() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFolder("Metro Exodus")
        // Lands inside the root, and is still refused: nothing here needs to
        // climb, so a path that does is either a bug or an attempt.
        let roundabout = sandbox.root.url
            .appending(path: "Metro Exodus")
            .appending(path: "..")
            .appending(path: "Metro Exodus")
        #expect(sandbox.root.resolve(roundabout) == nil)
    }

    @Test("The parent of the root does not resolve")
    func parentOfRoot() throws {
        let sandbox = try Sandbox()
        #expect(sandbox.root.resolve(sandbox.root.url.deletingLastPathComponent()) == nil)
        #expect(sandbox.root.parent(of: sandbox.root.url) == nil)
    }

    @Test("An absolute path elsewhere is refused")
    func absolutePathOutside() throws {
        let sandbox = try Sandbox()
        let outsider = try sandbox.makeOutsider("loot.txt")
        #expect(sandbox.root.resolve(outsider) == nil)
        #expect(sandbox.root.resolve(URL(filePath: "/etc/passwd")) == nil)
        #expect(sandbox.root.resolve(URL(filePath: "/")) == nil)
    }

    @Test("An absolute path given as a relative one is refused")
    func absoluteMasqueradingAsRelative() throws {
        let sandbox = try Sandbox()
        #expect(sandbox.root.resolve(relativePath: "/etc/passwd") == nil)
        #expect(sandbox.root.resolve(relativePath: "\\Windows\\System32") == nil)
        #expect(sandbox.root.resolve(relativePath: "C:\\Windows\\System32") == nil)
        #expect(sandbox.root.resolve(relativePath: "") == nil)
    }

    @Test("A symlink inside the root that points outside is refused")
    func symlinkEscape() throws {
        let sandbox = try Sandbox()
        let outsider = try sandbox.makeOutsider("loot.txt")
        let link = sandbox.root.url.appending(path: "escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsider)

        #expect(sandbox.root.resolve(link) == nil)
        #expect(sandbox.root.resolve(relativePath: "escape") == nil)
        #expect(!sandbox.root.isInside(link))
    }

    @Test("A file reached through a symlinked folder that points outside is refused")
    func symlinkedFolderEscape() throws {
        let sandbox = try Sandbox()
        try sandbox.makeOutsider("Stash/loot.txt")
        let stash = sandbox.base.appending(path: "Outside").appending(path: "Stash")
        let link = sandbox.root.url.appending(path: "Shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: stash)

        #expect(sandbox.root.resolve(relativePath: "Shortcut/loot.txt") == nil)
        #expect(sandbox.root.resolve(link.appending(path: "loot.txt")) == nil)
    }

    @Test("A symlink inside the root pointing back inside it is allowed")
    func symlinkInsideIsFine() throws {
        let sandbox = try Sandbox()
        let real = try sandbox.makeFile("Metro Exodus/MetroExodus.exe")
        let link = sandbox.root.url.appending(path: "Metro.exe")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        // Resolves to the real file, inside the root, so it is allowed — and
        // it is the real path that comes back, which is what gets launched.
        #expect(sandbox.root.resolve(link) == real)
    }

    @Test("A sibling folder whose name merely starts with the root's is refused")
    func siblingPrefixIsNotContainment() throws {
        let sandbox = try Sandbox()
        let sibling = sandbox.base.appending(path: "Games Backup")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        #expect(sandbox.root.resolve(sibling.appending(path: "loot.txt")) == nil)
    }

    @Test("A non-file URL is refused")
    func nonFileURL() throws {
        let sandbox = try Sandbox()
        let remote = try #require(URL(string: "https://example.com/game.exe"))
        #expect(sandbox.root.resolve(remote) == nil)
    }

    // MARK: - Presentation

    @Test("Paths are shown the way the game sees them")
    func displayPath() throws {
        let sandbox = try Sandbox()
        let exe = try sandbox.makeFile("Euro Truck Simulator Gold/bin/win_x86/eurotrucks.exe")
        #expect(
            sandbox.root.displayPath(for: exe)
                == "C:\\Games\\Euro Truck Simulator Gold\\bin\\win_x86\\eurotrucks.exe"
        )
        #expect(sandbox.root.displayPath(for: sandbox.root.url) == "C:\\Games")
    }

    @Test("Nothing outside the root has a display path")
    func noDisplayPathOutside() throws {
        let sandbox = try Sandbox()
        let outsider = try sandbox.makeOutsider("loot.txt")
        #expect(sandbox.root.displayPath(for: outsider) == nil)
    }

    @Test("The breadcrumb starts at Games and has no step above it")
    func breadcrumb() throws {
        let sandbox = try Sandbox()
        let deep = try sandbox.makeFolder("Metro Exodus/content/textures")
        let trail = sandbox.root.breadcrumb(to: deep)
        #expect(trail.map(\.name) == ["Games", "Metro Exodus", "content", "textures"])
        #expect(trail.first?.url == sandbox.root.url)
    }

    @Test("Going back up from a subfolder stops at the root")
    func walkingBackUpStops() throws {
        let sandbox = try Sandbox()
        let deep = try sandbox.makeFolder("Metro Exodus/content")
        let parent = try #require(sandbox.root.parent(of: deep))
        #expect(parent == sandbox.root.url.appending(path: "Metro Exodus"))
        let grandparent = try #require(sandbox.root.parent(of: parent))
        #expect(grandparent == sandbox.root.url)
        // And there it stops.
        #expect(sandbox.root.parent(of: grandparent) == nil)
    }

    // MARK: - Construction

    @Test("A bottle's Games folder is drive_c/Games")
    func bottleGamesFolder() {
        let bottle = URL(filePath: "/tmp/Bottles/ABC")
        let root = GamesRoot(bottleURL: bottle)
        #expect(root.url.lastPathComponent == "Games")
        #expect(root.url.deletingLastPathComponent().lastPathComponent == "drive_c")
    }

    @Test("A missing Games folder is reported missing, then created on request")
    func createIfNeeded() throws {
        let sandbox = try Sandbox()
        let fresh = GamesRoot(directory: sandbox.base.appending(path: "Another"))
        #expect(!fresh.exists)
        let made = try fresh.createIfNeeded()
        #expect(made.exists)
    }
}

//
//  GamesBrowserModel.swift
//  Whisky
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

import AppKit
import Foundation
import SwiftUI
import WhiskyKit

/// What the Games browser is looking at.
///
/// Every path it hands out has been through ``GamesRoot/resolve(_:)``, and
/// every path it is given goes back through it before anything happens. The
/// model never holds a URL it has not checked, which is why `current` is
/// private to set.
@MainActor
final class GamesBrowserModel: ObservableObject {
    @Published private(set) var root: GamesRoot?
    @Published private(set) var current: URL?
    @Published private(set) var entries: [GamesEntry] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var toast: ToastData?
    /// Executables whose launch call has not come back yet.
    @Published private(set) var starting: Set<URL> = []

    private weak var bottle: Bottle?

    // MARK: - Where we are

    /// Points the browser at a bottle's Games folder, creating it if this is
    /// the first time anyone has looked.
    func configure(bottle: Bottle?) {
        self.bottle = bottle
        guard let bottle else {
            root = nil
            current = nil
            entries = []
            return
        }

        let candidate = GamesRoot(bottleURL: bottle.url)
        // Created rather than reported missing: a games folder is the one
        // thing this whole screen is about, and an empty one is a better
        // answer than an error nobody can act on.
        root = (try? candidate.createIfNeeded()) ?? candidate
        current = root?.url
        refresh()
    }

    var canGoUp: Bool {
        guard let root, let current else { return false }
        return root.parent(of: current) != nil
    }

    var breadcrumb: [(name: String, url: URL)] {
        guard let root, let current else { return [] }
        return root.breadcrumb(to: current)
    }

    /// What to write above the list: `C:\Games\Metro Exodus`.
    var displayPath: String {
        guard let root, let current else { return GamesRoot.displayRoot }
        return root.displayPath(for: current) ?? GamesRoot.displayRoot
    }

    func navigate(to url: URL) {
        guard let root, let resolved = root.resolve(url) else {
            errorMessage = GamesRootError.outsideRoot.errorDescription
            return
        }
        current = resolved
        refresh()
    }

    func goUp() {
        guard let root, let current, let parent = root.parent(of: current) else { return }
        navigate(to: parent)
    }

    func open(_ entry: GamesEntry) {
        guard entry.isDirectory else { return }
        navigate(to: entry.url)
    }

    func refresh() {
        guard let root, let current else {
            entries = []
            return
        }
        do {
            entries = try root.contents(of: current)
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Changing things

    func createFolder(named name: String) {
        guard let root, let current else { return }
        do {
            let made = try root.createFolder(named: name, in: current)
            refresh()
            toast = ToastData(
                message: String(localized: "games.toast.folderCreated \(made.lastPathComponent)"),
                style: .success
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ entry: GamesEntry, to name: String) {
        guard let root else { return }
        do {
            try root.rename(entry.url, to: name)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveToTrash(_ entry: GamesEntry) {
        guard let root else { return }
        do {
            try root.moveToTrash(entry.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealInFinder(_ entry: GamesEntry) {
        guard let root, root.isInside(entry.url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    // MARK: - The library

    /// Whether this executable already has a shortcut.
    func isInLibrary(_ entry: GamesEntry) -> Bool {
        guard let bottle, let root else { return false }
        return bottle.settings.pins.contains { pin in
            pin.resolvedURL(gamesRoot: root) == entry.url
        }
    }

    /// Adds a shortcut. Copies nothing and moves nothing — the game stays
    /// exactly where it is.
    func addToLibrary(_ entry: GamesEntry) {
        guard let bottle, let root, let url = root.resolve(entry.url), !isInLibrary(entry) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        bottle.settings.pins.append(PinnedProgram(name: name, url: url, gamesRoot: root))
        // A game added on purpose is no longer a game the user refused, so the
        // Start Menu scan may pin it again later without arguing with itself.
        bottle.settings.unpinnedPrograms.removeAll { $0 == url }
        toast = ToastData(message: String(localized: "games.toast.addedToLibrary \(name)"), style: .success)
    }

    // MARK: - Playing

    func isStarting(_ entry: GamesEntry) -> Bool {
        starting.contains(entry.url)
    }

    /// Starts a game, or runs an installer — the same call either way, because
    /// to Wine they are the same kind of thing.
    func play(_ entry: GamesEntry) {
        guard let bottle, let root, let url = root.resolve(entry.url) else { return }
        guard !starting.contains(url) else { return }

        starting.insert(url)
        Task {
            let result = await GameLauncher.play(url, in: bottle)
            starting.remove(url)
            toast = result.toastData
        }
    }

    /// Runs an installer and then offers whatever it left behind.
    ///
    /// "Best effort" is the honest description: it compares the executables
    /// under the Games folder before and after, so anything the installer put
    /// somewhere else — `C:\Program Files`, most often — is not in the list.
    /// The user can still add it by hand from the browser.
    func install(_ entry: GamesEntry, onFinish: @escaping ([GamesEntry]) -> Void) {
        guard let bottle, let root, let url = root.resolve(entry.url) else { return }
        guard !starting.contains(url) else { return }

        let before = Set(Self.executables(under: root).map(\.url))
        starting.insert(url)
        Task {
            let result = await GameLauncher.play(url, in: bottle)
            starting.remove(url)
            toast = result.toastData
            refresh()

            let after = Self.executables(under: root)
            let fresh = after.filter { !before.contains($0.url) && !$0.isInstaller }
            onFinish(fresh)
        }
    }

    /// Every executable under the Games folder, at any depth.
    static func executables(under root: GamesRoot) -> [GamesEntry] {
        guard let walker = FileManager.default.enumerator(
            at: root.url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [GamesEntry] = []
        for case let child as URL in walker {
            guard child.pathExtension.lowercased() == "exe" else { continue }
            guard let safe = root.resolve(child) else { continue }
            found.append(GamesEntry(url: safe, isDirectory: false))
        }
        return found.sorted(by: GamesEntry.folderFirstByName)
    }
}

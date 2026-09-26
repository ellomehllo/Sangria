//
//  GamesBrowserView.swift
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
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

/// `C:\Games`, and nothing above it.
///
/// This is the only file browser a casual player sees, and it is deliberately
/// a small one: it starts at the games folder, it cannot climb out of it, and
/// its menus offer playing and installing rather than anything Wine-shaped.
struct GamesBrowserView: View {
    let bottle: Bottle?

    @StateObject private var model = GamesBrowserModel()
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: GamesEntry?
    @State private var discovered: [GamesEntry] = []
    @State private var showDiscovered = false

    var body: some View {
        Group {
            if model.root == nil {
                noBottle
            } else {
                browser
            }
        }
        .navigationTitle("games.title")
        .navigationSubtitle(model.displayPath)
        .toast($model.toast)
        .toolbar { toolbar }
        .task(id: bottle?.url) {
            model.configure(bottle: bottle)
        }
        .alert(
            "games.error.title",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("button.ok") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showNewFolder) {
            RenameView("games.newFolder.title", name: newFolderName, confirmTitle: "games.newFolder.confirm") {
                model.createFolder(named: $0)
            }
        }
        .sheet(item: $renaming) { entry in
            RenameView("games.rename.title", name: entry.name, confirmTitle: "games.rename.confirm") {
                model.rename(entry, to: $0)
            }
        }
        .sheet(isPresented: $showDiscovered) {
            InstalledGamesSheet(games: discovered) { chosen in
                for entry in chosen {
                    model.addToLibrary(entry)
                }
            }
        }
    }

    // MARK: - Pieces

    private var browser: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            if model.entries.isEmpty {
                emptyFolder
            } else {
                list
            }
        }
    }

    /// The trail of folders, starting at Games.
    ///
    /// There is no "up" control at the root because there is nowhere to go:
    /// the first crumb *is* the root, and a disabled arrow next to it would
    /// only invite someone to wonder what is behind it.
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if model.canGoUp {
                Button {
                    model.goUp()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("games.up")
                .accessibilityIdentifier("games.up")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button(crumb.name) {
                            model.navigate(to: crumb.url)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == model.breadcrumb.count - 1 ? .primary : .secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityIdentifier("games.breadcrumb")
    }

    private var list: some View {
        List {
            ForEach(model.entries) { entry in
                row(for: entry)
                    .contextMenu { menu(for: entry) }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("games.list")
    }

    /// A folder opens on one click; a game needs two.
    ///
    /// The asymmetry is deliberate. A folder row already draws a chevron, and a
    /// disclosure arrow that does nothing until you double-click it is a lie
    /// about what the row is. Starting a game, on the other hand, takes over
    /// the screen for the next hour, so it keeps the double-click that stops it
    /// happening by accident.
    @ViewBuilder
    private func row(for entry: GamesEntry) -> some View {
        if entry.isDirectory {
            Button {
                model.open(entry)
            } label: {
                GamesRow(entry: entry, isStarting: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            GamesRow(entry: entry, isStarting: model.isStarting(entry))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { activate(entry) }
        }
    }

    @ViewBuilder
    private func menu(for entry: GamesEntry) -> some View {
        if entry.isExecutable {
            Button("button.play") { model.play(entry) }
            Button("games.install.action") { runInstaller(entry) }
            if model.isInLibrary(entry) {
                Button("games.alreadyInLibrary") {}
                    .disabled(true)
            } else {
                Button("games.addToLibrary") { model.addToLibrary(entry) }
            }
            Divider()
        } else if entry.isDirectory {
            Button("games.open") { model.open(entry) }
            Button("games.newFolder") {
                model.navigate(to: entry.url)
                newFolderName = ""
                showNewFolder = true
            }
            Divider()
        } else if entry.isInstaller {
            // A .msi is not an executable but is still something to install.
            Button("games.install.action") { runInstaller(entry) }
            Divider()
        }
        Button("games.rename") { renaming = entry }
        Button("button.showInFinder") { model.revealInFinder(entry) }
        Button("games.trash", role: .destructive) { model.moveToTrash(entry) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // The tab's headline action, and the only way in normal mode to start
        // a game that is not under C:\Games. It is what Developer Mode called
        // "Run Program…", with a name a player recognises and a library entry
        // so it never has to be found by hand twice.
        ToolbarItem(placement: .primaryAction) {
            Button("games.play", systemImage: "play.fill") {
                choosePlay()
            }
            .disabled(model.root == nil)
            .accessibilityIdentifier("games.play")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("games.newFolder", systemImage: "folder.badge.plus") {
                newFolderName = ""
                showNewFolder = true
            }
            .disabled(model.root == nil)
            .accessibilityIdentifier("games.newFolder")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("games.install", systemImage: "arrow.down.app") {
                chooseInstaller()
            }
            .disabled(model.root == nil)
            .accessibilityIdentifier("games.install")
        }
    }

    private var emptyFolder: some View {
        ContentUnavailableView {
            Label("games.empty.title", systemImage: "folder")
        } description: {
            Text("games.empty.description")
        } actions: {
            Button("games.install") { chooseInstaller() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var noBottle: some View {
        ContentUnavailableView {
            Label("games.noLibrary.title", systemImage: "externaldrive.badge.questionmark")
        } description: {
            Text("games.noLibrary.description")
        }
    }

    // MARK: - Actions

    /// Double-click: open a folder, play a game.
    private func activate(_ entry: GamesEntry) {
        if entry.isDirectory {
            model.open(entry)
        } else if entry.isExecutable {
            model.play(entry)
        }
    }

    private func runInstaller(_ entry: GamesEntry) {
        model.install(entry) { fresh in
            guard !fresh.isEmpty else { return }
            discovered = fresh
            showDiscovered = true
        }
    }

    /// Picks a game to play, and keeps it in the library.
    ///
    /// Unlike the installer picker below, this one is *not* confined to
    /// `C:\Games`. It opens there because that is where games usually are, but
    /// it lets you walk anywhere on the C: drive — an installer that put a game
    /// in `Program Files` leaves it somewhere the Games browser cannot show,
    /// and refusing to launch it would mean Developer Mode is the only way to
    /// play your own game.
    private func choosePlay() {
        guard let root = model.root else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = model.current ?? root.url
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.message = String(localized: "games.play.prompt")
        panel.prompt = String(localized: "games.play")
        panel.begin { result in
            guard result == .OK, let picked = panel.urls.first else { return }
            model.playPicked(picked)
        }
    }

    /// Picks a setup file. The panel opens in the Games folder, and anything
    /// chosen from outside it is refused rather than run.
    private func chooseInstaller() {
        guard let root = model.root else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = model.current ?? root.url
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer")
        ]
        panel.message = String(localized: "games.install.prompt")
        panel.prompt = String(localized: "games.install.action")
        panel.begin { result in
            guard result == .OK, let picked = panel.urls.first else { return }
            // The panel can be navigated anywhere, so the answer still goes
            // through the funnel before it is run.
            guard let safe = root.resolve(picked) else {
                model.errorMessage = String(localized: "games.install.outsideGames")
                return
            }
            runInstaller(GamesEntry(url: safe, isDirectory: false))
        }
    }
}

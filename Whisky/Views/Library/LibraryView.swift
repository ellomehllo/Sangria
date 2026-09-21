//
//  LibraryView.swift
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
import WhiskyKit

/// Everything worth launching, across every bottle, most recently played first.
///
/// This is the home screen because it is the thing people open Whisky to do. A
/// bottle is a Wine prefix, which is an implementation detail of running a
/// Windows program on a Mac, and it only earns space on screen once there is
/// more than one of them.
///
/// Entries come from ``LibraryCatalogue``, so Steam games sit beside pinned
/// programs and a future launcher needs no change here.
struct LibraryView: View {
    @EnvironmentObject var bottleVM: BottleVM
    @EnvironmentObject var settings: AppSettings
    /// Where the sidebar is pointing. The library can send the user to the
    /// Games folder, and — in Developer Mode — to a bottle, so it needs the
    /// whole selection rather than a bottle-shaped slice of it.
    @Binding var selection: SidebarItem
    /// Toggled by the toolbar's refresh button. Folded into the reload trigger
    /// because the bottle list is unchanged by a refresh, so watching only that
    /// left the button spinning without rebuilding anything.
    @Binding var refresh: Bool

    @AppStorage("librarySort") private var sort: LibrarySort = .recent

    @StateObject private var model = LibraryModel()
    @State private var search: String = ""
    @State private var renaming: LibraryRow?

    private var bottles: [Bottle] { bottleVM.bottles.filter(\.isAvailable) }

    private var visible: [LibraryRow] {
        guard !search.isEmpty else { return model.rows }
        return model.rows.filter { $0.item.name.localizedCaseInsensitiveContains(search) }
    }

    /// Every input that changes what the grid should contain. Pins live in
    /// bottle settings, so a program pinned in the bottle screen shows up here
    /// without a relaunch.
    private var reloadTrigger: String {
        let pins = bottles.flatMap { $0.settings.pins.map(\.name) }
        return (bottles.map(\.url.path) + pins + ["\(refresh)"]).joined(separator: "\u{1F}")
    }

    var body: some View {
        Group {
            if model.rows.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle("library.title")
        .searchable(text: $search, prompt: Text("library.search"))
        .toolbar { sortMenu }
        .toast($model.toast)
        .task(id: reloadTrigger) {
            await model.reload(bottles: bottles)
        }
        .onChange(of: sort, initial: true) {
            model.sort = sort
        }
        .onDisappear {
            model.stopTracking()
        }
        .sheet(item: $renaming) { row in
            RenameView("library.card.rename", name: row.item.name) { rename(row, to: $0) }
        }
        .alert(
            "library.launch.failed",
            isPresented: Binding(
                get: { model.launchError != nil },
                set: { if !$0 { model.launchError = nil } }
            )
        ) {
            Button("button.ok") { model.launchError = nil }
        } message: {
            Text(model.launchError ?? "")
        }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("library.sort", selection: $sort) {
                    // Sorting by bottle names one, so that option belongs to
                    // Developer Mode like the rest of them.
                    ForEach(LibrarySort.allCases.filter { $0 != .bottle || settings.developerMode }) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("library.sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("library.sort")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                // 180 is the narrowest a poster can be and still fit "Last
                // played 2 hr. ago" beside the play button; two of them still
                // fit at the window's own minimum width, where the sidebar
                // leaves about 330pt. Capped at 230: a poster wider than that
                // is 345 tall and only a row of them fits on screen.
                columns: [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 16)],
                spacing: 16
            ) {
                ForEach(visible) { row in
                    LibraryCard(
                        item: row.item,
                        bottleName: row.bottleName,
                        lastPlayed: row.lastPlayed,
                        state: model.state(for: row.item),
                        launch: { model.launch(row, bottles: bottles) }
                    )
                    .contextMenu { menu(for: row) }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func menu(for row: LibraryRow) -> some View {
        Button("button.play") { model.launch(row, bottles: bottles) }
        if model.state(for: row.item) == .running {
            Button("library.card.stop") { model.stop(row, bottles: bottles) }
        }
        Divider()
        if case let .program(url) = row.item.launch {
            Button("library.card.rename") { renaming = row }
            Button("library.card.remove", role: .destructive) { removeShortcut(url, in: row.item.bottleURL) }
            if settings.developerMode {
                Button("button.showInFinder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if let program = bottles.first(where: { $0.url == row.item.bottleURL })?
                    .programs.first(where: { $0.url == url }) {
                    UseD3DMetalToggle(program: program)
                }
            }
        }
        // Per-program settings live inside the bottle's own navigation stack,
        // which the library cannot push onto, so this is as close as the menu
        // gets without a deep link into it — and it names a bottle, so it is
        // only offered to someone who has asked to see them.
        if settings.developerMode {
            Button("library.card.configure") {
                selection = .bottle(row.item.bottleURL)
            }
        }
    }

    /// Renames the shortcut. The file on disk is untouched: this is the label
    /// on a card, not the name of a game.
    private func rename(_ row: LibraryRow, to name: String) {
        guard case let .program(url) = row.item.launch,
              let bottle = bottles.first(where: { $0.url == row.item.bottleURL }),
              let index = bottle.settings.pins.firstIndex(where: { $0.url == url })
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // No reload needed: `reloadTrigger` watches every pin's name.
        bottle.settings.pins[index].name = trimmed
    }

    private func openGames() {
        selection = .games
    }

    /// Removes the shortcut and nothing else. The game stays where it is.
    private func removeShortcut(_ url: URL, in bottleURL: URL) {
        guard let bottle = bottles.first(where: { $0.url == bottleURL }) else { return }
        bottle.settings.pins.removeAll { $0.url == url }
        // Recorded here as well as in `pinned`'s setter: the library lists pins
        // straight from bottle settings, so it can offer to remove one for a
        // program the bottle has never scanned and has no `Program` for.
        // Without this the Start Menu scan would pin it again on the next visit.
        if !bottle.settings.unpinnedPrograms.contains(url) {
            bottle.settings.unpinnedPrograms.append(url)
        }
        if let program = bottle.programs.first(where: { $0.url == url }) {
            program.pinned = false
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("library.empty.title", systemImage: "square.grid.2x2")
        } description: {
            Text(bottles.isEmpty ? "library.empty.noBottle" : "library.empty.noPrograms")
        } actions: {
            if !bottles.isEmpty {
                Button("library.empty.openGames") { openGames() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library.openGames")
            }
        }
    }
}

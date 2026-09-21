//
//  ContentView+Sidebar.swift
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
import SemanticVersion
import SwiftUI
import WhiskyKit

/// What the sidebar can be showing.
///
/// Three things in normal mode. A bottle is the fourth, and it exists only
/// while Developer Mode is on — which is why this is an enum rather than the
/// `URL?` it used to be: "no bottle selected" and "the Games folder" are
/// different places, and one optional cannot hold both.
enum SidebarItem: Hashable {
    case library
    case games
    case settings
    case bottle(URL)
}

// MARK: - Sidebar & Detail

extension ContentView {
    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: bottleSelection) {
                Section {
                    fixedRow(
                        .library, title: "library.title",
                        systemImage: "square.grid.2x2", identifier: "sidebar.library"
                    )
                    fixedRow(
                        .games, title: "games.title",
                        systemImage: "folder", identifier: "sidebar.games"
                    )
                    fixedRow(
                        .settings, title: "settings.title",
                        systemImage: "gearshape", identifier: "sidebar.settings"
                    )
                }
                // A bottle is a Wine prefix, which is an implementation detail
                // of running a Windows program on a Mac. Nobody needs to learn
                // it to play a game, so it is here only for someone who has
                // said they want it.
                if settings.developerMode {
                    Section("sidebar.bottles") {
                        ForEach(sortedBottles) { bottle in
                            bottleRow(bottle)
                                .tag(SidebarItem.bottle(bottle.url))
                        }
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: settings.developerMode)
            .listStyle(.sidebar)
            .accessibilityIdentifier("bottleSidebar")
            // No search field here. The library has one, and two fields forty
            // points apart searching different things (bottles here, programs
            // there) is a choice nobody should have to make to find a game.
            .onChange(of: newlyCreatedBottleURL) { _, url in
                guard let url else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    selection = .bottle(url)
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bottleRow(_ bottle: Bottle) -> some View {
        Group {
            if bottle.inFlight {
                HStack {
                    Text(bottle.settings.name)
                    Spacer()
                    ProgressView().controlSize(.small)
                }
                .opacity(0.5)
            } else if !bottle.isAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(bottle.settings.name)
                    Spacer()
                    Button {
                        Task { await bottle.remove(delete: false) }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("button.removeFromList.help")
                }
                .opacity(0.6)
                .selectionDisabled(true)
            } else {
                BottleListEntry(
                    bottle: bottle,
                    selected: bottleSelection,
                    refresh: $triggerRefresh,
                    toast: $toast
                )
                .accessibilityIdentifier("sidebar.bottle")
            }
        }
        .id(bottle.url)
        .listRowBackground(sidebarSelection(isSelected: selection == .bottle(bottle.url)))
        .foregroundStyle(selection == .bottle(bottle.url)
            ? AnyShapeStyle(.white)
            : AnyShapeStyle(.primary))
    }

    /// One of the three rows that are always there.
    ///
    /// Drawn as a button rather than a tagged row because these carry their
    /// own selection colour (see ``sidebarSelection(isSelected:)``), and
    /// because a `List`'s own selection is a single optional that cannot
    /// distinguish "Games" from "no bottle".
    private func fixedRow(
        _ item: SidebarItem,
        title: LocalizedStringKey,
        systemImage: String,
        identifier: String
    ) -> some View {
        Button {
            selection = item
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == item ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .listRowBackground(sidebarSelection(isSelected: selection == item))
        .accessibilityIdentifier(identifier)
    }

    /// The sidebar's selected-row fill, in the app's own blue.
    ///
    /// A `List` on macOS draws selection in the *system* accent — whatever the
    /// user chose in Appearance settings — and neither the app's AccentColor
    /// asset nor a SwiftUI `tint` reaches it. Drawing the row background here
    /// is what keeps the sidebar the same colour as the rest of the app.
    func sidebarSelection(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? AnyShapeStyle(Color.brandBlue) : AnyShapeStyle(.clear))
    }

    @ViewBuilder
    var detail: some View {
        switch selection {
        case .library:
            LibraryView(selection: $selection, refresh: $triggerRefresh)
        case .games:
            GamesBrowserView(bottle: bottleVM.mainBottle)
        case .settings:
            GameSettingsView()
        case let .bottle(url):
            if let bottle = bottleVM.bottles.first(where: { $0.url == url }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            }
        }
    }

    var sortedBottles: [Bottle] {
        bottleVM.bottles.sorted()
    }

    /// The selected bottle, when one is selected.
    var selectedBottleURL: URL? {
        if case let .bottle(url) = selection { return url }
        return nil
    }

    /// A bottle-shaped view of the selection, for the pieces that only know
    /// about bottles.
    ///
    /// Writing `nil` is ignored on purpose: a `List` clears its selection when
    /// the highlighted row is something it does not own, and without this,
    /// clicking "Games" would be undone a frame later by the list reporting
    /// that no bottle is selected any more.
    var bottleSelection: Binding<URL?> {
        Binding(
            get: { selectedBottleURL },
            set: { newValue in
                if let newValue { selection = .bottle(newValue) }
            }
        )
    }
}

// MARK: - Process Close Confirmation

extension ContentView {
    @MainActor
    func showProcessCloseAlert(for bottle: Bottle) {
        let checkbox = NSButton(
            checkboxWithTitle: String(localized: "bottle.close.remember"),
            target: nil,
            action: nil
        )
        let alert = NSAlert()
        alert.messageText = String(localized: "bottle.close.confirm.title")
        alert.informativeText = String(localized: "bottle.close.confirm.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "bottle.close.keepRunning"))
        let stopButton = alert.addButton(withTitle: String(localized: "bottle.close.stopBottle"))
        stopButton.hasDestructiveAction = true
        alert.accessoryView = checkbox

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Keep Running (default)
            if checkbox.state == .on {
                bottle.settings.closeWithProcessesPolicy = .alwaysKeepRunning
            }
        } else if response == .alertSecondButtonReturn {
            // Stop Bottle
            if checkbox.state == .on {
                bottle.settings.closeWithProcessesPolicy = .alwaysStop
            }
            Wine.killBottle(bottle: bottle)
            ProcessRegistry.shared.clearRegistry(for: bottle.url)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
        .environmentObject(AppSettings.shared)
}

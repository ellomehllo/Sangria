//
//  GamesBrowserRows.swift
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

import SwiftUI
import WhiskyKit

/// One file or folder.
struct GamesRow: View {
    let entry: GamesEntry
    let isStarting: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(entry.isExecutable ? AnyShapeStyle(Color.brandBlue) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text(entry.name)
            Spacer()
            if isStarting {
                ProgressView()
                    .controlSize(.small)
            } else if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isInstaller { return "shippingbox" }
        if entry.isExecutable { return "gamecontroller.fill" }
        return "doc"
    }

    private var detail: String? {
        guard !entry.isDirectory, let size = entry.size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// What an installer left behind, offered as shortcuts.
struct InstalledGamesSheet: View {
    let games: [GamesEntry]
    let add: ([GamesEntry]) -> Void

    @State private var selected: Set<URL> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(games) { game in
                Toggle(isOn: binding(for: game)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.url.deletingPathExtension().lastPathComponent)
                        Text(game.url.deletingLastPathComponent().lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("games.installed.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("games.addToLibrary") {
                        add(games.filter { selected.contains($0.url) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .frame(width: ViewWidth.medium, height: 320)
        .onAppear {
            // Everything ticked: the user just ran an installer, so adding
            // what it produced is the expected answer, not a decision.
            selected = Set(games.map(\.url))
        }
    }

    private func binding(for game: GamesEntry) -> Binding<Bool> {
        Binding(
            get: { selected.contains(game.url) },
            set: { isOn in
                if isOn {
                    selected.insert(game.url)
                } else {
                    selected.remove(game.url)
                }
            }
        )
    }
}

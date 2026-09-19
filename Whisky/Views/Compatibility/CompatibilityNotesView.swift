//
//  CompatibilityNotesView.swift
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

/// The personal compatibility database: every title tested, on which backend,
/// and how it went, grouped by title so backends compare side by side.
struct CompatibilityNotesView: View {
    static let windowID = "compatibility-notes"

    @ObservedObject private var store = CompatibilityNotesStore.shared
    @State private var search = ""
    @State private var statusFilter: CompatibilityStatus?
    @State private var backendFilter: GraphicsBackend?
    @State private var editing: CompatibilityNoteEditorItem?

    private var filteredGroups: [(title: String, notes: [CompatibilityNote])] {
        store.database.groupedByTitle().compactMap { group in
            let notes = group.notes.filter { note in
                (statusFilter == nil || note.status == statusFilter)
                    && (backendFilter == nil || note.backend == backendFilter)
                    && (search.isEmpty
                        || note.title.localizedCaseInsensitiveContains(search)
                        || note.notes.localizedCaseInsensitiveContains(search))
            }
            return notes.isEmpty ? nil : (group.title, notes)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.saveError {
                Label("Couldn't save notes: \(error)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1))
            }
            if store.database.notes.isEmpty {
                ContentUnavailableView {
                    Label("No Compatibility Notes Yet", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Test a program, then add a note from its page, or click + to add one by hand.")
                } actions: {
                    Button("Add Note") { addNote() }
                }
            } else if filteredGroups.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(filteredGroups, id: \.title) { group in
                        Section {
                            ForEach(group.notes) { note in
                                CompatibilityNoteRow(note: note, isFastest: isFastest(note, in: group.notes))
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { editing = .init(note: note, isNew: false) }
                                    .contextMenu { contextMenu(for: note) }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Compatibility Notes")
        .searchable(text: $search, placement: .toolbar, prompt: "Search titles and notes")
        .toolbar { toolbarContent }
        .sheet(item: $editing) { item in
            CompatibilityNoteEditor(
                item: item,
                onSave: { store.upsert($0) },
                onDelete: { store.remove(id: item.note.id) }
            )
        }
    }

    /// Marks the highest measured FPS in a title with at least two measured backends.
    private func isFastest(_ note: CompatibilityNote, in notes: [CompatibilityNote]) -> Bool {
        let measured = notes.compactMap(\.averageFPS)
        guard measured.count > 1, let fps = note.averageFPS else { return false }
        return fps == measured.max()
    }

    @ViewBuilder
    private func contextMenu(for note: CompatibilityNote) -> some View {
        Button("Edit…") { editing = .init(note: note, isNew: false) }
        Button("Duplicate for Another Backend…") {
            var copy = note
            copy.id = UUID()
            copy.lastTested = Date()
            copy.averageFPS = nil
            copy.backendVerification = nil
            editing = .init(note: copy, isNew: true)
        }
        Divider()
        Button("Delete", role: .destructive) { store.remove(id: note.id) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    Text("All Statuses").tag(CompatibilityStatus?.none)
                    ForEach(CompatibilityStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(CompatibilityStatus?.some(status))
                    }
                }
                Picker("Backend", selection: $backendFilter) {
                    Text("All Backends").tag(GraphicsBackend?.none)
                    ForEach(GraphicsBackend.concreteCases, id: \.self) { backend in
                        Text(backend.displayName).tag(GraphicsBackend?.some(backend))
                    }
                }
            } label: {
                Label("Filter", systemImage: statusFilter == nil && backendFilter == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
            }
            Menu {
                Button("Export as CSV…") { exportCSV() }
                Button("Show JSON File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            Button {
                addNote()
            } label: {
                Label("Add Note", systemImage: "plus")
            }
        }
    }

    private func addNote() {
        editing = .init(note: CompatibilityNote(title: "", backend: .dxmt, status: .working), isNew: true)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Compatibility Notes.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(store.database.csv().utf8).write(to: url, options: .atomic)
    }
}

/// One test result.
struct CompatibilityNoteRow: View {
    let note: CompatibilityNote
    var isFastest = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(note.backend.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(note.backend.tint.opacity(0.18), in: Capsule())
                .foregroundStyle(note.backend.tint)
                .frame(width: 80, alignment: .leading)
            Label(note.status.displayName, systemImage: note.status.symbol)
                .foregroundStyle(note.status.tint)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let fps = note.averageFPS {
                        Text("\(fps, specifier: "%.0f") fps")
                            .monospacedDigit()
                            .fontWeight(isFastest ? .semibold : .regular)
                        if isFastest {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .help("Fastest measured backend for this title")
                        }
                    }
                    if let api = note.graphicsAPI {
                        Text(api).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                if !note.notes.isEmpty {
                    Text(note.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(note.lastTested, format: .dateTime.day().month().year())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

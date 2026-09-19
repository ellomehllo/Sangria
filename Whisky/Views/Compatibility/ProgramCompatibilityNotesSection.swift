//
//  ProgramCompatibilityNotesSection.swift
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

/// This program's entries in the compatibility database, with a one-click
/// note prefilled from its last run.
struct ProgramCompatibilityNotesSection: View {
    @ObservedObject var program: Program
    @Binding var isExpanded: Bool

    @ObservedObject private var store = CompatibilityNotesStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var editing: CompatibilityNoteEditorItem?

    var body: some View {
        Section(isExpanded: $isExpanded) {
            let notes = store.notes(for: program)
            if notes.isEmpty {
                Text("No notes for this program yet. After a test run, record how it went.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                CompatibilityNoteRow(note: note)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = .init(note: note, isNew: false) }
            }
            HStack {
                Button("Add Note from Last Run…") {
                    editing = .init(note: .draft(for: program), isNew: true)
                }
                Spacer()
                Button("Open Compatibility Notes") {
                    openWindow(id: CompatibilityNotesView.windowID)
                }
            }
        } header: {
            Text("Compatibility Notes")
        }
        .sheet(item: $editing) { item in
            CompatibilityNoteEditor(
                item: item,
                onSave: { store.upsert($0) },
                onDelete: { store.remove(id: item.note.id) }
            )
        }
    }
}

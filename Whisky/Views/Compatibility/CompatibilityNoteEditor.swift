//
//  CompatibilityNoteEditor.swift
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

/// What the editor sheet is editing: an existing note or a new draft.
struct CompatibilityNoteEditorItem: Identifiable {
    let note: CompatibilityNote
    let isNew: Bool
    var id: UUID { note.id }
}

/// Creates or edits one compatibility note.
struct CompatibilityNoteEditor: View {
    let isNew: Bool
    let onSave: (CompatibilityNote) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var note: CompatibilityNote
    @State private var fpsText: String

    init(
        item: CompatibilityNoteEditorItem,
        onSave: @escaping (CompatibilityNote) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.isNew = item.isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _note = State(initialValue: item.note)
        _fpsText = State(initialValue: item.note.averageFPS.map { String(format: "%g", $0) } ?? "")
    }

    private var parsedFPS: Double?? {
        let trimmed = fpsText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value >= 0 else {
            return nil
        }
        return .some(value)
    }

    private var canSave: Bool {
        !note.title.trimmingCharacters(in: .whitespaces).isEmpty && parsedFPS != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $note.title)
                    Picker("Backend", selection: $note.backend) {
                        ForEach(GraphicsBackend.concreteCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    Picker("Status", selection: $note.status) {
                        ForEach(CompatibilityStatus.allCases, id: \.self) { status in
                            Label(status.displayName, systemImage: status.symbol).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Last tested", selection: $note.lastTested)
                }
                Section {
                    TextField("Average FPS", text: $fpsText, prompt: Text("Optional, e.g. 58"))
                    if parsedFPS == nil {
                        Text("Enter a number, or leave it empty.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("Graphics API", text: Binding(
                        get: { note.graphicsAPI ?? "" },
                        set: { note.graphicsAPI = $0.isEmpty ? nil : $0 }
                    ), prompt: Text("e.g. Direct3D 11"))
                }
                Section("Notes") {
                    TextEditor(text: $note.notes)
                        .font(.body)
                        .frame(minHeight: 100)
                }
                if note.bottleName != nil || note.programPath != nil || note.backendVerification != nil {
                    Section("Recorded from the app") {
                        if let bottle = note.bottleName {
                            LabeledContent("Bottle", value: bottle)
                        }
                        if let path = note.programPath {
                            LabeledContent("Executable") {
                                Text(path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            }
                        }
                        if let verification = note.backendVerification {
                            LabeledContent("Backend check") {
                                Text(verification).font(.caption)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let onDelete, !isNew {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Note" : "Save") {
                    var saved = note
                    saved.title = saved.title.trimmingCharacters(in: .whitespaces)
                    saved.averageFPS = parsedFPS ?? nil
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 520)
    }
}

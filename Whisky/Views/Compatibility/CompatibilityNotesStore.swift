//
//  CompatibilityNotesStore.swift
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

import Foundation
import SwiftUI
import WhiskyKit

/// The app's single copy of the compatibility database. Every edit is saved
/// to disk immediately, so the window and the program pages never disagree.
@MainActor
final class CompatibilityNotesStore: ObservableObject {
    static let shared = CompatibilityNotesStore()

    @Published private(set) var database: CompatibilityDatabase
    /// The last save failure, shown in the notes window until a save succeeds.
    @Published private(set) var saveError: String?

    let fileURL: URL

    init(fileURL: URL = CompatibilityDatabase.defaultURL) {
        self.fileURL = fileURL
        self.database = CompatibilityDatabase.load(from: fileURL)
    }

    func upsert(_ note: CompatibilityNote) {
        database.upsert(note)
        save()
    }

    func remove(id: UUID) {
        database.remove(id: id)
        save()
    }

    func notes(for program: Program) -> [CompatibilityNote] {
        database.notes(forProgramPath: program.url.path(percentEncoded: false))
    }

    private func save() {
        do {
            try database.save(to: fileURL)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

extension CompatibilityNote {
    /// A new note prefilled from what the app knows about a program's last run.
    @MainActor
    static func draft(for program: Program) -> CompatibilityNote {
        let lastRun = RunLogStore.load(for: program.name, in: program.bottle.url)
            .entries.max { $0.startTime < $1.startTime }
        let preview = Wine.previewGraphics(
            for: program.url,
            bottleBackend: program.bottle.settings.graphicsBackend,
            programBackend: program.settings.overrides?.graphicsBackend
        )
        let backend = lastRun?.graphicsBackend ?? preview.decision.backend
        let verification = lastRun.flatMap { run -> String? in
            guard let ran = run.graphicsBackend else { return nil }
            return GraphicsLogInspector.verify(
                expected: ran,
                since: run.startTime,
                programURL: program.url,
                bottleURL: program.bottle.url,
                loggingEnabled: run.graphicsLoggingEnabled ?? false
            ).summary
        }
        let measuredFPS = lastRun.flatMap { run -> Double? in
            guard run.frameRateMeasured == true else { return nil }
            let fps = MetalHUDLog.measurement(inLogAt: Wine.logsFolder.appending(path: run.logFileName))?.averageFPS
            return fps.map { ($0 * 10).rounded() / 10 }
        }
        return CompatibilityNote(
            title: program.url.deletingPathExtension().lastPathComponent,
            backend: backend,
            status: .working,
            lastTested: lastRun?.startTime ?? Date(),
            averageFPS: measuredFPS,
            graphicsAPI: preview.profile?.summary,
            bottleName: program.bottle.settings.name,
            programPath: program.url.path(percentEncoded: false),
            backendVerification: verification
        )
    }
}

extension GraphicsBackend {
    /// The backends a test can actually have run on.
    static var concreteCases: [GraphicsBackend] {
        allCases.filter { $0 != .recommended }
    }

    /// A stable tint per backend for badges.
    var tint: Color {
        switch self {
        case .dxmt: .purple
        case .d3dMetal: .green
        case .dxvk: .blue
        case .wined3d: .orange
        case .recommended: .gray
        }
    }
}

extension CompatibilityStatus {
    var tint: Color {
        switch self {
        case .working: .green
        case .partial: .orange
        case .broken: .red
        }
    }

    var symbol: String {
        switch self {
        case .working: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .broken: "xmark.octagon.fill"
        }
    }
}

//
//  BottleVM.swift
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
import os.log
import SemanticVersion
import WhiskyKit

// MARK: - Bottle Creation Errors

enum BottleCreationError: LocalizedError, Equatable {
    case directoryCreationFailed
    case metadataCreationFailed
    case wineVersionChangeFailed
    case persistenceSaveFailed
    /// The Wine runtime (WhiskyWine) is not installed, so the prefix can't be
    /// initialized. Surfaced with a "Run Setup" action in the failure alert.
    case runtimeMissing
    /// The chosen location failed pre-flight validation. Carries the already
    /// localized, user-facing message (built at the throw site) since the alert
    /// displays `errorDescription` verbatim.
    case locationUnsuitable(message: String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            String(localized: "bottle.creation.error.directoryCreationFailed")
        case .metadataCreationFailed:
            String(localized: "bottle.creation.error.metadataCreationFailed")
        case .wineVersionChangeFailed:
            String(localized: "bottle.creation.error.wineVersionChangeFailed")
        case .persistenceSaveFailed:
            String(localized: "bottle.creation.error.persistenceSaveFailed")
        case .runtimeMissing:
            String(localized: "bottle.creation.error.runtimeMissing")
        case let .locationUnsuitable(message):
            message
        }
    }
}

/// Why a bottle location was refused, phrased for the user, or `nil` when it is
/// usable. Shared so the creation sheet and the failure alert cannot drift.
func bottleLocationRefusal(_ result: BottleLocationValidation.ValidationResult) -> String? {
    switch result {
    case .valid:
        nil
    case let .notWritable(path):
        String(format: String(localized: "bottle.creation.preflight.notWritable"), path)
    case let .accessDenied(path):
        String(format: String(localized: "bottle.creation.preflight.accessDenied"), path)
    case let .insufficientSpace(available, required):
        String(
            format: String(localized: "bottle.creation.preflight.insufficientSpace"),
            ByteCountFormatter.string(fromByteCount: available, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
        )
    }
}

private let bottleVMLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.franke.Whisky",
    category: "BottleVM"
)

@MainActor
final class BottleVM: ObservableObject {
    static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []
    @Published var bottleCreationAlert: BottleCreationAlert?

    struct BottleCreationAlert: Identifiable {
        let id = UUID()
        let message: String
        let diagnostics: String
        /// When true the alert offers a "Run Setup" action so the user can
        /// install the missing Wine runtime directly.
        let isRuntimeMissing: Bool
    }

    /// The bottle casual mode runs everything in, or `nil` when there is none.
    ///
    /// Recomputed on load rather than on every read: choosing it stats the
    /// filesystem once per bottle, and this is read from view bodies.
    @Published private(set) var mainBottleURL: URL?

    /// Guards ``ensureMainBottleExists()`` so a slow first creation cannot be
    /// started twice by two passes of the same startup.
    var isCreatingFirstBottle = false

    func loadBottles() {
        // Keep the live instance for any bottle that is mid-operation:
        // rebuilding it would reset inFlight and drop the guard that blocks
        // conflicting actions during move/export/duplicate.
        let inFlight = Dictionary(bottles.filter(\.inFlight).map { ($0.url, $0) }) { first, _ in first }
        bottles = bottlesList.loadBottles().map { inFlight[$0.url] ?? $0 }
        mainBottleURL = chosenMainBottleURL()
        migrateShortcutsToRelativePaths()
    }

    /// Bottles found on disk with no registry entry, awaiting a re-import
    /// decision from the user (issue #145). Non-empty drives the recovery
    /// alert in ContentView.
    @Published var orphanedBottles: [BottleData.OrphanedBottle] = []

    /// Scans the default bottles directory for bottle folders the registry
    /// doesn't know about — pre-#136 creations, a reset registry, or a
    /// restored Bottles/ backup.
    func scanForOrphanedBottles() {
        orphanedBottles = bottlesList.orphanedBottles()
    }

    func reimportOrphanedBottles() {
        for orphan in orphanedBottles where !bottlesList.registerBottlePath(orphan.url) {
            bottleVMLogger.error(
                "Failed to re-register orphaned bottle at \(orphan.url.path(percentEncoded: false), privacy: .public)"
            )
        }
        orphanedBottles = []
        loadBottles()
    }

    func countActive() -> Int {
        bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        let request = BottleCreationRequest(
            bottleName: bottleName,
            winVersion: winVersion,
            bottleURL: bottleURL,
            newBottleDir: newBottleDir
        )
        Task {
            await self.createBottleTask(request: request)
        }
        return newBottleDir
    }

    private struct BottleCreationRequest {
        let bottleName: String
        let winVersion: WinVersion
        let bottleURL: URL
        let newBottleDir: URL
    }

    private func createBottleTask(request: BottleCreationRequest) async {
        var bottle: Bottle?
        do {
            // The Wine runtime is required to initialize the prefix; fail fast
            // with an actionable error instead of a low-level file-not-found
            // failure from the wine invocation (issue #61).
            guard WhiskyWineInstaller.isWhiskyWineInstalled() else {
                throw BottleCreationError.runtimeMissing
            }

            // Pre-flight the chosen location before creating anything, so an
            // unwritable or near-full destination surfaces a clear error up
            // front instead of a cryptic late wineboot failure (issue #61).
            if let refusal = bottleLocationRefusal(BottleLocationValidation.validate(at: request.bottleURL)) {
                throw BottleCreationError.locationUnsuitable(message: refusal)
            }

            try createBottleDirectory(at: request.newBottleDir)

            // Create bottle on main actor (since Bottle is @MainActor)
            let createdBottle = Bottle(bottleUrl: request.newBottleDir, inFlight: true)
            bottle = createdBottle
            bottles.append(createdBottle)

            // Configure bottle settings (all on MainActor)
            createdBottle.settings.windowsVersion = request.winVersion
            createdBottle.settings.name = request.bottleName
            // DXMT is this build's default backend. It is set explicitly, not
            // left on Recommended, so the picker shows what the bottle runs;
            // a runtime without a usable DXMT payload keeps Recommended.
            createdBottle.settings.graphicsBackend = GraphicsBackendResolver.defaultForNewBottle()

            // Wine operations are async and can run on background threads
            try await Wine.changeWinVersion(bottle: createdBottle, win: request.winVersion)
            let wineVer = try await Wine.wineVersion()
            createdBottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

            // Bootstrap host fonts so Unity titles render fallback glyphs correctly.
            BottleFontBootstrap.copySystemFonts(toPrefix: createdBottle.url)

            // Save settings
            createdBottle.saveBottleSettings()

            try persistBottleCreation(request: request)
            // Reload while the bottle is still in flight so the reload keeps
            // this instance. Reloading after clearing the flag replaced it,
            // and the selected bottle page kept writing to the old one: its
            // first pin never reached the library, the Dock menu, or the menu
            // bar extra until the next reload.
            loadBottles()
            createdBottle.isAvailable = true
            createdBottle.inFlight = false
            Telemetry.capture(.firstBottleCreated)
        } catch {
            handleBottleCreationFailure(error, request: request, bottle: bottle)
        }
    }

    private func createBottleDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw BottleCreationError.directoryCreationFailed
        }
    }

    private func persistBottleCreation(request: BottleCreationRequest) throws {
        // registerBottlePath verifies the entries file on disk actually
        // contains the new path; a silent save failure here used to make the
        // bottle vanish on the next launch with no explanation (issue #61).
        guard bottlesList.registerBottlePath(request.newBottleDir) else {
            throw BottleCreationError.persistenceSaveFailed
        }
    }

    private func handleBottleCreationFailure(
        _ error: Error,
        request: BottleCreationRequest,
        bottle: Bottle?
    ) {
        let message = error.localizedDescription
        let diagnostics = makeBottleCreationDiagnostics(
            bottleName: request.bottleName,
            winVersion: request.winVersion,
            bottleURL: request.bottleURL,
            newBottleDir: request.newBottleDir,
            error: error
        )
        bottleVMLogger.error("Failed to create new bottle: \(message)")
        bottleVMLogger.error("\(diagnostics, privacy: .public)")
        bottleCreationAlert = BottleCreationAlert(
            message: message,
            diagnostics: diagnostics,
            isRuntimeMissing: (error as? BottleCreationError) == .runtimeMissing
        )

        // Clean up on failure
        if let bottle, let index = bottles.firstIndex(of: bottle) {
            bottles.remove(at: index)
        }
        try? FileManager.default.removeItem(at: request.newBottleDir)
    }
}

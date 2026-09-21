//
//  GameSettingsView.swift
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

/// One set of switches for every game.
///
/// A casual player has one library, so they get one set of settings rather
/// than a copy per game and another per prefix. Anything that mentions Wine
/// lives at the bottom, behind Developer Mode, which is the only place in the
/// whole interface that says the words bottle, terminal or winetricks.
struct GameSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var bottleVM: BottleVM

    /// The bottle everything runs in, which is what the settings are written
    /// onto and what Storage reports on.
    var mainBottle: Bottle? { bottleVM.mainBottle }

    @State private var usedBytes: Int64?

    var body: some View {
        Form {
            general
            display
            performance
            storage
            advanced
            if settings.developerMode {
                DeveloperSettingsSection()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.title")
        .task(id: mainBottle?.url) {
            await measureStorage()
        }
    }

    // MARK: - General

    private var general: some View {
        Section("settings.general") {
            Picker("settings.theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .accessibilityIdentifier("settings.theme")
            Toggle("settings.automaticUpdates", isOn: $settings.automaticUpdates)
            Toggle("settings.quitGamesOnExit", isOn: $settings.quitGamesOnExit)
        }
    }

    // MARK: - Display

    private var display: some View {
        Section("settings.display") {
            captioned("settings.startFullscreen", "settings.startFullscreen.caption") {
                Toggle("", isOn: writeThrough($settings.startFullscreen))
                    .labelsHidden()
            }
            captioned("settings.retina", "settings.retina.caption") {
                Toggle("", isOn: Binding(
                    get: { settings.retinaMode },
                    set: { newValue in
                        settings.retinaMode = newValue
                        guard let bottle = mainBottle else { return }
                        Task { await GameDefaults.applyRetinaMode(settings, to: bottle) }
                    }
                ))
                .labelsHidden()
            }
            captioned("settings.fpsOverlay", "settings.fpsOverlay.caption") {
                Toggle("", isOn: writeThrough($settings.showFPSOverlay))
                    .labelsHidden()
            }
        }
    }

    // MARK: - Performance

    private var performance: some View {
        Section("settings.performance") {
            captioned("settings.metalFX", "settings.metalFX.caption") {
                Toggle("", isOn: writeThrough($settings.metalFXUpscaling))
                    .labelsHidden()
            }
            captioned("settings.sync", "settings.sync.caption") {
                Toggle("", isOn: writeThrough($settings.syncOptimization))
                    .labelsHidden()
            }
            captioned("settings.background", "settings.background.caption") {
                Toggle("", isOn: writeThrough($settings.limitBackgroundActivity))
                    .labelsHidden()
            }
        }
    }

    // MARK: - Storage

    private var storage: some View {
        Section("settings.storage") {
            LabeledContent("settings.storage.location") {
                Text(GamesRoot.displayRoot)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("settings.storage.used") {
                if let usedBytes {
                    Text(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Button("settings.storage.reveal") {
                guard let root = gamesRoot else { return }
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.url.path(percentEncoded: false))
            }
            .disabled(gamesRoot == nil)
            .accessibilityIdentifier("settings.revealGames")
        }
    }

    // MARK: - Advanced

    private var advanced: some View {
        Section("settings.advanced") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("settings.developerMode", isOn: $settings.developerMode)
                    .accessibilityIdentifier("settings.developerMode")
                Text("settings.developerMode.warning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var gamesRoot: GamesRoot? {
        mainBottle.map { GamesRoot(bottleURL: $0.url) }
    }

    /// A row whose control sits on the right and whose explanation sits under
    /// the title, because half of these switches are meaningless without one.
    @ViewBuilder
    private func captioned(
        _ title: LocalizedStringKey,
        _ caption: LocalizedStringKey,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    /// Wraps a switch so that changing it also writes the value onto the
    /// bottle everything runs in.
    private func writeThrough(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                guard let bottle = mainBottle else { return }
                GameDefaults.apply(settings, to: bottle)
            }
        )
    }

    private func measureStorage() async {
        guard let root = gamesRoot else {
            usedBytes = nil
            return
        }
        usedBytes = nil
        // Off the main actor: this walks every file under the Games folder,
        // and on a drive holding Metro Exodus that is not instant.
        usedBytes = await Task.detached { root.usedBytes() }.value
    }
}

#Preview {
    GameSettingsView()
        .environmentObject(AppSettings.shared)
        .environmentObject(BottleVM.shared)
}

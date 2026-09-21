//
//  DeveloperSettingsSection.swift
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

/// The settings that only make sense once you know what Wine is.
///
/// Every row here was in the Settings window before this refactor; none of it
/// was removed, it just stopped being the first thing a new player sees. The
/// terminal picker in particular is the reason this section is gated: naming a
/// terminal app is not a question anyone should be asked in order to play a
/// game.
struct DeveloperSettingsSection: View {
    @AppStorage("defaultBottleLocation") private var defaultBottleLocation = BottleData.defaultBottleDir
    @AppStorage("preferredTerminal") private var preferredTerminal = "terminal"
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @AppStorage(Telemetry.consentDefaultsKey) private var telemetryConsentRaw: String = Telemetry.ConsentState
        .undecided.rawValue

    /// Mirrors the setup-flow opt-in; writing records the explicit choice.
    private var telemetryOptIn: Binding<Bool> {
        Binding(
            get: { telemetryConsentRaw == Telemetry.ConsentState.granted.rawValue },
            set: { Telemetry.setConsent(granted: $0) }
        )
    }

    var body: some View {
        Section("settings.developer") {
            Toggle("settings.toggle.menubar", isOn: $showMenuBarExtra)
                .help("settings.toggle.menubar.help")
            Picker("settings.terminal", selection: $preferredTerminal) {
                // installedTerminals should always include Terminal.app on macOS,
                // but fall back to showing just Terminal if somehow empty
                let terminals = TerminalApp.installedTerminals
                ForEach(terminals.isEmpty ? [.terminal] : terminals) { terminal in
                    Text(terminal.displayName).tag(terminal.rawValue)
                }
            }
            ActionView(
                text: "settings.path",
                subtitle: defaultBottleLocation.prettyPath(),
                actionName: "create.browse"
            ) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.directoryURL = BottleData.containerDir
                panel.begin { result in
                    if result == .OK, let url = panel.urls.first {
                        defaultBottleLocation = url
                    }
                }
            }
        }
        GPTKSettingsSection()
        Section("settings.privacy") {
            Toggle("settings.toggle.telemetry", isOn: telemetryOptIn)
                .help("setup.telemetry.consent.help")
        }
    }
}

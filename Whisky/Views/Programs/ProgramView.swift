//
//  ProgramView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

struct ProgramView: View {
    @ObservedObject var program: Program
    @State private var programLoading: Bool = false
    @State private var cachedIconImage: Image?
    @State private var toast: ToastData?
    @State private var showTroubleshootingWizard: Bool = false
    @State private var hasActiveSession: Bool = false
    @AppStorage("configSectionExapnded") private var configSectionExpanded: Bool = true
    @AppStorage("envArgsSectionExpanded") private var envArgsSectionExpanded: Bool = true
    @AppStorage("overridesSectionExpanded") private var overridesSectionExpanded: Bool = false
    @AppStorage("consoleRunsSectionExpanded") private var consoleRunsSectionExpanded: Bool = false
    @AppStorage("graphicsSectionExpanded") private var graphicsSectionExpanded: Bool = true
    @AppStorage("graphicsDebugSectionExpanded") private var graphicsDebugSectionExpanded: Bool = false
    @AppStorage("compatibilityNotesSectionExpanded") private var compatibilityNotesSectionExpanded: Bool = true
    @State private var selectedRunId: UUID?
    /// A launch the graphics API check refused, awaiting the user's choice.
    @State private var apiRefusal: GraphicsAPIRefusal?

    private let sessionStore = TroubleshootingSessionStore()

    var body: some View {
        Form {
            if hasActiveSession {
                TroubleshootingEntryBanner(bannerType: .resumeSession) {
                    showTroubleshootingWizard = true
                }
            }
            Section("program.config", isExpanded: $configSectionExpanded) {
                Picker("locale.title", selection: $program.settings.locale) {
                    ForEach(Locales.allCases, id: \.self) { locale in
                        Text(locale.pretty()).id(locale)
                    }
                }
                VStack {
                    HStack {
                        Text("program.args")
                        Spacer()
                    }
                    TextField("program.args", text: $program.settings.arguments)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .labelsHidden()
                }
            }
            EnvironmentArgView(program: program, isExpanded: $envArgsSectionExpanded)
            ProgramGraphicsSection(program: program, isExpanded: $graphicsSectionExpanded)
            ProgramOverrideSettingsView(
                bottle: program.bottle,
                program: program,
                isExpanded: $overridesSectionExpanded
            )
            ProgramGraphicsDebugSection(program: program, isExpanded: $graphicsDebugSectionExpanded) { capture in
                launchProgram(frameCapture: capture)
            }
            ProgramCompatibilityNotesSection(program: program, isExpanded: $compatibilityNotesSectionExpanded)
            Section("console.title", isExpanded: $consoleRunsSectionExpanded) {
                ConsoleRunHistoryView(
                    program: program,
                    bottle: program.bottle,
                    selectedRunId: $selectedRunId
                )
                if let runId = selectedRunId,
                   let entry = findRunEntry(id: runId) {
                    ConsoleLogView(runEntry: entry, bottle: program.bottle)
                }
            }
        }
        .sheet(isPresented: $showTroubleshootingWizard) {
            TroubleshootingWizardView(
                bottle: program.bottle,
                program: program,
                entryContext: .program(programURL: program.url, bottleURL: program.bottle.url)
            )
        }
        .bottomBar {
            HStack {
                Spacer()
                Button(String(localized: "troubleshooting.entry.troubleshoot")) {
                    showTroubleshootingWizard = true
                }
                Button("button.showInFinder") {
                    NSWorkspace.shared.activateFileViewerSelecting([program.url])
                }
                Button("button.createShortcut") {
                    let panel = NSSavePanel()
                    let applicationDir = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)[0]
                    let name = program.name.replacingOccurrences(of: ".exe", with: "")
                    panel.directoryURL = applicationDir
                    panel.canCreateDirectories = true
                    panel.allowedContentTypes = [UTType.applicationBundle]
                    panel.allowsOtherFileTypes = false
                    panel.isExtensionHidden = true
                    panel.nameFieldStringValue = name + ".app"
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.url {
                                let name = url.deletingPathExtension().lastPathComponent
                                Task(priority: .userInitiated) {
                                    await ProgramShortcut.createShortcut(program, app: url, name: name)
                                }
                            }
                        }
                    }
                }
                Button("button.run") {
                    launchProgram()
                }
                .disabled(programLoading)
                if programLoading {
                    Spacer()
                        .frame(width: 10)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
        }
        .toast($toast)
        .alert(
            apiRefusal?.title ?? "",
            isPresented: Binding(get: { apiRefusal != nil }, set: { if !$0 { apiRefusal = nil } }),
            presenting: apiRefusal
        ) { refusal in
            if let suggestion = refusal.suggestion {
                Button("Use \(suggestion.displayName) for This Program") {
                    var overrides = program.settings.overrides ?? ProgramOverrides()
                    overrides.graphicsBackend = suggestion
                    program.settings.overrides = overrides
                    launchProgram(frameCapture: refusal.frameCapture)
                }
            }
            Button("Launch Anyway") {
                launchProgram(frameCapture: refusal.frameCapture, skipGraphicsAPICheck: true)
            }
            Button("Always Launch This Program Anyway") {
                program.settings.allowUnsupportedGraphicsAPI = true
                launchProgram(frameCapture: refusal.frameCapture)
            }
            Button("Cancel", role: .cancel) {}
        } message: { refusal in
            Text(refusal.message)
        }
        .toolbar {
            if let image = cachedIconImage {
                ToolbarItem(id: "ProgramViewIcon", placement: .navigation) {
                    image
                        .resizable()
                        .frame(width: 25, height: 25)
                        .padding(.trailing, 5)
                }
            } else {
                ToolbarItem(id: "ProgramViewIcon", placement: .navigation) {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .padding(.trailing, 5)
                }
            }
        }
        .navigationTitle(program.name)
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: configSectionExpanded)
        .animation(.whiskyDefault, value: envArgsSectionExpanded)
        .animation(.whiskyDefault, value: overridesSectionExpanded)
        .animation(.whiskyDefault, value: consoleRunsSectionExpanded)
        .animation(.whiskyDefault, value: graphicsSectionExpanded)
        .animation(.whiskyDefault, value: graphicsDebugSectionExpanded)
        .animation(.whiskyDefault, value: compatibilityNotesSectionExpanded)
        .task {
            let icon = await IconCache.shared.iconOrFallback(for: program.url, peFile: program.peFile)
            self.cachedIconImage = Image(nsImage: icon)
        }
        .onAppear {
            hasActiveSession = sessionStore.hasActiveSession(for: program.bottle.url)
        }
    }

    private func findRunEntry(id: UUID) -> RunLogEntry? {
        let history = RunLogStore.load(for: program.name, in: program.bottle.url)
        return history.entries.first(where: { $0.id == id })
    }

    private func launchProgram(frameCapture: FrameCaptureRequest? = nil, skipGraphicsAPICheck: Bool = false) {
        // Capture modifier flags synchronously before entering async context
        let useTerminal = NSEvent.modifierFlags.contains(.shift) && frameCapture == nil

        // Ask before launching into a backend that cannot render this program
        // (Direct3D 12 on DXMT), rather than letting it crash or show nothing.
        if !useTerminal, !skipGraphicsAPICheck, program.settings.allowUnsupportedGraphicsAPI != true {
            let preview = Wine.previewGraphics(
                for: program.url,
                bottleBackend: program.bottle.settings.graphicsBackend,
                programBackend: program.settings.overrides?.graphicsBackend
            )
            if preview.assessment.isUnsupported, let message = preview.assessment.message {
                apiRefusal = GraphicsAPIRefusal(
                    backend: preview.decision.backend,
                    api: preview.profile?.primaryAPI,
                    message: message,
                    suggestion: preview.assessment.suggestion,
                    frameCapture: frameCapture
                )
                return
            }
        }

        programLoading = true
        Telemetry.capture(.firstProgramLaunchAttempted)
        Task {
            let result = await program.launchWithUserMode(
                useTerminal: useTerminal,
                frameCapture: frameCapture,
                skipGraphicsAPICheck: skipGraphicsAPICheck
            )
            withAnimation {
                toast = launchToast(for: result, frameCapture: frameCapture)
            }
            programLoading = false
        }
    }

    /// The launch toast, naming the backend the launch actually used.
    private func launchToast(for result: LaunchResult, frameCapture: FrameCaptureRequest?) -> ToastData {
        guard case let .launchedSuccessfully(name) = result,
              let decision = program.lastBackendDecision
        else { return result.toastData }
        var message = "Launched \(name) on \(decision.backend.displayName)"
        if frameCapture != nil {
            message += ". Frame capture armed: press F10 in the game"
        }
        return ToastData(message: message, style: .success, autoDismiss: frameCapture == nil)
    }
}

/// A launch the graphics API check refused, held for the confirmation alert.
private struct GraphicsAPIRefusal {
    let backend: GraphicsBackend
    let api: GraphicsAPI?
    let message: String
    let suggestion: GraphicsBackend?
    let frameCapture: FrameCaptureRequest?

    var title: String {
        if let api {
            // DXMT is under active development; the others will not grow D3D12.
            let yet = backend == .dxmt ? " yet" : ""
            return "\(api.displayName) isn't supported by \(backend.displayName)\(yet)"
        }
        return "\(backend.displayName) can't run this program"
    }
}

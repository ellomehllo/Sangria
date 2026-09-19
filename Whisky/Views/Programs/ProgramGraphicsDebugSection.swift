//
//  ProgramGraphicsDebugSection.swift
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

/// Per-program graphics debugging: validation layers, DXMT/DXVK logs, and
/// DXMT's F10 frame capture, without setting environment variables by hand.
struct ProgramGraphicsDebugSection: View {
    @ObservedObject var program: Program
    @Binding var isExpanded: Bool
    /// Launches the program with frame capture armed.
    let launchWithCapture: (FrameCaptureRequest) -> Void

    @State private var captureTarget = ""
    @State private var autoCapture = false
    @State private var autoCaptureFrame = 300
    @State private var captures: [URL] = []
    @State private var nextBackend: GraphicsBackend?

    var body: some View {
        Section(isExpanded: $isExpanded) {
            Toggle(isOn: $program.settings.effectiveGraphicsDebug.writeGraphicsLogs) {
                VStack(alignment: .leading) {
                    Text("Write DXMT and DXVK logs")
                    Text("Per-program log files, shown below. Also how the Graphics section confirms the backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Picker("DXMT log level", selection: $program.settings.effectiveGraphicsDebug.dxmtLogLevel) {
                ForEach(DXMTLogLevel.allCases, id: \.self) { level in
                    Text(level == .dxmtDefault ? "\(level.rawValue) (default)" : level.rawValue).tag(level)
                }
            }
            Toggle(isOn: $program.settings.effectiveGraphicsDebug.measureFrameRate) {
                VStack(alignment: .leading) {
                    Text("Measure FPS with the Metal HUD")
                    Text("Shows Apple's performance HUD in the game and logs its frame counter. The Graphics " +
                        "section then reports the run's average FPS, on any backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $program.settings.effectiveGraphicsDebug.metalAPIValidation) {
                VStack(alignment: .leading) {
                    Text("Metal API validation")
                    Text("MTL_DEBUG_LAYER=1. Catches invalid Metal calls. Costs CPU time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $program.settings.effectiveGraphicsDebug.metalShaderValidation) {
                VStack(alignment: .leading) {
                    Text("Metal shader validation")
                    Text("MTL_SHADER_VALIDATION=1. Catches out-of-bounds GPU access. Very slow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            frameCaptureControls

            VStack(alignment: .leading, spacing: 6) {
                Text("Logs").font(.headline)
                GraphicsLogViewer(programURL: program.url, bottleURL: program.bottle.url)
            }
        } header: {
            Text("Graphics Debug")
        }
        .task(id: program.settings.overrides?.graphicsBackend) {
            if captureTarget.isEmpty {
                captureTarget = FrameCaptureRequest.defaultExecutableName(for: program.url)
            }
            let url = program.url
            let bottleBackend = program.bottle.settings.graphicsBackend
            let programBackend = program.settings.overrides?.graphicsBackend
            let found = await Task.detached(priority: .utility) {
                (
                    Wine.previewGraphics(for: url, bottleBackend: bottleBackend, programBackend: programBackend)
                        .decision.backend,
                    FrameCaptureLocator.captures(near: url)
                )
            }.value
            nextBackend = found.0
            captures = found.1
        }
    }

    // MARK: - Frame capture

    @ViewBuilder
    private var frameCaptureControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame capture").font(.headline)
            if let nextBackend, nextBackend != .dxmt {
                Label(
                    "Frame capture is a DXMT feature. This program launches on \(nextBackend.displayName).",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            LabeledContent("Capture executable") {
                TextField("Executable", text: $captureTarget, prompt: Text("Name without .exe"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            Text("The process that renders. For a launcher stub this is the real game, e.g. Game-Win64-Shipping.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Toggle("Capture automatically at frame", isOn: $autoCapture)
                TextField("Frame", value: $autoCaptureFrame, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .disabled(!autoCapture)
            }
            HStack {
                Button {
                    launchWithCapture(FrameCaptureRequest(
                        executableName: captureTarget.isEmpty
                            ? FrameCaptureRequest.defaultExecutableName(for: program.url)
                            : captureTarget,
                        automaticFrame: autoCapture ? max(1, autoCaptureFrame) : nil
                    ))
                } label: {
                    Label("Launch with Frame Capture", systemImage: "camera.metering.center.weighted")
                }
                .disabled(nextBackend != nil && nextBackend != .dxmt)
                Spacer()
                Button("Refresh Captures") {
                    captures = FrameCaptureLocator.captures(near: program.url)
                }
                .controlSize(.small)
            }
            Text(autoCapture
                ? "DXMT captures frame \(autoCaptureFrame) on its own and saves a .gputrace beside the executable."
                : "Once the game is running, press F10 in its window. The .gputrace lands beside the executable.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(captures.prefix(5), id: \.self) { capture in
                HStack {
                    Image(systemName: "doc.viewfinder")
                    Text(capture.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Open") { NSWorkspace.shared.open(capture) }
                        .help("Opens in Xcode's GPU debugger")
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([capture]) }
                }
                .controlSize(.small)
            }
        }
    }
}

/// Tails a program's DXMT and DXVK logs.
struct GraphicsLogViewer: View {
    let programURL: URL
    let bottleURL: URL

    @State private var files: [GraphicsLogInspector.LogFile] = []
    @State private var selection: URL?
    @State private var text = ""
    @State private var follow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Log file", selection: $selection) {
                    if files.isEmpty {
                        Text("No logs yet").tag(URL?.none)
                    }
                    ForEach(files) { file in
                        Text("\(file.backend.displayName): \(file.url.lastPathComponent)").tag(URL?.some(file.url))
                    }
                }
                .labelsHidden()
                Toggle("Follow", isOn: $follow)
                    .toggleStyle(.checkbox)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        GraphicsLogLocations.programDirectory(programURL: programURL, bottleURL: bottleURL)
                    ])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show log folder in Finder")
                .disabled(files.isEmpty)
                Button {
                    clearLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this program's graphics logs")
                .disabled(files.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(text.isEmpty ? "Logs appear here once the program creates a Direct3D device." : text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(text.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(6)
                }
                .frame(height: 220)
                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: text) {
                    if follow {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(follow ? 1 : 3))
            }
        }
    }

    private func refresh() {
        files = GraphicsLogInspector.logFiles(programURL: programURL, bottleURL: bottleURL)
        if selection == nil || !files.contains(where: { $0.url == selection }) {
            selection = files.first?.url
        }
        let newText = selection.map { GraphicsLogInspector.tail(of: $0) } ?? ""
        if newText != text {
            text = newText
        }
    }

    private func clearLogs() {
        for file in files {
            try? FileManager.default.removeItem(at: file.url)
        }
        selection = nil
        text = ""
        refresh()
    }
}

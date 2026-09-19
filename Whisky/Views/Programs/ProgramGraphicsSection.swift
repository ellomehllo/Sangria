//
//  ProgramGraphicsSection.swift
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

/// What will render this program, why, and what actually rendered it last time.
///
/// The "next launch" line comes from the same preview the launch path decides
/// with, and the "last run" line from the run history plus the log directories,
/// so the page never reports a backend the program is not running on.
struct ProgramGraphicsSection: View {
    @ObservedObject var program: Program
    @Binding var isExpanded: Bool

    @State private var preview: GraphicsLaunchPreview?
    @State private var lastRun: RunLogEntry?
    @State private var verification: BackendVerification?
    @State private var measurement: FrameRateMeasurement?
    /// The log size the measurement was taken at, so an unchanged log is not re-read.
    @State private var measuredLogSize: Int?

    /// Changes whenever something that feeds the decision changes.
    private var refreshKey: String {
        [
            program.bottle.settings.graphicsBackend.rawValue,
            program.settings.overrides?.graphicsBackend?.rawValue ?? "-",
            program.lastBackendDecision?.summary ?? "-"
        ].joined(separator: "|")
    }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            LabeledContent("Detected API") {
                if let preview {
                    Text(preview.profile?.summary ?? "Not a Windows executable")
                        .help("Read from the executable's import table. Engines that load Direct3D at " +
                            "runtime show as Not detected.")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            if let preview {
                LabeledContent("Next launch") {
                    VStack(alignment: .trailing, spacing: 2) {
                        BackendBadge(backend: preview.decision.backend)
                        Text(reasonText(preview.decision))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let message = preview.assessment.message {
                    assessmentBanner(message: message, assessment: preview.assessment)
                }
            }
            lastRunRows
        } header: {
            Text("Graphics")
        }
        .task(id: refreshKey) {
            await refreshPreview()
        }
        .task {
            // The logs appear when the program creates its device, which can
            // be well after launch, so keep checking while the page is open.
            while !Task.isCancelled {
                refreshLastRun()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var lastRunRows: some View {
        if let lastRun, let backend = lastRun.graphicsBackend {
            LabeledContent("Last run") {
                VStack(alignment: .trailing, spacing: 2) {
                    BackendBadge(backend: backend)
                    Text(lastRun.startTime, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let verification {
                Label {
                    Text(verification.summary).font(.caption)
                } icon: {
                    Image(systemName: verificationSymbol(verification))
                        .foregroundStyle(verificationTint(verification))
                }
            }
            if lastRun.frameRateMeasured == true {
                LabeledContent("Measured FPS") {
                    Text(measurement?.summary ?? "No HUD samples yet")
                        .monospacedDigit()
                        .foregroundStyle(measurement == nil ? .secondary : .primary)
                }
            }
        } else if lastRun != nil {
            LabeledContent("Last run", value: "Before backend tracking")
        }
    }

    private func assessmentBanner(message: String, assessment: BackendAPIAssessment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: assessment.isUnsupported ? "xmark.octagon.fill" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(assessment.isUnsupported ? .red : .orange)
            if let suggestion = assessment.suggestion {
                Button("Use \(suggestion.displayName) for This Program") {
                    var overrides = program.settings.overrides ?? ProgramOverrides()
                    overrides.graphicsBackend = suggestion
                    program.settings.overrides = overrides
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (assessment.isUnsupported ? Color.red : Color.orange).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func reasonText(_ decision: BackendDecision) -> String {
        decision.choice == .recommended
            ? "Recommended: \(decision.reason)"
            : decision.reason
    }

    private func verificationSymbol(_ verification: BackendVerification) -> String {
        switch verification {
        case .confirmed: "checkmark.seal.fill"
        case .mismatch: "exclamationmark.octagon.fill"
        case .noEvidence: "hourglass"
        case .notVerifiable, .loggingDisabled: "questionmark.circle"
        }
    }

    private func verificationTint(_ verification: BackendVerification) -> Color {
        switch verification {
        case .confirmed: .green
        case .mismatch: .red
        case .noEvidence: .orange
        case .notVerifiable, .loggingDisabled: .secondary
        }
    }

    // MARK: - Refresh

    private func refreshPreview() async {
        let url = program.url
        let bottleBackend = program.bottle.settings.graphicsBackend
        let programBackend = program.settings.overrides?.graphicsBackend
        preview = await Task.detached(priority: .userInitiated) {
            Wine.previewGraphics(for: url, bottleBackend: bottleBackend, programBackend: programBackend)
        }.value
        refreshLastRun()
    }

    private func refreshLastRun() {
        let run = RunLogStore.load(for: program.name, in: program.bottle.url)
            .entries.max { $0.startTime < $1.startTime }
        lastRun = run
        refreshMeasurement(for: run)
        guard let run, let backend = run.graphicsBackend else {
            verification = nil
            return
        }
        verification = GraphicsLogInspector.verify(
            expected: backend,
            since: run.startTime,
            programURL: program.url,
            bottleURL: program.bottle.url,
            loggingEnabled: run.graphicsLoggingEnabled ?? false
        )
    }
}

extension ProgramGraphicsSection {
    /// Re-reads the run's HUD samples when its log has grown.
    fileprivate func refreshMeasurement(for run: RunLogEntry?) {
        guard let run, run.frameRateMeasured == true else {
            measurement = nil
            measuredLogSize = nil
            return
        }
        let logURL = Wine.logsFolder.appending(path: run.logFileName)
        let size = (try? logURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard size != measuredLogSize else { return }
        measuredLogSize = size
        Task {
            let result = await Task.detached(priority: .utility) {
                MetalHUDLog.measurement(inLogAt: logURL)
            }.value
            measurement = result
        }
    }
}

/// A backend name in its tint.
struct BackendBadge: View {
    let backend: GraphicsBackend

    var body: some View {
        Text(backend.displayName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(backend.tint)
    }
}

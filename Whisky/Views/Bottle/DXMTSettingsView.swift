//
//  DXMTSettingsView.swift
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

/// The bottle's DXMT tuning, written to `dxmt.conf` on every DXMT launch.
struct DXMTSettingsView: View {
    @ObservedObject var bottle: Bottle
    @State private var showExtraOptions = false
    @State private var showPreview = false

    /// The main display's refresh rate. DXMT paces through CoreAnimation, so a
    /// cap only lands exactly on a factor of this.
    private var refreshRate: Int {
        max(NSScreen.main?.maximumFramesPerSecond ?? 60, 1)
    }

    /// Off, then every factor of the refresh rate from 15 up.
    private var frameRateOptions: [Int] {
        var options = [0] + (1 ... refreshRate).filter { $0 >= 15 && refreshRate % $0 == 0 }
        let current = bottle.settings.dxmtFrameRateLimit
        if current > 0, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    private var frameRateIsFactor: Bool {
        let limit = bottle.settings.dxmtFrameRateLimit
        return limit == 0 || refreshRate % limit == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DXMT")
                    .font(.headline)
                Spacer()
                Text("Direct3D 10/11 only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Written to this bottle's dxmt.conf each time a program launches on DXMT.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(selection: $bottle.settings.dxmtFrameRateLimit) {
                ForEach(frameRateOptions, id: \.self) { option in
                    Text(option == 0 ? "Off" : "\(option) fps").tag(option)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Frame rate limit")
                    Text("Paced by Metal, not a CPU sleep. Pick a factor of your \(refreshRate) Hz display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Measured with the Metal HUD on macOS 26.6 / M5: frame
                    // intervals stayed at the display rate with a 30 fps cap.
                    Text("DXMT 0.80 reads this but was not seen to enforce it on macOS 26. Verify with the " +
                        "Metal HUD before relying on it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if !frameRateIsFactor {
                Label(
                    "\(bottle.settings.dxmtFrameRateLimit) fps isn't a factor of \(refreshRate) Hz, " +
                        "so DXMT will settle on a lower rate.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Toggle(isOn: $bottle.settings.dxmtMetalFXSpatial) {
                VStack(alignment: .leading) {
                    Text("MetalFX spatial upscaling")
                    Text("Upscales the game's output with MetalFX. Set the game to a lower resolution to gain speed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if bottle.settings.dxmtMetalFXSpatial {
                upscaleFactorControl
            }

            DisclosureGroup("Extra dxmt.conf options", isExpanded: $showExtraOptions) {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $bottle.settings.dxmtExtraOptions)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.secondary.opacity(0.3))
                        )
                    Text("One `key = value` per line, e.g. `dxgi.customVendorId = 10de`. Later lines win.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            DisclosureGroup("Preview dxmt.conf", isExpanded: $showPreview) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: DXMTConfiguration.render(settings: bottle.settings))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    let fileURL = DXMTConfiguration.fileURL(bottleURL: bottle.url)
                    if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                        Button("Reveal dxmt.conf in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        }
                        .controlSize(.small)
                    } else {
                        Text("The file is created on the first DXMT launch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private static let upscalePresets: [(factor: Double, label: String)] = [
        (1.33, "1.33× (1080p → 1440p)"),
        (1.5, "1.5× (720p → 1080p)"),
        (2.0, "2× (1080p → 4K)")
    ]

    private var upscaleFactorControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Upscale factor")
                Spacer()
                Text(String(format: "%.2f×", bottle.settings.dxmtUpscaleFactor))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $bottle.settings.dxmtUpscaleFactor,
                in: DXMTConfiguration.upscaleFactorRange,
                step: 0.01
            )
            HStack(spacing: 6) {
                ForEach(Self.upscalePresets, id: \.factor) { preset in
                    Button(preset.label) {
                        bottle.settings.dxmtUpscaleFactor = preset.factor
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

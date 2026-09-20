//
//  GraphicsConfigSection.swift
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
import Metal
import SwiftUI
import WhiskyKit

struct GraphicsConfigSection: View {
    @ObservedObject var bottle: Bottle
    @AppStorage("graphicsAdvancedMode") private var advancedMode: Bool = false
    @State private var hasRunningProcesses: Bool = false

    private var resolvedBackend: GraphicsBackend {
        if bottle.settings.graphicsBackend == .recommended {
            return GraphicsBackendResolver.resolve()
        }
        return bottle.settings.graphicsBackend
    }

    var body: some View {
        Section("config.title.graphics") {
            // Simple/Advanced segmented control
            Picker("", selection: $advancedMode) {
                Text("config.graphics.simple").tag(false)
                Text("config.graphics.advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Backend picker -- always visible
            BackendPickerView(
                selection: $bottle.settings.graphicsBackend,
                resolvedBackend: resolvedBackend,
                isBackendAvailable: { backend in
                    WhiskyWineInstaller.isBackendAvailable(backend)
                }
            )

            // A bottle explicitly set to D3DMetal without its payload silently
            // degrades to WineD3D at launch — say so instead (issue #146).
            if bottle.settings.graphicsBackend == .d3dMetal,
               !WhiskyWineInstaller.isBackendAvailable(.d3dMetal) {
                d3dMetalMissingWarning
            }

            // Running process warning banner
            if hasRunningProcesses {
                runningProcessWarning
            }

            // MetalFX rides on D3DMetal's DLSS bridge and Metal 4 is D3DMetal's
            // own command-encoding backend, so both are meaningless under any
            // other backend rather than merely inactive.
            if resolvedBackend == .d3dMetal {
                Toggle(isOn: $bottle.settings.metalFX) {
                    VStack(alignment: .leading) {
                        Text("config.metalFX")
                        Text("config.metalFX.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $bottle.settings.metal4Enabled) {
                    VStack(alignment: .leading) {
                        Text("config.metal4")
                        Text("config.metal4.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Frame generation reaches MetalFX through the same DLSS bridge
                // as upscaling, so it has nothing to switch on without it.
                Toggle(isOn: $bottle.settings.frameGeneration) {
                    VStack(alignment: .leading) {
                        Text("config.frameGeneration")
                        Text("config.frameGeneration.info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!bottle.settings.metalFX)
            }

            // DXMT tuning applies wherever DXMT runs in this bottle, including
            // programs that override to it while the bottle uses something else.
            if resolvedBackend == .dxmt || programsWithGraphicsOverrides.contains(where: {
                $0.settings.overrides?.graphicsBackend == .dxmt
            }) {
                DXMTSettingsView(bottle: bottle)
            }

            // Force DX11 toggle -- always visible (Simple + Advanced)
            Toggle(isOn: $bottle.settings.forceD3D11) {
                Text("config.forceD3D11")
            }

            // Frame rate limit -- always visible, and on every backend
            Picker(selection: $bottle.settings.frameRateLimit) {
                ForEach(FrameRateLimitOptions.values(including: bottle.settings.frameRateLimit), id: \.self) {
                    Text(FrameRateLimitOptions.label($0)).tag($0)
                }
            } label: {
                VStack(alignment: .leading) {
                    Text("Frame rate limit")
                    Text("Caps every program in this bottle, on any graphics backend. Takes effect next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // The Sequoia compatibility toggle is gone: everything it set is a
            // platform-layer fix applied on every supported macOS, so the
            // switch changed nothing in either position.

            // "Advanced settings active" badge in Simple mode
            if !advancedMode, hasAdvancedSettingsConfigured {
                advancedSettingsBadge
            }

            // Per-program override note in Simple mode
            if !advancedMode, !programsWithGraphicsOverrides.isEmpty {
                programOverridesBadge
            }

            // Advanced mode content
            if advancedMode {
                // DXVK settings subsection
                DXVKSettingsView(
                    bottle: bottle,
                    resolvedBackend: resolvedBackend,
                    bottleURL: bottle.url
                )

                // Metal settings subsection (migrated from MetalConfigSection)
                VStack(alignment: .leading, spacing: 8) {
                    Text("config.metal.title")
                        .font(.headline)
                    Toggle(isOn: $bottle.settings.metalHud) {
                        Text("config.metalHud")
                    }
                    Toggle(isOn: $bottle.settings.metalTrace) {
                        Text("config.metalTrace")
                        Text("config.metalTrace.info")
                    }
                    if let device = MTLCreateSystemDefaultDevice() {
                        if device.supportsFamily(.apple9) {
                            Toggle(isOn: $bottle.settings.dxrEnabled) {
                                Text("config.dxr")
                                Text("config.dxr.info")
                            }
                        }
                    }
                    Toggle(isOn: $bottle.settings.metalValidation) {
                        Text("config.metalValidation")
                    }
                }

                // Per-program override info
                if !programsWithGraphicsOverrides.isEmpty {
                    programOverridesInfo
                }
            }
        }
        .animation(.default, value: advancedMode)
        .task {
            await checkRunningProcesses()
        }
    }

    // MARK: - D3DMetal Missing Warning

    private var d3dMetalMissingWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("config.graphics.backend.d3dMetal.missingWarning")
                .font(.caption)
            Spacer()
        }
    }

    // MARK: - Running Process Warning

    private var runningProcessWarning: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("config.graphics.nextLaunchInfo")
                .font(.caption)
            Spacer()
            Button("config.graphics.stopBottle") {
                Wine.killBottle(bottle: bottle)
                Task {
                    // Brief delay for wineserver to stop
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await checkRunningProcesses()
                }
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Running Process Check

    private func checkRunningProcesses() async {
        let wineserverActive = await Wine.isWineserverRunning(for: bottle)
        let trackedCount = ProcessRegistry.shared.getProcessCount(for: bottle)
        hasRunningProcesses = wineserverActive || trackedCount > 0
    }

    // MARK: - Advanced Settings Badge

    private var hasAdvancedSettingsConfigured: Bool {
        // Default dxvkAsync is true; check if any advanced-only settings differ from defaults
        !bottle.settings.dxvkAsync
            || bottle.settings.dxvkHud != .off
            || bottle.settings.metalHud
            || bottle.settings.metalTrace
            || bottle.settings.metalValidation
            || bottle.settings.dxrEnabled
    }

    private var advancedSettingsBadge: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.secondary)
            Text("config.graphics.advancedActive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("config.graphics.showAdvanced") {
                advancedMode = true
            }
            .font(.caption)
        }
    }

    // MARK: - Per-Program Override Info

    private var programsWithGraphicsOverrides: [Program] {
        bottle.programs.filter { $0.settings.overrides?.graphicsBackend != nil }
    }

    private var programOverridesBadge: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("config.graphics.programOverridesActive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("config.graphics.showAdvanced") {
                advancedMode = true
            }
            .font(.caption)
        }
    }

    private var programOverridesInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("config.graphics.programOverrides")
                .font(.headline)
            ForEach(programsWithGraphicsOverrides) { program in
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(program.name)
                        .font(.callout)
                    Spacer()
                    Text(
                        program.settings.overrides?.graphicsBackend?.displayName
                            ?? String(localized: "config.graphics.inherited")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text("config.graphics.programOverrides.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The choices a frame rate limit picker offers: off, then every factor of the
/// main display's refresh rate from 15 up, so a cap never beats against it.
enum FrameRateLimitOptions {
    static var refreshRate: Int {
        max(NSScreen.main?.maximumFramesPerSecond ?? 60, 1)
    }

    /// The options, plus `current` if it is set to something else, so the
    /// picker can always show the selection.
    static func values(including current: Int) -> [Int] {
        let rate = refreshRate
        var options = [0] + (1 ... rate).filter { $0 >= 15 && rate % $0 == 0 }
        if current > 0, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    static func label(_ value: Int) -> String {
        value == 0 ? "Off" : "\(value) fps"
    }
}

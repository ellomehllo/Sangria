//
//  BottleQuickConfigSection.swift
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

/// The handful of settings worth changing between one session and the next,
/// on the bottle's own screen instead of two taps into Configuration.
///
/// Everything here is a view onto the same `bottle.settings` the full
/// Configuration screen edits — this panel owns no state of its own, so the two
/// can never disagree. What earns a tile is a setting that changes how a game
/// runs and that people actually reach for; anything set once and forgotten
/// (audio driver, DLL overrides, cleanup policy) stays in Configuration.
///
/// Each tile carries a one-line explanation. A switch labelled only "Async
/// Shaders" asks the reader to already know what it does, which defeats the
/// point of surfacing it.
struct BottleQuickConfigSection: View {
    @ObservedObject var bottle: Bottle

    /// Deliberately not persisted. Backed by `@AppStorage` this arrived
    /// collapsed: something in the bottle screen's layout writes the binding
    /// back as false before anyone has clicked it, and a panel whose whole
    /// point is being visible must not be able to get stuck shut. Collapsing it
    /// still works for the rest of the visit.
    @State private var isExpanded: Bool = true

    /// What the bottle will actually run on, which is not what the setting says
    /// whenever the setting says "Automatic".
    private var resolvedBackend: GraphicsBackend {
        bottle.settings.graphicsBackend == .recommended
            ? GraphicsBackendResolver.resolve()
            : bottle.settings.graphicsBackend
    }

    private var availableBackends: [GraphicsBackend] {
        GraphicsBackend.allCases.filter { WhiskyWineInstaller.isBackendAvailable($0) }
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 10) {
                    // Top-aligned so a tile whose caption wraps to three lines
                    // does not push its neighbours' titles down the row.
                    HStack(alignment: .top, spacing: 10) {
                        engineTile
                        frameCapTile
                        fastSyncTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    profileTile
                    HStack(alignment: .top, spacing: 10) {
                        asyncShadersTile
                        upscalingTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            } label: {
                header
            }
        }
        .animation(.default, value: isExpanded)
        .animation(.default, value: resolvedBackend)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("quickConfig.title", systemImage: "slider.horizontal.3")
            Spacer()
            Text(runtimeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The engine actually behind this bottle, named and versioned. The mockup
    /// this screen follows put a bare version string here; a version with no
    /// subject tells you nothing, so it names the renderer too.
    private var runtimeSummary: String {
        let engine = resolvedBackend.displayName
        guard let version = WhiskyWineInstaller.whiskyWineVersion() else {
            return engine
        }
        return "\(engine) · Runtime \(version)"
    }

    // MARK: - Tiles

    private var engineTile: some View {
        QuickTile(
            title: "quickConfig.engine",
            caption: engineCaption,
            systemImage: "cpu",
            placement: .below
        ) {
            Picker("quickConfig.engine", selection: $bottle.settings.graphicsBackend) {
                ForEach(availableBackends, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var engineCaption: LocalizedStringKey {
        bottle.settings.graphicsBackend == .recommended
            ? "quickConfig.engine.auto \(resolvedBackend.displayName)"
            : "quickConfig.engine.manual"
    }

    private var frameCapTile: some View {
        QuickTile(
            title: "quickConfig.frameCap",
            caption: "quickConfig.frameCap.caption",
            systemImage: "speedometer",
            placement: .below
        ) {
            Picker("quickConfig.frameCap", selection: $bottle.settings.frameRateLimit) {
                ForEach(
                    FrameRateLimitOptions.values(including: bottle.settings.frameRateLimit),
                    id: \.self
                ) { value in
                    Text(FrameRateLimitOptions.label(value)).tag(value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// msync rather than esync: on macOS the Mach-port implementation is the one
    /// that helps, so the switch picks between it and plain Wine sync rather
    /// than exposing all three states nobody wants to arbitrate between. The
    /// full Configuration screen still offers esync for a bottle that needs it.
    private var fastSyncTile: some View {
        QuickTile(
            title: "quickConfig.fastSync",
            caption: "quickConfig.fastSync.caption",
            systemImage: "arrow.triangle.branch"
        ) {
            Toggle("quickConfig.fastSync", isOn: Binding(
                get: { bottle.settings.enhancedSync != .none },
                set: { bottle.settings.enhancedSync = $0 ? .msync : .none }
            ))
            .labelsHidden()
        }
    }

    private var profileTile: some View {
        QuickTile(
            title: "quickConfig.profile",
            caption: "quickConfig.profile.caption",
            systemImage: "dial.medium"
        ) {
            Picker("quickConfig.profile", selection: $bottle.settings.performancePreset) {
                Text("quickConfig.profile.performance").tag(PerformancePreset.performance)
                Text("quickConfig.profile.balanced").tag(PerformancePreset.balanced)
                Text("quickConfig.profile.quality").tag(PerformancePreset.quality)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    /// DXVK compiles pipelines on a background thread; nothing else here has a
    /// pipeline cache to compile ahead of.
    private var asyncShadersTile: some View {
        QuickTile(
            title: "quickConfig.asyncShaders",
            caption: resolvedBackend == .dxvk
                ? "quickConfig.asyncShaders.caption"
                : "quickConfig.asyncShaders.inactive",
            systemImage: "square.stack.3d.up",
            isActive: resolvedBackend == .dxvk
        ) {
            Toggle("quickConfig.asyncShaders", isOn: $bottle.settings.dxvkAsync)
                .labelsHidden()
                .disabled(resolvedBackend != .dxvk)
        }
    }

    /// MetalFX reaches a game through D3DMetal's DLSS bridge, so on any other
    /// renderer the switch has nothing to turn on.
    private var upscalingTile: some View {
        QuickTile(
            title: "quickConfig.upscaling",
            caption: resolvedBackend == .d3dMetal
                ? "quickConfig.upscaling.caption"
                : "quickConfig.upscaling.inactive",
            systemImage: "arrow.up.left.and.arrow.down.right",
            isActive: resolvedBackend == .d3dMetal
        ) {
            Toggle("quickConfig.upscaling", isOn: $bottle.settings.metalFX)
                .labelsHidden()
                .disabled(resolvedBackend != .d3dMetal)
        }
    }
}

// MARK: - Tile

/// One setting: what it is, what it does, and the control that changes it.
///
/// `isActive` is for a setting that is real but does nothing under the current
/// renderer. It dims rather than hides, because a switch that vanishes when you
/// change engines reads as a bug, and the caption says which engine brings it
/// back.
private struct QuickTile<Control: View>: View {
    /// Where the control sits relative to the title.
    ///
    /// A switch is narrow and belongs on the title's line. A pop-up carries a
    /// value as wide as "D3DMetal", and beside a title it squeezed that title
    /// down to "Graphic…" — so it gets a line of its own.
    enum ControlPlacement {
        case trailing
        case below
    }

    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let systemImage: String
    var placement: ControlPlacement = .trailing
    var isActive: Bool = true
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if placement == .trailing {
                    control()
                }
            }
            if placement == .below {
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        // Fills the row's height so the tiles beside it end at the same line,
        // whatever their captions wrap to.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isActive ? 1 : 0.55)
    }
}

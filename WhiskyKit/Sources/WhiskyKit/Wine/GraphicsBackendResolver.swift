//
//  GraphicsBackendResolver.swift
//  WhiskyKit
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

/// Resolves the `.recommended` graphics backend to a concrete backend.
///
/// This is a caseless enum (static methods only) following the ``GPUDetection`` pattern.
/// The resolver centralises the heuristic so that future improvements (e.g., preferring
/// DXVK on specific GPU families) can be made without changing the data model or UI.
public enum GraphicsBackendResolver {
    /// Resolves the recommended graphics backend for the current system.
    ///
    /// This build prefers DXMT: it is native Direct3D 10/11-to-Metal, needs no
    /// Apple payload, and on the titles it covers it is the most direct path to
    /// the GPU. The order is:
    ///
    /// 1. Launchers get DXVK. Their Chromium UIs cannot render on D3DMetal or DXMT.
    /// 2. A program that needs Direct3D 12 gets D3DMetal when its payload is
    ///    installed, because neither DXMT nor DXVK on macOS has a D3D12 path.
    /// 3. A program that only imports Direct3D 9 or older gets DXVK, since
    ///    DXMT would leave it on WineD3D, but only when the runtime's DXVK
    ///    actually ships `d3d9.dll`.
    /// 4. Otherwise DXMT when the runtime carries a usable DXMT payload,
    ///    then D3DMetal when installed, then DXVK, which ships with every runtime.
    ///
    /// Only backends that are actually installed are recommended; recommending
    /// a missing one makes a launch silently fall back to WineD3D.
    ///
    /// - Parameters:
    ///   - launcher: The launcher this launch targets, if any.
    ///   - api: What the executable's imports say about its graphics API, if known.
    ///   - macOSVersion: The macOS version to consider. Defaults to the running system.
    ///   - runtimeInfo: The runtime record to consider. Defaults to the installed
    ///     runtime's version plist.
    ///   - d3dMetalInstalled: Whether the D3DMetal payload exists on disk. Defaults
    ///     to checking the installed runtime.
    ///   - dxmtRuntimeNative: Whether the runtime's DXMT payload is the native
    ///     variant. Defaults to checking the installed runtime.
    /// - Returns: A concrete ``GraphicsBackend`` (never `.recommended`).
    public static func resolve(
        for launcher: LauncherType? = nil,
        api: GraphicsAPIProfile? = nil,
        macOSVersion: MacOSVersion = .current,
        runtimeInfo: WhiskyWineVersion? = WhiskyWineInstaller.whiskyWineInfo(),
        d3dMetalInstalled: Bool = WhiskyWineInstaller.isD3DMetalInstalled(),
        dxmtRuntimeNative: Bool = Wine.isDXMTRuntimeNative(),
        dxvkHasD3D9: Bool = Wine.dxvkProvidesD3D9()
    ) -> GraphicsBackend {
        resolveWithReason(
            for: launcher,
            api: api,
            macOSVersion: macOSVersion,
            runtimeInfo: runtimeInfo,
            d3dMetalInstalled: d3dMetalInstalled,
            dxmtRuntimeNative: dxmtRuntimeNative,
            dxvkHasD3D9: dxvkHasD3D9
        ).backend
    }

    /// ``resolve(for:api:macOSVersion:runtimeInfo:d3dMetalInstalled:dxmtRuntimeNative:)``
    /// together with a one-line reason the UI can show beside the choice.
    public static func resolveWithReason(
        for launcher: LauncherType? = nil,
        api: GraphicsAPIProfile? = nil,
        macOSVersion: MacOSVersion = .current,
        runtimeInfo: WhiskyWineVersion? = WhiskyWineInstaller.whiskyWineInfo(),
        d3dMetalInstalled: Bool = WhiskyWineInstaller.isD3DMetalInstalled(),
        dxmtRuntimeNative: Bool = Wine.isDXMTRuntimeNative(),
        dxvkHasD3D9: Bool = Wine.dxvkProvidesD3D9()
    ) -> (backend: GraphicsBackend, reason: String) {
        // Launcher clients are Chromium and cannot render on D3DMetal or DXMT:
        // the CEF gpu process fails to create its window swapchain and the
        // client shows no window (or a black one). DXVK is the one backend
        // their UIs render on, so a launcher gets it regardless of what else
        // is installed. Games a launcher starts still resolve below.
        if let launcher {
            return (.dxvk, "\(launcher.displayName) is a launcher; its UI only renders on DXVK")
        }
        if let api, api.usesD3D12, d3dMetalInstalled {
            return (.d3dMetal, "Direct3D 12 title; DXMT and DXVK have no Direct3D 12 path")
        }
        if let api, api.isLegacyDirect3DOnly, dxvkHasD3D9 {
            let name = api.primaryAPI?.displayName ?? "Legacy Direct3D"
            return (.dxvk, "\(name) title; DXMT only translates Direct3D 10/11")
        }
        // The same gate the backend picker applies, not the version record
        // alone: a version-only check lets auto promise DXMT on a runtime
        // whose payload is missing or builtin-variant, which then throws
        // payloadMissing at launch after the picker refused the same choice.
        if WhiskyWineInstaller.backendAvailability(
            .dxmt,
            runtimeInfo: runtimeInfo,
            d3dMetalInstalled: d3dMetalInstalled,
            dxmtRuntimeNative: dxmtRuntimeNative
        ) {
            return (.dxmt, "DXMT is the preferred backend for Direct3D 10/11")
        }
        if d3dMetalInstalled {
            return (.d3dMetal, "DXMT isn't available in this runtime; D3DMetal is installed")
        }
        return (.dxvk, "Neither DXMT nor D3DMetal is available; DXVK ships with every runtime")
    }

    /// The backend a brand-new bottle starts on: DXMT when the installed
    /// runtime can run it, otherwise Recommended, so a bottle is never created
    /// pointing at a backend that would fail its first launch.
    public static func defaultForNewBottle(
        runtimeInfo: WhiskyWineVersion? = WhiskyWineInstaller.whiskyWineInfo(),
        d3dMetalInstalled: Bool = WhiskyWineInstaller.isD3DMetalInstalled(),
        dxmtRuntimeNative: Bool = Wine.isDXMTRuntimeNative()
    ) -> GraphicsBackend {
        WhiskyWineInstaller.backendAvailability(
            .dxmt,
            runtimeInfo: runtimeInfo,
            d3dMetalInstalled: d3dMetalInstalled,
            dxmtRuntimeNative: dxmtRuntimeNative
        ) ? .dxmt : .recommended
    }

    /// Decides the concrete backend for one launch and records why.
    ///
    /// A program override beats the bottle; `.recommended` at either level
    /// resolves against what is being launched.
    ///
    /// - Parameters:
    ///   - bottleChoice: The bottle's backend setting.
    ///   - programChoice: The program's override, `nil` to inherit.
    ///   - launcher: The launcher detected from the executable, if any.
    ///   - api: The executable's API evidence, if known.
    ///   - resolveRecommended: Resolves `.recommended`; injectable for tests.
    public static func decide(
        bottleChoice: GraphicsBackend,
        programChoice: GraphicsBackend?,
        launcher: LauncherType? = nil,
        api: GraphicsAPIProfile? = nil,
        resolveRecommended: (LauncherType?, GraphicsAPIProfile?) -> (backend: GraphicsBackend, reason: String) = {
            resolveWithReason(for: $0, api: $1)
        }
    ) -> BackendDecision {
        let choice = programChoice ?? bottleChoice
        let source: BackendDecision.Source = programChoice == nil ? .bottle : .program
        guard choice == .recommended else {
            let reason = source == .program ? "Program override" : "Bottle setting"
            return BackendDecision(backend: choice, choice: choice, source: source, reason: reason)
        }
        let resolved = resolveRecommended(launcher, api)
        return BackendDecision(backend: resolved.backend, choice: .recommended, source: source, reason: resolved.reason)
    }

    /// Returns a localized explanation for the recommended backend choice.
    ///
    /// Suitable for display in a detail label or tooltip next to the "Recommended" option.
    ///
    /// - Parameter macOSVersion: The macOS version to consider. Defaults to the running system.
    /// - Returns: A human-readable rationale string.
    public static func rationale(macOSVersion: MacOSVersion = .current) -> String {
        "Recommended prefers DXMT for Direct3D 10/11. Direct3D 12 titles go to D3DMetal when it's " +
            "installed, launchers such as Steam go to DXVK, and so do Direct3D 9 titles when the runtime's " +
            "DXVK includes d3d9. The choice is made per launch and recorded in the program's run history."
    }
}

/// The concrete backend chosen for a launch, and how it was chosen.
public struct BackendDecision: Equatable, Sendable {
    /// Which setting the choice came from.
    public enum Source: String, Codable, Sendable {
        case bottle
        case program
    }

    /// The concrete backend the launch uses. Never `.recommended`.
    public let backend: GraphicsBackend
    /// The setting as configured, which may be `.recommended`.
    public let choice: GraphicsBackend
    /// Whether the bottle or a program override supplied the choice.
    public let source: Source
    /// Why this backend: "Bottle setting", or the Recommended policy's reason.
    public let reason: String

    public init(backend: GraphicsBackend, choice: GraphicsBackend, source: Source, reason: String) {
        self.backend = backend
        self.choice = choice
        self.source = source
        self.reason = reason
    }

    /// For example "DXMT — Bottle setting" or "DXVK — Recommended: ...".
    public var summary: String {
        let origin = choice == .recommended
            ? "Recommended (\(source == .program ? "program" : "bottle")): \(reason)"
            : reason
        return "\(backend.displayName) — \(origin)"
    }
}

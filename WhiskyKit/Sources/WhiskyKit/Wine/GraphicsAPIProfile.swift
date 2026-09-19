//
//  GraphicsAPIProfile.swift
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

/// A Windows graphics API an executable can use.
public enum GraphicsAPI: String, Codable, CaseIterable, Comparable, Sendable {
    case directDraw
    case d3d8
    case d3d9
    case d3d10
    case d3d11
    case d3d12
    case openGL
    case vulkan

    /// The DLL names that identify this API in an import table.
    var dllNames: [String] {
        switch self {
        case .directDraw: ["ddraw.dll"]
        case .d3d8: ["d3d8.dll"]
        case .d3d9: ["d3d9.dll"]
        case .d3d10: ["d3d10.dll", "d3d10_1.dll", "d3d10core.dll"]
        case .d3d11: ["d3d11.dll"]
        case .d3d12: ["d3d12.dll"]
        case .openGL: ["opengl32.dll"]
        case .vulkan: ["vulkan-1.dll"]
        }
    }

    public var displayName: String {
        switch self {
        case .directDraw: "DirectDraw"
        case .d3d8: "Direct3D 8"
        case .d3d9: "Direct3D 9"
        case .d3d10: "Direct3D 10"
        case .d3d11: "Direct3D 11"
        case .d3d12: "Direct3D 12"
        case .openGL: "OpenGL"
        case .vulkan: "Vulkan"
        }
    }

    /// Rank used to pick a program's headline API: newer Direct3D first.
    private var rank: Int {
        switch self {
        case .d3d12: 7
        case .d3d11: 6
        case .d3d10: 5
        case .vulkan: 4
        case .d3d9: 3
        case .openGL: 2
        case .d3d8: 1
        case .directDraw: 0
        }
    }

    public static func < (lhs: GraphicsAPI, rhs: GraphicsAPI) -> Bool {
        lhs.rank < rhs.rank
    }

    static func from(dllName: String) -> GraphicsAPI? {
        let lowered = dllName.lowercased()
        return allCases.first { $0.dllNames.contains(lowered) }
    }
}

/// What an executable reveals about the graphics APIs it uses.
///
/// Built from the PE import tables, plus the one on-disk signal that survives
/// dynamic loading: a `D3D12/D3D12Core.dll` beside the executable, which is how
/// games ship the D3D12 Agility SDK. Engines that pick their API at runtime
/// (most Unreal and Unity titles) load it with `LoadLibrary` and show up as
/// "not detected", so the profile is evidence, never proof of absence.
public struct GraphicsAPIProfile: Equatable, Sendable {
    /// APIs the executable itself imports.
    public var importedAPIs: Set<GraphicsAPI>
    /// Whether the D3D12 Agility SDK ships beside the executable.
    public var hasAgilitySDK: Bool

    public init(importedAPIs: Set<GraphicsAPI>, hasAgilitySDK: Bool = false) {
        self.importedAPIs = importedAPIs
        self.hasAgilitySDK = hasAgilitySDK
    }

    /// Whether the program needs Direct3D 12.
    public var usesD3D12: Bool {
        importedAPIs.contains(.d3d12) || hasAgilitySDK
    }

    /// Whether `d3d12.dll` is in the import table, so the loader must resolve
    /// it before any of the program runs. Such a program cannot fall back to
    /// Direct3D 11: with `d3d12` disabled it never starts. An Agility SDK folder
    /// alone means the engine loads `d3d12` itself and may have that fallback.
    public var importsD3D12: Bool {
        importedAPIs.contains(.d3d12)
    }

    /// Whether the only Direct3D the program imports predates Direct3D 10,
    /// which DXMT does not translate.
    public var isLegacyDirect3DOnly: Bool {
        let modern: Set<GraphicsAPI> = [.d3d10, .d3d11, .d3d12]
        let legacy: Set<GraphicsAPI> = [.d3d9, .d3d8, .directDraw]
        return importedAPIs.isDisjoint(with: modern) && !hasAgilitySDK && !importedAPIs.isDisjoint(with: legacy)
    }

    /// The newest API in evidence, if any.
    public var primaryAPI: GraphicsAPI? {
        if hasAgilitySDK { return .d3d12 }
        return importedAPIs.max()
    }

    /// A short label such as "Direct3D 11" or "Not detected".
    public var summary: String {
        guard let primaryAPI else { return "Not detected" }
        let others = importedAPIs.subtracting([primaryAPI]).sorted(by: >).map(\.displayName)
        return others.isEmpty
            ? primaryAPI.displayName
            : "\(primaryAPI.displayName) (also \(others.joined(separator: ", ")))"
    }

    /// Builds the profile from a list of imported DLL names.
    public init(importedDLLs: [String], hasAgilitySDK: Bool = false) {
        self.init(
            importedAPIs: Set(importedDLLs.compactMap(GraphicsAPI.from(dllName:))),
            hasAgilitySDK: hasAgilitySDK
        )
    }

    /// Inspects an executable on disk.
    ///
    /// - Returns: `nil` when the file is not a readable PE image.
    public static func detect(executableURL: URL) -> GraphicsAPIProfile? {
        guard let peFile = try? PEFile(url: executableURL) else { return nil }
        let agility = executableURL.deletingLastPathComponent()
            .appending(path: "D3D12")
            .appending(path: "D3D12Core.dll")
        return GraphicsAPIProfile(
            importedDLLs: peFile.importedDLLNames(),
            hasAgilitySDK: FileManager.default.fileExists(atPath: agility.path(percentEncoded: false))
        )
    }
}

// MARK: - Backend compatibility

/// How well a concrete backend fits a program's graphics API.
public enum BackendAPIAssessment: Equatable, Sendable {
    /// Nothing known against this pairing.
    case compatible
    /// It will run, but not through the chosen backend or not at its best.
    case caution(message: String, suggestion: GraphicsBackend?)
    /// The backend cannot render this API. Launching would fail or crash.
    case unsupported(message: String, suggestion: GraphicsBackend?)

    public var message: String? {
        switch self {
        case .compatible: nil
        case let .caution(message, _), let .unsupported(message, _): message
        }
    }

    public var suggestion: GraphicsBackend? {
        switch self {
        case .compatible: nil
        case let .caution(_, suggestion), let .unsupported(_, suggestion): suggestion
        }
    }

    public var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    /// Checks a concrete backend against an API profile.
    ///
    /// - Parameters:
    ///   - backend: The concrete backend the launch resolved to.
    ///   - profile: The program's API evidence.
    ///   - d3dMetalAvailable: Whether D3DMetal's payload is deployed, which
    ///     decides whether it can be offered as the way out.
    ///   - dxvkHasD3D9: Whether the runtime's DXVK ships `d3d9.dll`. Neither
    ///     DXMT nor D3DMetal translates Direct3D 9, so without it every
    ///     backend leaves a Direct3D 9 program on WineD3D.
    public static func assess(
        backend: GraphicsBackend,
        profile: GraphicsAPIProfile,
        d3dMetalAvailable: Bool,
        dxvkHasD3D9: Bool = false
    ) -> BackendAPIAssessment {
        if profile.usesD3D12 {
            return assessD3D12(backend: backend, profile: profile, d3dMetalAvailable: d3dMetalAvailable)
        }
        let translatesLegacy = backend == .wined3d || (backend == .dxvk && dxvkHasD3D9)
        if profile.isLegacyDirect3DOnly, !translatesLegacy {
            let api = profile.primaryAPI?.displayName ?? "an older Direct3D"
            if dxvkHasD3D9 {
                return .caution(
                    message: "\(backend.displayName) doesn't translate \(api), so this program will render " +
                        "through WineD3D, not \(backend.displayName). DXVK translates Direct3D 9.",
                    suggestion: .dxvk
                )
            }
            return .caution(
                message: "This program uses \(api). No backend in this runtime translates it (DXMT and " +
                    "D3DMetal start at Direct3D 10, and this DXVK build has no d3d9), so it renders through " +
                    "WineD3D whichever backend is selected.",
                suggestion: nil
            )
        }
        return .compatible
    }

    /// The Direct3D 12 half of ``assess(backend:profile:d3dMetalAvailable:dxvkHasD3D9:)``.
    ///
    /// Three routes exist. D3DMetal is the real one. WineD3D resets every
    /// translation DLL to builtin, which puts Wine's own `d3d12` in charge:
    /// vkd3d over winevulkan and MoltenVK, with Wine's `dxgi` beside it (DXMT's
    /// `dxgi` can't host its swapchain). DXMT and DXVK disable `d3d12`, which
    /// only an engine that loads it itself can survive, by falling back to
    /// Direct3D 11.
    private static func assessD3D12(
        backend: GraphicsBackend,
        profile: GraphicsAPIProfile,
        d3dMetalAvailable: Bool
    ) -> BackendAPIAssessment {
        let translator = backend == .dxmt || backend == .dxvk
        if translator, !profile.importsD3D12 {
            return .caution(
                message: "This program ships the Direct3D 12 Agility SDK. \(backend.displayName) turns " +
                    "Direct3D 12 off, so the game has to fall back to Direct3D 11. If it doesn't do that on its " +
                    "own, add -dx11 (Unreal) or -force-d3d11 (Unity) to its arguments.",
                suggestion: d3dMetalAvailable ? .d3dMetal : nil
            )
        }
        let wayOut = d3dMetalAvailable
            ? "Turn on Use D3DMetal for this program: right-click it, or tick the box next to Run on its page."
            : "D3DMetal (Apple's Game Porting Toolkit) isn't available in this runtime, but Wine's own " +
            "Direct3D 12 (vkd3d, through Vulkan and MoltenVK) can run it: use WineD3D for this program."
        let fallback: GraphicsBackend = d3dMetalAvailable ? .d3dMetal : .wined3d
        switch backend {
        case .dxmt:
            return .unsupported(
                message: "This program uses Direct3D 12, which DXMT doesn't support yet " +
                    "(DXMT covers Direct3D 10 and 11). \(wayOut)",
                suggestion: fallback
            )
        case .dxvk:
            return .unsupported(
                message: "This program uses Direct3D 12, which DXVK on macOS doesn't support. \(wayOut)",
                suggestion: fallback
            )
        case .wined3d:
            var message = "Direct3D 12 runs through Wine's vkd3d here (Vulkan, then MoltenVK): expect lower " +
                "performance and fewer features than D3DMetal."
            if !profile.importedAPIs.isDisjoint(with: [.d3d10, .d3d11]) {
                message += " This program also uses Direct3D 10/11, which WineD3D can't start on current macOS."
            }
            return .caution(message: message, suggestion: d3dMetalAvailable ? .d3dMetal : nil)
        case .d3dMetal, .recommended:
            return .compatible
        }
    }
}

/// Everything a launch decides about graphics before it starts.
public struct GraphicsLaunchPreview: Equatable, Sendable {
    /// The backend and why.
    public let decision: BackendDecision
    /// The executable's API evidence, `nil` when it is not a readable PE image.
    public let profile: GraphicsAPIProfile?
    /// How the backend fits the API.
    public let assessment: BackendAPIAssessment

    public init(decision: BackendDecision, profile: GraphicsAPIProfile?, assessment: BackendAPIAssessment) {
        self.decision = decision
        self.profile = profile
        self.assessment = assessment
    }
}

/// The graphics API check refused a launch.
public struct GraphicsAPICompatibilityError: LocalizedError, Equatable, Sendable {
    /// The backend the launch resolved to.
    public let backend: GraphicsBackend
    /// The assessment that refused it.
    public let assessment: BackendAPIAssessment
    /// The program's API evidence.
    public let profile: GraphicsAPIProfile

    public var errorDescription: String? {
        assessment.message
    }
}

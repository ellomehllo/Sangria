//
//  DXMTBackendPolicyTests.swift
//  WhiskyKitTests
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

import SemanticVersion
import Testing
@testable import WhiskyKit

@Suite("DXMT-first backend policy")
struct DXMTBackendPolicyTests {
    private let dxmtRuntime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
    private let d3d11 = GraphicsAPIProfile(importedAPIs: [.d3d11])
    private let d3d12 = GraphicsAPIProfile(importedAPIs: [.d3d12])
    private let d3d9 = GraphicsAPIProfile(importedAPIs: [.d3d9])

    private func resolve(
        launcher: LauncherType? = nil,
        api: GraphicsAPIProfile?,
        d3dMetal: Bool,
        dxmt: Bool = true,
        dxvkD3D9: Bool = true
    ) -> GraphicsBackend {
        GraphicsBackendResolver.resolve(
            for: launcher,
            api: api,
            runtimeInfo: dxmtRuntime,
            d3dMetalInstalled: d3dMetal,
            dxmtRuntimeNative: dxmt,
            dxvkHasD3D9: dxvkD3D9
        )
    }

    @Test("Direct3D 11 titles resolve to DXMT even when D3DMetal is installed")
    func d3d11PrefersDXMT() {
        #expect(resolve(api: d3d11, d3dMetal: true) == .dxmt)
        #expect(resolve(api: nil, d3dMetal: true) == .dxmt)
    }

    @Test("Direct3D 12 titles resolve to D3DMetal when it is installed")
    func d3d12GoesToD3DMetal() {
        #expect(resolve(api: d3d12, d3dMetal: true) == .d3dMetal)
    }

    @Test("Without D3DMetal, a title that imports d3d12 goes to WineD3D, where Wine's vkd3d runs it")
    func d3d12WithoutD3DMetal() {
        #expect(resolve(api: d3d12, d3dMetal: false) == .wined3d)
        let result = GraphicsBackendResolver.resolveWithReason(
            api: d3d12, runtimeInfo: dxmtRuntime, d3dMetalInstalled: false, dxmtRuntimeNative: true
        )
        #expect(result.reason.contains("vkd3d"))
    }

    @Test("The Agility SDK folder alone marks a title as Direct3D 12")
    func agilitySDKCountsAsD3D12() {
        let profile = GraphicsAPIProfile(importedAPIs: [.d3d11], hasAgilitySDK: true)
        #expect(profile.usesD3D12)
        #expect(!profile.importsD3D12)
        #expect(resolve(api: profile, d3dMetal: true) == .d3dMetal)
    }

    @Test("Without D3DMetal, an Agility-SDK-only title stays on DXMT, whose disabled d3d12 lets it fall back")
    func agilitySDKWithoutD3DMetal() {
        let profile = GraphicsAPIProfile(importedAPIs: [.d3d11], hasAgilitySDK: true)
        #expect(resolve(api: profile, d3dMetal: false) == .dxmt)
    }

    @Test("Direct3D 9-only titles resolve to DXVK when its payload ships d3d9")
    func d3d9GoesToDXVK() {
        #expect(resolve(api: d3d9, d3dMetal: true, dxvkD3D9: true) == .dxvk)
        let mixed = GraphicsAPIProfile(importedAPIs: [.d3d9, .d3d11])
        #expect(resolve(api: mixed, d3dMetal: false) == .dxmt)
    }

    @Test("Without a DXVK d3d9, Direct3D 9 titles are not steered: every backend lands on WineD3D")
    func d3d9WithoutDXVKD3D9() {
        #expect(resolve(api: d3d9, d3dMetal: true, dxvkD3D9: false) == .dxmt)
    }

    @Test("Launchers resolve to DXVK regardless of API")
    func launchersGetDXVK() {
        #expect(resolve(launcher: .steam, api: d3d12, d3dMetal: true) == .dxvk)
    }

    @Test("Every resolution carries a reason")
    func reasons() {
        let result = GraphicsBackendResolver.resolveWithReason(
            api: d3d12, runtimeInfo: dxmtRuntime, d3dMetalInstalled: true, dxmtRuntimeNative: true
        )
        #expect(result.backend == .d3dMetal)
        #expect(result.reason.contains("Direct3D 12"))
    }

    @Test("New bottles default to DXMT only when the runtime can run it")
    func newBottleDefault() {
        #expect(GraphicsBackendResolver.defaultForNewBottle(
            runtimeInfo: dxmtRuntime, d3dMetalInstalled: false, dxmtRuntimeNative: true
        ) == .dxmt)
        #expect(GraphicsBackendResolver.defaultForNewBottle(
            runtimeInfo: dxmtRuntime, d3dMetalInstalled: true, dxmtRuntimeNative: false
        ) == .recommended)
        #expect(GraphicsBackendResolver.defaultForNewBottle(
            runtimeInfo: nil, d3dMetalInstalled: false, dxmtRuntimeNative: true
        ) == .recommended)
    }

    // MARK: - Decisions

    private static func stubRecommended(
        _: LauncherType?, _: GraphicsAPIProfile?
    ) -> (backend: GraphicsBackend, reason: String) {
        (.dxmt, "stub")
    }

    @Test("A program override beats the bottle and says so")
    func programOverrideWins() {
        let decision = GraphicsBackendResolver.decide(
            bottleChoice: .dxmt, programChoice: .d3dMetal, resolveRecommended: Self.stubRecommended
        )
        #expect(decision.backend == .d3dMetal)
        #expect(decision.source == .program)
        #expect(decision.reason == "Program override")
    }

    @Test("An explicit bottle backend is used as is")
    func bottleSetting() {
        let decision = GraphicsBackendResolver.decide(
            bottleChoice: .dxvk, programChoice: nil, resolveRecommended: Self.stubRecommended
        )
        #expect(decision == BackendDecision(backend: .dxvk, choice: .dxvk, source: .bottle, reason: "Bottle setting"))
    }

    @Test("Recommended resolves and keeps its reason and source")
    func recommendedResolves() {
        let decision = GraphicsBackendResolver.decide(
            bottleChoice: .dxvk, programChoice: .recommended, resolveRecommended: Self.stubRecommended
        )
        #expect(decision.backend == .dxmt)
        #expect(decision.choice == .recommended)
        #expect(decision.source == .program)
        #expect(decision.summary.hasPrefix("DXMT"))
        #expect(decision.summary.contains("stub"))
    }

    // MARK: - API assessment

    @Test("Direct3D 12 on DXMT is refused with a pointer to D3DMetal")
    func d3d12OnDXMTRefused() {
        let assessment = BackendAPIAssessment.assess(backend: .dxmt, profile: d3d12, d3dMetalAvailable: true)
        #expect(assessment.isUnsupported)
        #expect(assessment.suggestion == .d3dMetal)
        #expect(assessment.message?.contains("doesn't support yet") == true)
        #expect(assessment.message?.contains("Use D3DMetal") == true)
    }

    @Test("Without D3DMetal the refusal points at WineD3D, where vkd3d runs Direct3D 12")
    func d3d12WithoutD3DMetalMessage() {
        for backend in [GraphicsBackend.dxmt, .dxvk] {
            let assessment = BackendAPIAssessment.assess(backend: backend, profile: d3d12, d3dMetalAvailable: false)
            #expect(assessment.isUnsupported)
            #expect(assessment.suggestion == .wined3d)
            #expect(assessment.message?.contains("vkd3d") == true)
            #expect(assessment.message?.contains("Game Porting Toolkit") == true)
        }
    }

    @Test("Direct3D 12 on DXVK is refused; on WineD3D it is a caution; on D3DMetal it is fine")
    func d3d12Matrix() {
        #expect(BackendAPIAssessment.assess(backend: .dxvk, profile: d3d12, d3dMetalAvailable: true).isUnsupported)
        let wined3d = BackendAPIAssessment.assess(backend: .wined3d, profile: d3d12, d3dMetalAvailable: true)
        #expect(!wined3d.isUnsupported)
        #expect(wined3d.suggestion == .d3dMetal)
        #expect(wined3d.message?.contains("vkd3d") == true)
        let alone = BackendAPIAssessment.assess(backend: .wined3d, profile: d3d12, d3dMetalAvailable: false)
        #expect(!alone.isUnsupported)
        #expect(alone.suggestion == nil)
        #expect(BackendAPIAssessment.assess(backend: .d3dMetal, profile: d3d12, d3dMetalAvailable: true)
            == .compatible)
    }

    @Test("On WineD3D, a Direct3D 12 title that also imports Direct3D 11 is warned about it")
    func d3d12WithD3D11OnWineD3D() {
        let mixed = GraphicsAPIProfile(importedAPIs: [.d3d12, .d3d11])
        let assessment = BackendAPIAssessment.assess(backend: .wined3d, profile: mixed, d3dMetalAvailable: false)
        #expect(assessment.message?.contains("Direct3D 10/11") == true)
        let plain = BackendAPIAssessment.assess(backend: .wined3d, profile: d3d12, d3dMetalAvailable: false)
        #expect(plain.message?.contains("Direct3D 10/11") == false)
    }

    @Test("An Agility-SDK-only title on DXMT or DXVK is a caution naming the Direct3D 11 switches")
    func agilitySDKOnTranslatorsCaution() {
        let profile = GraphicsAPIProfile(importedAPIs: [.d3d11], hasAgilitySDK: true)
        for backend in [GraphicsBackend.dxmt, .dxvk] {
            let assessment = BackendAPIAssessment.assess(backend: backend, profile: profile, d3dMetalAvailable: false)
            #expect(!assessment.isUnsupported)
            #expect(assessment.suggestion == nil)
            #expect(assessment.message?.contains("-dx11") == true)
            #expect(assessment.message?.contains("-force-d3d11") == true)
        }
        #expect(BackendAPIAssessment.assess(backend: .dxmt, profile: profile, d3dMetalAvailable: true)
            .suggestion == .d3dMetal)
    }

    @Test("Direct3D 9 on DXMT is a caution pointing at DXVK when DXVK has d3d9, not a refusal")
    func d3d9OnDXMTCaution() {
        let assessment = BackendAPIAssessment.assess(
            backend: .dxmt, profile: d3d9, d3dMetalAvailable: true, dxvkHasD3D9: true
        )
        #expect(!assessment.isUnsupported)
        #expect(assessment.suggestion == .dxvk)
        #expect(assessment.message?.contains("WineD3D") == true)
        #expect(BackendAPIAssessment.assess(
            backend: .dxvk, profile: d3d9, d3dMetalAvailable: true, dxvkHasD3D9: true
        ) == .compatible)
    }

    @Test("Without a DXVK d3d9, Direct3D 9 is a caution on every translating backend, with no false suggestion")
    func d3d9WithoutDXVKD3D9Caution() {
        for backend in [GraphicsBackend.dxmt, .dxvk, .d3dMetal] {
            let assessment = BackendAPIAssessment.assess(
                backend: backend, profile: d3d9, d3dMetalAvailable: true, dxvkHasD3D9: false
            )
            #expect(!assessment.isUnsupported)
            #expect(assessment.suggestion == nil)
            #expect(assessment.message?.contains("whichever backend") == true)
        }
        #expect(BackendAPIAssessment.assess(
            backend: .wined3d, profile: d3d9, d3dMetalAvailable: true, dxvkHasD3D9: false
        ) == .compatible)
    }

    @Test("Direct3D 11 on DXMT is compatible")
    func d3d11OnDXMT() {
        #expect(BackendAPIAssessment.assess(backend: .dxmt, profile: d3d11, d3dMetalAvailable: false) == .compatible)
    }

    private func preview(_ profile: GraphicsAPIProfile?, _ backend: GraphicsBackend) -> GraphicsLaunchPreview {
        GraphicsLaunchPreview(
            decision: BackendDecision(backend: backend, choice: backend, source: .bottle, reason: "Bottle setting"),
            profile: profile,
            assessment: profile.map {
                BackendAPIAssessment.assess(backend: backend, profile: $0, d3dMetalAvailable: true)
            } ?? .compatible
        )
    }

    @Test("The launch check throws a descriptive error for unsupported pairings only")
    func launchCheck() throws {
        let error = #expect(throws: GraphicsAPICompatibilityError.self) {
            try Wine.checkGraphicsAPI(preview(d3d12, .dxmt))
        }
        #expect(error?.errorDescription?.contains("Direct3D 12") == true)
        #expect(error?.backend == .dxmt)
        try Wine.checkGraphicsAPI(preview(d3d11, .dxmt))
        try Wine.checkGraphicsAPI(preview(nil, .dxmt))
        try Wine.checkGraphicsAPI(preview(d3d9, .dxmt))
        try Wine.checkGraphicsAPI(preview(d3d12, .d3dMetal))
        try Wine.checkGraphicsAPI(preview(d3d12, .wined3d))
        try Wine.checkGraphicsAPI(preview(GraphicsAPIProfile(importedAPIs: [.d3d11], hasAgilitySDK: true), .dxmt))
    }

    // MARK: - Profiles

    @Test("Profiles map DLL names case-insensitively and pick the newest API")
    func profileFromDLLs() {
        let profile = GraphicsAPIProfile(importedDLLs: ["KERNEL32.dll", "D3D11.dll", "dxgi.dll", "d3d9.dll"])
        #expect(profile.importedAPIs == [.d3d11, .d3d9])
        #expect(profile.primaryAPI == .d3d11)
        #expect(profile.summary == "Direct3D 11 (also Direct3D 9)")
        #expect(!profile.isLegacyDirect3DOnly)
        #expect(GraphicsAPIProfile(importedDLLs: ["kernel32.dll"]).summary == "Not detected")
    }

    @Test("Direct3D 10.1 and d3d10core count as Direct3D 10")
    func d3d10Variants() {
        #expect(GraphicsAPIProfile(importedDLLs: ["d3d10_1.dll"]).importedAPIs == [.d3d10])
        #expect(GraphicsAPIProfile(importedDLLs: ["d3d10core.dll"]).importedAPIs == [.d3d10])
    }
}

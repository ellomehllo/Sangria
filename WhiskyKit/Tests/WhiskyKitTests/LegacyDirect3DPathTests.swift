//
//  LegacyDirect3DPathTests.swift
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

import Foundation
import Testing
@testable import WhiskyKit

/// Direct3D 9 always ends up on Wine's own `wined3d` here, whatever backend is
/// named — but `WINED3DMETAL=0` used to follow the *name*, so on a bottle set to
/// D3DMetal wined3d took its Metal route and could not enumerate an adapter.
/// Euro Truck Simulator's launcher found no device and the game faulted on the
/// null one it was handed.
@Suite("Direct3D 9 gets the working wined3d path on any backend")
struct LegacyDirect3DPathTests {
    private let d3d9 = GraphicsAPIProfile(importedAPIs: [.d3d9])
    private let d3d11 = GraphicsAPIProfile(importedAPIs: [.d3d11])

    private func environment(
        profile: GraphicsAPIProfile?,
        backend: GraphicsBackend
    ) -> [String: String] {
        var env: [String: String] = [:]
        Wine.applyLegacyDirect3DPath(&env, apiProfile: profile, effectiveBackend: backend)
        return env
    }

    @Test("A Direct3D 9 program gets WINED3DMETAL=0 on a backend that cannot translate it")
    func legacyOnModernBackend() {
        for backend in [GraphicsBackend.d3dMetal, .dxmt, .dxvk] {
            #expect(environment(profile: d3d9, backend: backend)["WINED3DMETAL"] == "0")
        }
    }

    @Test("Direct3D 8 and DirectDraw get it too")
    func olderAPIsAlso() {
        for api in [GraphicsAPI.d3d8, .directDraw] {
            let profile = GraphicsAPIProfile(importedAPIs: [api])
            #expect(environment(profile: profile, backend: .d3dMetal)["WINED3DMETAL"] == "0")
        }
    }

    @Test("On WineD3D it is left alone: the backend layer already sets it")
    func wineD3DUntouched() {
        #expect(environment(profile: d3d9, backend: .wined3d).isEmpty)
    }

    @Test("A modern program is untouched, so nothing else changes behaviour")
    func modernUntouched() {
        #expect(environment(profile: d3d11, backend: .d3dMetal).isEmpty)
        #expect(environment(profile: nil, backend: .d3dMetal).isEmpty)
        let mixed = GraphicsAPIProfile(importedAPIs: [.d3d9, .d3d11])
        #expect(environment(profile: mixed, backend: .d3dMetal).isEmpty)
    }

    @Test("It only adds the one variable, and does not disturb what is already there")
    func doesNotClobber() {
        var env = ["WINEPREFIX": "/somewhere", "WINEMSYNC": "1"]
        Wine.applyLegacyDirect3DPath(&env, apiProfile: d3d9, effectiveBackend: .d3dMetal)
        #expect(env["WINEPREFIX"] == "/somewhere")
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["WINED3DMETAL"] == "0")
        #expect(env.count == 3)
    }
}

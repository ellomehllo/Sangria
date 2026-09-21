//
//  DynamicGraphicsAPITests.swift
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
import SemanticVersion
import Testing
@testable import WhiskyKit

/// Detection of a Direct3D version the executable loads at runtime rather than
/// importing. Euro Truck Simulator resolves `Direct3DCreate9` by hand, so its
/// import table names no graphics API at all and the program page reported "Not
/// detected" — which let the resolver route a Direct3D 9 game to a backend that
/// starts at Direct3D 10.
@Suite("Graphics APIs an executable loads rather than imports")
struct DynamicGraphicsAPITests {
    /// Writes `body` into a throwaway folder and hands back its URL.
    private func withFolder(_ body: (URL) throws -> Void) rethrows {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func write(_ text: String, to url: URL) {
        try? Data(text.utf8).write(to: url)
    }

    @Test("A DLL name in the image counts, even with nothing in the import table")
    func findsNameInExecutable() {
        withFolder { folder in
            let exe = folder.appending(path: "game.exe")
            write("MZ....LoadLibraryA\0d3d9.dll\0Direct3DCreate9\0", to: exe)
            let found = GraphicsAPIProfile.dynamicallyLoadedAPIs(executableURL: exe, folder: folder)
            #expect(found == [.d3d9])
        }
    }

    @Test("A renderer plugin beside the executable is searched too")
    func findsNameInPluginFolder() {
        withFolder { folder in
            let exe = folder.appending(path: "game.exe")
            write("MZ nothing to see here", to: exe)
            let lib = folder.appending(path: "lib")
            try? FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
            write("MZ....d3d9.dll....Direct3DCreate9Ex", to: lib.appending(path: "dx9.dll"))
            let found = GraphicsAPIProfile.dynamicallyLoadedAPIs(executableURL: exe, folder: folder)
            #expect(found == [.d3d9])
        }
    }

    @Test("Case and UTF-16 spellings both count")
    func findsEitherEncoding() {
        withFolder { folder in
            let upper = folder.appending(path: "a.exe")
            write("MZ....D3D11.DLL", to: upper)
            #expect(GraphicsAPIProfile.dynamicallyLoadedAPIs(
                executableURL: upper, folder: folder
            ) == [.d3d11])

            let wide = folder.appending(path: "b.exe")
            let utf16 = Data("d3d12.dll".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
            try? (Data("MZ".utf8) + utf16).write(to: wide)
            #expect(GraphicsAPIProfile.dynamicallyLoadedAPIs(
                executableURL: wide, folder: folder
            ).contains(.d3d12))
        }
    }

    @Test("An executable that names no Direct3D reports none")
    func findsNothingWhenAbsent() {
        withFolder { folder in
            let exe = folder.appending(path: "tool.exe")
            write("MZ just a console program, kernel32.dll and user32.dll", to: exe)
            #expect(GraphicsAPIProfile.dynamicallyLoadedAPIs(
                executableURL: exe, folder: folder
            ).isEmpty)
        }
    }

    @Test("OpenGL and Vulkan are deliberately not inferred from strings")
    func ignoresNonDirect3D() {
        withFolder { folder in
            let exe = folder.appending(path: "game.exe")
            write("MZ....opengl32.dll....vulkan-1.dll", to: exe)
            #expect(GraphicsAPIProfile.dynamicallyLoadedAPIs(
                executableURL: exe, folder: folder
            ).isEmpty)
        }
    }

    @Test("A detected Direct3D 9 game is legacy-only, which is what steers it to WineD3D")
    func detectedLegacyProfileSteers() {
        let profile = GraphicsAPIProfile(importedAPIs: [.d3d9])
        #expect(profile.isLegacyDirect3DOnly)
        #expect(GraphicsBackendResolver.resolve(
            for: nil,
            api: profile,
            runtimeInfo: WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80"),
            d3dMetalInstalled: true,
            dxmtRuntimeNative: true,
            dxvkHasD3D9: false
        ) == .wined3d)
    }
}

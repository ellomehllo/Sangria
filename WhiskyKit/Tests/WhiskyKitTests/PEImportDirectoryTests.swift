//
//  PEImportDirectoryTests.swift
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

/// Builds a minimal PE image with one `.idata` section holding an import
/// table and, optionally, a delay-import table.
private struct SyntheticPE {
    var is64Bit = true
    var imports: [String] = []
    var delayImports: [String] = []
    /// Stack/heap reserve values. Nonzero upper halves in PE32+ are what the
    /// old 32-bit reads of these fields tripped over.
    var sizeField: UInt64 = 0x0000_0001_0010_0000

    private static let peOffset = 0x80
    private static let sectionRVA: UInt32 = 0x1000
    private static let sectionFileOffset = 0x400
    private static let sectionSize = 0x400

    // swiftlint:disable:next function_body_length
    func build() -> Data {
        var data = Data(count: Self.sectionFileOffset + Self.sectionSize)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes in
                data.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
            }
        }
        data[0] = 0x4D // "MZ"
        data[1] = 0x5A
        put(UInt32(Self.peOffset), at: 0x3C)
        data.replaceSubrange(Self.peOffset ..< Self.peOffset + 4, with: [0x50, 0x45, 0, 0])

        // COFF header.
        let coff = Self.peOffset + 4
        put(UInt16(is64Bit ? 0x8664 : 0x14C), at: coff)
        put(UInt16(1), at: coff + 2)
        let optionalSize = is64Bit ? 112 + 16 * 8 : 96 + 16 * 8
        put(UInt16(optionalSize), at: coff + 16)

        // Optional header.
        let opt = coff + 20
        put(UInt16(is64Bit ? 0x20B : 0x10B), at: opt)
        put(UInt32(0x400), at: opt + 60) // SizeOfHeaders
        if is64Bit {
            put(UInt64(0x1_4000_0000), at: opt + 24) // ImageBase
            for index in 0 ..< 4 {
                put(sizeField, at: opt + 72 + index * 8)
            }
            put(UInt32(16), at: opt + 108)
        } else {
            put(UInt32(0x40_0000), at: opt + 28)
            for index in 0 ..< 4 {
                put(UInt32(truncatingIfNeeded: sizeField), at: opt + 72 + index * 4)
            }
            put(UInt32(16), at: opt + 92)
        }
        let directories = opt + (is64Bit ? 112 : 96)

        // Section table: one section holding everything.
        let section = opt + optionalSize
        data.replaceSubrange(section ..< section + 6, with: Array(".idata".utf8))
        put(UInt32(Self.sectionSize), at: section + 8)
        put(Self.sectionRVA, at: section + 12)
        put(UInt32(Self.sectionSize), at: section + 16)
        put(UInt32(Self.sectionFileOffset), at: section + 20)

        // Layout inside the section: import descriptors, delay descriptors, strings.
        var cursor = 0
        func rva(_ sectionOffset: Int) -> UInt32 {
            Self.sectionRVA + UInt32(sectionOffset)
        }
        let importTable = cursor
        cursor += (imports.count + 1) * 20
        let delayTable = cursor
        cursor += (delayImports.count + 1) * 32
        var stringOffsets: [String: Int] = [:]
        for name in imports + delayImports where stringOffsets[name] == nil {
            stringOffsets[name] = cursor
            let bytes = Array(name.utf8) + [0]
            data.replaceSubrange(
                Self.sectionFileOffset + cursor ..< Self.sectionFileOffset + cursor + bytes.count, with: bytes
            )
            cursor += bytes.count
        }
        for (index, name) in imports.enumerated() {
            let base = Self.sectionFileOffset + importTable + index * 20
            put(rva(0x300), at: base) // OriginalFirstThunk (dummy)
            put(rva(stringOffsets[name] ?? 0), at: base + 12)
            put(rva(0x300), at: base + 16) // FirstThunk (dummy)
        }
        for (index, name) in delayImports.enumerated() {
            let base = Self.sectionFileOffset + delayTable + index * 32
            put(UInt32(1), at: base) // RVA-based
            put(rva(stringOffsets[name] ?? 0), at: base + 4)
        }
        if !imports.isEmpty {
            put(rva(importTable), at: directories + 8)
            put(UInt32((imports.count + 1) * 20), at: directories + 12)
        }
        if !delayImports.isEmpty {
            put(rva(delayTable), at: directories + 13 * 8)
            put(UInt32((delayImports.count + 1) * 32), at: directories + 13 * 8 + 4)
        }
        return data
    }

    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).exe")
        try build().write(to: url)
        return url
    }
}

@Suite("PE import directory")
struct PEImportDirectoryTests {
    @Test("A PE32+ image's imports are read, including NumberOfRvaAndSizes past the 8-byte size fields")
    func pe32PlusImports() throws {
        let url = try SyntheticPE(is64Bit: true, imports: ["KERNEL32.dll", "d3d11.dll", "DXGI.dll"]).write()
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try PEFile(url: url)
        #expect(image.architecture == .x64)
        #expect(image.optionalHeader?.numberOfRvaAndSizes == 16)
        #expect(image.optionalHeader?.sizeOfStackReserve == 0x0010_0000)
        #expect(image.importedDLLNames() == ["kernel32.dll", "d3d11.dll", "dxgi.dll"])
    }

    @Test("A PE32 image's imports are read")
    func pe32Imports() throws {
        let url = try SyntheticPE(is64Bit: false, imports: ["d3d9.dll", "user32.dll"]).write()
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try PEFile(url: url)
        #expect(image.architecture == .x32)
        #expect(image.importedDLLNames() == ["d3d9.dll", "user32.dll"])
    }

    @Test("Delay-loaded DLLs are included, without duplicates")
    func delayImports() throws {
        let url = try SyntheticPE(imports: ["dxgi.dll"], delayImports: ["d3d12.dll", "DXGI.dll"]).write()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try PEFile(url: url).importedDLLNames() == ["dxgi.dll", "d3d12.dll"])
    }

    @Test("An image with no import table yields nothing")
    func noImports() throws {
        let url = try SyntheticPE().write()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try PEFile(url: url).importedDLLNames().isEmpty)
    }

    @Test("An import directory pointing outside every section yields nothing instead of garbage")
    func badRVA() throws {
        var data = SyntheticPE(imports: ["d3d11.dll"]).build()
        // Point the import directory far past the section.
        let directories = 0x80 + 4 + 20 + 112
        withUnsafeBytes(of: UInt32(0x00F0_0000).littleEndian) { bytes in
            data.replaceSubrange(directories + 8 ..< directories + 12, with: bytes)
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).exe")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try PEFile(url: url).importedDLLNames().isEmpty)
    }

    @Test("Detection builds the API profile from imports and the Agility SDK folder")
    func detection() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "D3D12"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let exe = dir.appending(path: "Game.exe")
        try SyntheticPE(imports: ["d3d11.dll", "dxgi.dll"]).build().write(to: exe)
        var profile = try #require(GraphicsAPIProfile.detect(executableURL: exe))
        #expect(profile.importedAPIs == [.d3d11])
        #expect(!profile.usesD3D12)

        try Data("stub".utf8).write(to: dir.appending(path: "D3D12/D3D12Core.dll"))
        profile = try #require(GraphicsAPIProfile.detect(executableURL: exe))
        #expect(profile.usesD3D12)
        #expect(profile.primaryAPI == .d3d12)

        let notPE = dir.appending(path: "readme.txt")
        try Data("hello".utf8).write(to: notPE)
        #expect(GraphicsAPIProfile.detect(executableURL: notPE) == nil)
    }
}

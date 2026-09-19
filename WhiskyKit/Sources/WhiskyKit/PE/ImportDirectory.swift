//
//  ImportDirectory.swift
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

extension PEFile {
    /// Data directory indices from the PE optional header.
    ///
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#optional-header-data-directories-image-only
    enum DataDirectory: Int {
        case importTable = 1
        case delayImportDescriptor = 13
    }

    /// Upper bounds for walking file-controlled tables, so a malformed or
    /// hostile executable cannot make the scan run away.
    private static let maxImportDescriptors = 4_096
    private static let maxDLLNameLength = 256

    /// The DLL names this executable imports, statically or delay-loaded,
    /// lowercased and in table order without duplicates.
    ///
    /// Libraries loaded at runtime with `LoadLibrary` are not visible here, so
    /// an empty or partial answer does not rule an API out.
    public func importedDLLNames() -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var names: [String] = []
        var seen = Set<String>()
        func add(_ name: String) {
            let lowered = name.lowercased()
            if seen.insert(lowered).inserted {
                names.append(lowered)
            }
        }

        if let dir = dataDirectory(.importTable, handle: handle), dir.rva != 0 {
            for name in importDescriptorNames(rva: dir.rva, handle: handle) {
                add(name)
            }
        }
        if let dir = dataDirectory(.delayImportDescriptor, handle: handle), dir.rva != 0 {
            for name in delayImportNames(rva: dir.rva, handle: handle) {
                add(name)
            }
        }
        return names
    }

    /// Reads one data directory entry (RVA, size) from the optional header.
    func dataDirectory(_ directory: DataDirectory, handle: FileHandle) -> (rva: UInt32, size: UInt32)? {
        guard let optionalHeader,
              UInt32(directory.rawValue) < optionalHeader.numberOfRvaAndSizes,
              let peOffset = handle.extract(UInt32.self, offset: 0x3C)
        else { return nil }

        // Signature (4) + COFF header (20), then the optional header's fixed
        // fields: 96 bytes for PE32, 112 for PE32+.
        let fixedFields: UInt64 = switch optionalHeader.magic {
        case .pe32Plus: 112
        case .pe32: 96
        default: 0
        }
        guard fixedFields > 0 else { return nil }
        let entryOffset = UInt64(peOffset) + 24 + fixedFields + UInt64(directory.rawValue) * 8
        guard let rva = handle.extract(UInt32.self, offset: entryOffset),
              let size = handle.extract(UInt32.self, offset: entryOffset + 4)
        else { return nil }
        return (rva, size)
    }

    /// Maps a relative virtual address to a file offset through the section table.
    func fileOffset(forRVA rva: UInt32) -> UInt64? {
        for section in sections {
            let span = max(section.virtualSize, section.sizeOfRawData)
            let start = UInt64(section.virtualAddress)
            if UInt64(rva) >= start, UInt64(rva) < start + UInt64(span) {
                let delta = UInt64(rva) - start
                guard delta < UInt64(section.sizeOfRawData) else { return nil }
                return UInt64(section.pointerToRawData) + delta
            }
        }
        // RVAs inside the headers map one to one.
        if let headers = optionalHeader?.sizeOfHeaders, rva < headers {
            return UInt64(rva)
        }
        return nil
    }

    private func importDescriptorNames(rva: UInt32, handle: FileHandle) -> [String] {
        guard var offset = fileOffset(forRVA: rva) else { return [] }
        var names: [String] = []
        for _ in 0 ..< Self.maxImportDescriptors {
            // IMAGE_IMPORT_DESCRIPTOR: OriginalFirstThunk, TimeDateStamp,
            // ForwarderChain, Name, FirstThunk (4 bytes each).
            guard let originalFirstThunk = handle.extract(UInt32.self, offset: offset),
                  let nameRVA = handle.extract(UInt32.self, offset: offset + 12),
                  let firstThunk = handle.extract(UInt32.self, offset: offset + 16)
            else { break }
            if originalFirstThunk == 0, nameRVA == 0, firstThunk == 0 { break }
            if nameRVA != 0, let name = cString(atRVA: nameRVA, handle: handle) {
                names.append(name)
            }
            offset += 20
        }
        return names
    }

    private func delayImportNames(rva: UInt32, handle: FileHandle) -> [String] {
        guard var offset = fileOffset(forRVA: rva) else { return [] }
        var names: [String] = []
        for _ in 0 ..< Self.maxImportDescriptors {
            // ImgDelayDescr: Attributes, DllNameRVA, then six more DWORDs.
            guard let attributes = handle.extract(UInt32.self, offset: offset),
                  let rawName = handle.extract(UInt32.self, offset: offset + 4),
                  rawName != 0
            else { break }
            // Attribute bit 0 clear is the VC6-era layout, which stores
            // virtual addresses rather than RVAs.
            var nameRVA = rawName
            if attributes & 1 == 0, let imageBase = optionalHeader?.imageBase,
               UInt64(rawName) > imageBase {
                nameRVA = UInt32(truncatingIfNeeded: UInt64(rawName) - imageBase)
            }
            if let name = cString(atRVA: nameRVA, handle: handle) {
                names.append(name)
            }
            offset += 32
        }
        return names
    }

    private func cString(atRVA rva: UInt32, handle: FileHandle) -> String? {
        guard let offset = fileOffset(forRVA: rva) else { return nil }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Self.maxDLLNameLength) else { return nil }
            let bytes = data.prefix { $0 != 0 }
            guard !bytes.isEmpty, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
            return String(bytes: bytes, encoding: .ascii)
        } catch {
            return nil
        }
    }
}

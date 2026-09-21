//
//  GamesEntry.swift
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

/// Why the Games folder refused something.
///
/// The cases carry the facts; the interface does the wording. WhiskyKit has no
/// string catalogue of its own, and inventing one for three messages would put
/// half the app's English in a place translators do not look. `errorDescription`
/// is the log's fallback, not what anybody reads on screen.
public enum GamesRootError: LocalizedError, Equatable {
    /// The path is not inside `C:\Games`, so nothing here will touch it.
    case outsideRoot
    case nameNotAllowed(String)
    case alreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .outsideRoot: "That location is outside the Games folder."
        case let .nameNotAllowed(name): "\"\(name)\" is not a name that can be used here."
        case let .alreadyExists(name): "\"\(name)\" already exists."
        }
    }
}

/// One row in the Games browser.
///
/// Its `url` has already been through ``GamesRoot/resolve(_:)``, so anything
/// holding one of these is holding a path that is inside the Games folder.
public struct GamesEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let size: Int64?
    public let modified: Date?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, isDirectory: Bool, size: Int64? = nil, modified: Date? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }

    /// A Windows program this app can start.
    public var isExecutable: Bool {
        !isDirectory && url.pathExtension.lowercased() == "exe"
    }

    /// Something that installs a game rather than being one.
    ///
    /// `.msi` is always an installer. An `.exe` is a guess from its name,
    /// which is why this only ever *offers* Install — it never decides on the
    /// user's behalf, and Play stays available on the same file.
    public var isInstaller: Bool {
        guard !isDirectory else { return false }
        let ext = url.pathExtension.lowercased()
        if ext == "msi" { return true }
        guard ext == "exe" else { return false }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["setup", "install", "installer", "autorun"].contains { stem.contains($0) }
    }

    /// Folders first, then names the way Finder orders them.
    public static func folderFirstByName(_ first: GamesEntry, _ second: GamesEntry) -> Bool {
        if first.isDirectory != second.isDirectory { return first.isDirectory }
        return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }
}

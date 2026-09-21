//
//  GamesRoot.swift
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

/// The one folder a casual user is allowed to see: `C:\Games` inside the main
/// bottle.
///
/// Everything the Games browser does goes through ``resolve(_:)`` first. That
/// is the whole point of this type — a single funnel that canonicalizes a
/// path, follows every symlink in it, and refuses anything that lands outside
/// the root. Navigation, drag and drop, New Folder, rename, and every path
/// handed to the launch code are all the same question, so they get the same
/// answer from the same place.
///
/// The browser shows `C:\Games\…` because that is what the game sees, but the
/// real directory is `<bottle>/drive_c/Games`; Wine's `dosdevices/c:` is a
/// symlink to `drive_c`, so the two are the same bytes on disk.
public struct GamesRoot: Sendable, Equatable, Hashable {
    /// The real directory, canonicalized at construction.
    public let url: URL

    /// How the root is written in the interface.
    public static let displayRoot = "C:\\Games"

    /// The Games folder of a bottle. Does not create anything; see
    /// ``createIfNeeded()``.
    public init(bottleURL: URL) {
        self.init(
            directory: bottleURL.appending(path: "drive_c").appending(path: "Games")
        )
    }

    /// An explicit directory. Used by tests and by any future second root.
    public init(directory: URL) {
        // Canonical from the start: if the root itself were left holding a
        // symlink, every containment check below would compare a resolved
        // candidate against an unresolved root and reject everything.
        self.url = Self.canonical(directory)
    }

    /// One spelling for one file.
    ///
    /// `resolvingSymlinksInPath()` marks a path that exists *and is a
    /// directory* with a trailing slash, and leaves one that does not exist
    /// without it — so the same folder compares unequal to itself depending on
    /// whether it has been created yet. Everything here is rebuilt from the
    /// resolved path string instead, which has no trailing slash either way.
    private static func canonical(_ url: URL) -> URL {
        URL(
            filePath: url.resolvingSymlinksInPath().path(percentEncoded: false),
            directoryHint: .notDirectory
        )
    }

    /// Creates the Games folder if it is missing, and returns a root whose
    /// `url` is canonical for the folder that now exists.
    ///
    /// Creating it changes the canonical form when an ancestor is a symlink,
    /// which is why this hands back a fresh value rather than mutating.
    @discardableResult
    public func createIfNeeded() throws -> GamesRoot {
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return GamesRoot(directory: url)
    }

    public var exists: Bool {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory
        )
        return found && isDirectory.boolValue
    }

    // MARK: - The funnel

    /// Canonicalizes `candidate` and returns it only if it is the root or lies
    /// inside it.
    ///
    /// Returns `nil` for anything else: a path above the root, an absolute
    /// path somewhere else entirely, a symlink whose target is outside, or a
    /// path that tries to climb with `..`.
    public func resolve(_ candidate: URL) -> URL? {
        guard candidate.isFileURL else { return nil }
        // `..` is refused before anything else touches the path. Standardizing
        // it away lexically — which `resolvingSymlinksInPath()` will do for a
        // component that does not exist yet — cancels it against whatever name
        // precedes it, and if that name is a symlink the cancellation is a lie
        // that steps somewhere the real filesystem never would. Nothing this
        // browser does needs to climb, so the honest answer is no.
        guard !candidate.pathComponents.contains("..") else { return nil }

        let resolved = Self.canonical(candidate)
        guard contains(resolved) else { return nil }
        return resolved
    }

    /// Resolves a path stored relative to the root, such as a saved shortcut.
    ///
    /// Accepts both separators, because the interface says `Metro Exodus\game.exe`
    /// while storage uses `Metro Exodus/game.exe`.
    public func resolve(relativePath: String) -> URL? {
        let parts = relativePath
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .map(String.init)
        guard !parts.isEmpty else { return nil }
        guard !parts.contains("..") else { return nil }
        // A leading separator made this absolute; the split dropped it, so
        // check the original rather than trusting the pieces.
        guard !relativePath.hasPrefix("/"), !relativePath.hasPrefix("\\") else { return nil }
        // A Windows drive letter is absolute too, and would otherwise be taken
        // for a folder name.
        guard !isDriveQualified(parts[0]) else { return nil }

        var candidate = url
        for part in parts {
            candidate = candidate.appending(path: part)
        }
        return resolve(candidate)
    }

    /// The path of `url` relative to the root, or `nil` if it is not inside it.
    ///
    /// This is what a shortcut stores, so that moving the bottle — or the whole
    /// container — does not break it.
    public func relativePath(for target: URL) -> String? {
        guard let resolved = resolve(target) else { return nil }
        let extra = resolved.pathComponents.dropFirst(url.pathComponents.count)
        guard !extra.isEmpty else { return "" }
        return extra.joined(separator: "/")
    }

    /// How a path is written on screen: `C:\Games\Metro Exodus\MetroExodus.exe`.
    public func displayPath(for target: URL) -> String? {
        guard let relative = relativePath(for: target) else { return nil }
        guard !relative.isEmpty else { return Self.displayRoot }
        return Self.displayRoot + "\\" + relative.replacingOccurrences(of: "/", with: "\\")
    }

    /// The trail of folders from the root down to `target`, for a breadcrumb.
    ///
    /// The first element is always the root itself, which is why there is no
    /// "up" button to draw at the top: there is nothing before it.
    public func breadcrumb(to target: URL) -> [(name: String, url: URL)] {
        guard let resolved = resolve(target) else { return [(name: "Games", url: url)] }
        var trail: [(name: String, url: URL)] = [(name: "Games", url: url)]
        var walk = url
        for component in resolved.pathComponents.dropFirst(url.pathComponents.count) {
            walk = walk.appending(path: component)
            trail.append((name: component, url: walk))
        }
        return trail
    }

    /// The parent of `target`, or `nil` when `target` is the root.
    ///
    /// Returning `nil` at the root is what stops the browser climbing out: it
    /// has no parent to offer, so it draws no way up.
    public func parent(of target: URL) -> URL? {
        guard let resolved = resolve(target), resolved != url else { return nil }
        return resolve(resolved.deletingLastPathComponent())
    }

    /// Whether `target` is the root or inside it, after canonicalization.
    public func isInside(_ target: URL) -> Bool {
        resolve(target) != nil
    }

    // MARK: - Listing

    /// What is in `directory`, ready to draw.
    ///
    /// Anything that does not survive ``resolve(_:)`` is left out — in
    /// practice a symlink pointing outside the Games folder. It is hidden
    /// rather than shown-and-disabled on purpose: a row the browser will not
    /// open, will not launch and will not let you rename is not a row, and
    /// showing it only invites someone to try.
    ///
    /// - Throws: whatever `FileManager` throws when `directory` cannot be read.
    public func contents(of directory: URL) throws -> [GamesEntry] {
        guard let resolved = resolve(directory) else { return [] }
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return urls
            .compactMap { child -> GamesEntry? in
                guard let safe = resolve(child) else { return nil }
                let values = try? safe.resourceValues(forKeys: Set(keys))
                return GamesEntry(
                    url: safe,
                    isDirectory: values?.isDirectory ?? false,
                    size: values?.fileSize.map(Int64.init),
                    modified: values?.contentModificationDate
                )
            }
            .sorted(by: GamesEntry.folderFirstByName)
    }

    /// The total size of everything under the root, for the Storage section.
    ///
    /// Walks the tree rather than asking for a directory's size, because a
    /// directory's own `fileSize` is the size of its entry, not its contents.
    public func usedBytes() -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in walker {
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    // MARK: - Changing things

    /// Makes a folder inside `parent`.
    ///
    /// - Returns: the new folder, already resolved.
    @discardableResult
    public func createFolder(named name: String, in parent: URL) throws -> URL {
        let target = try validated(name: name, in: parent)
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            throw GamesRootError.alreadyExists(name)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    /// Renames a file or folder in place.
    @discardableResult
    public func rename(_ item: URL, to name: String) throws -> URL {
        guard let source = resolve(item), source != url else { throw GamesRootError.outsideRoot }
        let target = try validated(name: name, in: source.deletingLastPathComponent())
        guard target != source else { return source }
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            throw GamesRootError.alreadyExists(name)
        }
        try FileManager.default.moveItem(at: source, to: target)
        return target
    }

    /// Moves a file or folder to the Trash.
    ///
    /// The Trash rather than a delete, always: this browser is pointed at a
    /// folder full of games somebody spent a night downloading, and nothing in
    /// it should be unrecoverable by accident. The root itself cannot be
    /// trashed.
    public func moveToTrash(_ item: URL) throws {
        guard let target = resolve(item), target != url else { throw GamesRootError.outsideRoot }
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
    }

    /// A name the browser is willing to create, resolved against `parent`.
    private func validated(name: String, in parent: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            throw GamesRootError.nameNotAllowed(name)
        }
        // A separator in a "name" is a path, and a path is how you leave. `:`
        // is a separator to the Finder and a drive marker to Windows.
        guard !trimmed.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" }) else {
            throw GamesRootError.nameNotAllowed(name)
        }
        // A leading dot would make it invisible, and the listing skips hidden
        // entries — the folder would be created and then never appear.
        guard !trimmed.hasPrefix(".") else { throw GamesRootError.nameNotAllowed(name) }

        guard let base = resolve(parent),
              let target = resolve(base.appending(path: trimmed))
        else { throw GamesRootError.outsideRoot }
        return target
    }

    // MARK: - Internals

    private func contains(_ resolved: URL) -> Bool {
        let rootParts = url.pathComponents
        let parts = resolved.pathComponents
        guard parts.count >= rootParts.count else { return false }
        // Component-wise, not a string prefix: `…/Games Backup` starts with
        // `…/Games` as text while being a different directory entirely.
        return Array(parts.prefix(rootParts.count)) == rootParts
    }

    private func isDriveQualified(_ component: String) -> Bool {
        guard component.count == 2, component.hasSuffix(":") else { return false }
        return component.first?.isLetter == true
    }
}

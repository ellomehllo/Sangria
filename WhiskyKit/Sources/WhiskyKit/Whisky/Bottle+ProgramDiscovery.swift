//
//  Bottle+ProgramDiscovery.swift
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

/// Finding the programs a bottle has installed.
///
/// Its own file because it is a pure filesystem walk with no actor-isolated
/// state — the rest of ``Bottle`` is the live object the interface observes.
extension Bottle {
    public nonisolated static let noiseExecutableNames: Set<String> = [
        "steamerrorreporter.exe",
        "steamerrorreporter64.exe",
        "steamservice.exe",
        "steamwebhelper.exe",
        "steam_monitor.exe",
        "steamsysinfo.exe",
        "steamxboxutil.exe",
        "crashreport.exe",
        "installermessage.exe",
        "crashreporter.exe",
        "crashhandler.exe",
        "crashpad_handler.exe",
        "gameoverlayui.exe",
        "gameoverlayui64.exe",
        "fossilize-replay.exe",
        "fossilize-replay64.exe",
        "gldriverquery.exe",
        "gldriverquery64.exe",
        "hardwareupdater.exe",
        "secure_desktop_capture.exe",
        "writeminidump.exe",
        "vc_redist.x86.exe",
        "vc_redist.x64.exe",
        "vcredist_x86.exe",
        "vcredist_x64.exe",
        "ueprereqsetup_x86.exe",
        "ueprereqsetup_x64.exe",
        "crossover html engine.exe"
    ]

    /// The folders under `drive_c` that a program scan walks.
    ///
    /// `Games` is here because that is where this app puts games and where the
    /// Games browser points; without it every game in `C:\Games` was invisible
    /// to the Installed Programs list, so the pin controls that list offers
    /// could not reach a single one of them.
    ///
    /// A list rather than three hard-coded names so that an installer landing
    /// somewhere else — which they do — can be covered by adding one entry.
    public nonisolated static let programScanRoots = [
        "Program Files",
        "Program Files (x86)",
        "Games"
    ]

    /// Walks the bottle's program directories (see ``programScanRoots``) and
    /// returns the URLs of installed `.exe` files, excluding ClickOnce cache
    /// artifacts, known noise executables, uninstallers, and anything in
    /// `blocklist`.
    ///
    /// This is a pure filesystem read with no actor-isolated state, so callers
    /// can run it off the main actor — it's the heavy part of repopulating
    /// ``programs`` for a large bottle.
    ///
    /// - Parameters:
    ///   - driveC: The bottle's `drive_c` directory.
    ///   - blocklist: User-blocked program URLs to omit.
    /// - Returns: Discovered executable URLs in filesystem-enumeration order.
    public nonisolated static func discoverInstalledExecutables(
        driveC: URL,
        blocklist: Set<URL>
    ) -> [URL] {
        var found: [URL] = []
        // Canonicalized once, then compared as paths. `FileManager`'s
        // enumerator hands back symlink-resolved URLs (`/private/var/…`) while
        // a URL built with `appending(path:)` keeps the unresolved form
        // (`/var/…`): the same file, unequal both as URLs and as raw path
        // strings. Blocking was failing silently on exactly that. Resolved here
        // rather than per enumerated file, which would be a syscall apiece
        // across the whole of Program Files.
        let blockedPaths = Set(blocklist.map(canonicalPath(of:)))
        for folderName in programScanRoots {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath, url.pathExtension == "exe" else { continue }
                // Skip ClickOnce cache executables (noisy internal artifacts)
                guard !url.path.contains("/Apps/2.0/") else { continue }
                // Skip known launcher helpers and crash reporters that pollute the list
                guard !noiseExecutableNames.contains(url.lastPathComponent.lowercased()) else { continue }
                // Inno Setup leaves unins000.exe, unins001.exe and so on beside
                // the game. Numbered, so a name list cannot catch them, and a
                // game folder usually holds several.
                guard !isUninstaller(url) else { continue }
                guard !blockedPaths.contains(canonicalPath(of: url)) else { continue }
                found.append(url)
            }
        }
        return found
    }

    /// The one spelling of a file's path that two URLs naming it will agree on.
    ///
    /// `resolvingSymlinksInPath()` is not enough: it leaves `/var/…` alone
    /// while `FileManager`'s enumerator hands back `/private/var/…` for the
    /// very same file, so the two compare unequal as URLs *and* as path
    /// strings. `canonicalPathKey` asks the filesystem instead. Falls back to
    /// the plain path for a file that no longer exists, which is the only case
    /// it cannot answer.
    public nonisolated static func canonicalPath(of url: URL) -> String {
        let canonical = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        return canonical ?? url.path(percentEncoded: false)
    }

    /// Whether this executable is an uninstaller rather than something to run.
    nonisolated static func isUninstaller(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return stem.hasPrefix("unins") || stem == "uninstall" || stem == "uninstaller"
    }

    /// Runs a program rescan, coalescing concurrent callers onto one scan.
    ///
    /// If a scan is already in flight this awaits *that* scan instead of starting
    /// a duplicate or returning early. The distinction matters versus an
    /// early-return guard: a caller that bailed out would then read whatever
    /// ``programs`` happened to hold (e.g. the Start Menu auto-pin pinning against
    /// an empty list), whereas awaiting means the caller observes the in-flight
    /// scan's freshly published results before it proceeds. The owning call clears
    /// the handle when its scan finishes, so the next call starts a fresh scan.
    ///
    /// The coalesced result reflects the in-flight scan, which began at the
    /// *owning* call — so a caller that must observe a change it made after that
    /// scan started should rescan once the current one completes.
    ///
    /// - Parameter scan: The rescan body; should publish into ``programs`` and
    ///   manage ``programsLoading``. Only the owning call runs it — coalesced
    ///   callers just await the shared result.
    public func coalesceProgramScan(_ scan: @escaping @MainActor () async -> Void) async {
        if let existing = programScanTask {
            await existing.value
            return
        }
        let task = Task { @MainActor in await scan() }
        programScanTask = task
        defer { programScanTask = nil }
        await task.value
    }

    // MARK: - Equatable

    public nonisolated static func == (lhs: Bottle, rhs: Bottle) -> Bool {
        lhs.url == rhs.url
    }

    // MARK: - Hashable

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    // MARK: - Comparable

    public static func < (lhs: Bottle, rhs: Bottle) -> Bool {
        lhs.settings.name.lowercased() < rhs.settings.name.lowercased()
    }
}

// MARK: - Program Sequence Extensions

@MainActor
public extension Sequence where Iterator.Element == Program {
    /// Returns only the pinned programs from the sequence.
    ///
    /// Use this to filter a collection of programs to show favorites or
    /// frequently-used applications.
    var pinned: [Program] {
        self.filter(\.pinned)
    }

    /// Returns only the unpinned programs from the sequence.
    ///
    /// Use this alongside ``pinned`` to separate programs into categories
    /// in the user interface.
    var unpinned: [Program] {
        self.filter { !$0.pinned }
    }
}

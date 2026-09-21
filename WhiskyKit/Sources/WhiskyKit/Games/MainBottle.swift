//
//  MainBottle.swift
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

/// What a bottle is for.
///
/// A bottle is a Wine prefix, which is an implementation detail nobody should
/// have to learn to play a game. Casual mode therefore never says the word and
/// runs everything in one bottle — this is how it knows which one.
///
/// ``compatibility`` is reserved rather than implemented: a second prefix for
/// awkward titles is a plausible next step, and leaving room for it costs one
/// case. Nothing creates or selects a compatibility bottle today.
public enum BottleRole: String, Codable, Sendable, CaseIterable {
    /// Never assigned a role. The resolver decides from what is on disk.
    case unset
    /// The bottle everything runs in.
    case main
    /// Reserved for a future second bottle for awkward titles. Unused.
    case compatibility
}

/// One bottle, reduced to what choosing between them needs.
public struct BottleCandidate: Sendable, Equatable, Hashable {
    public let url: URL
    public let role: BottleRole
    /// Whether this prefix already has a `drive_c/Games` folder.
    public let hasGamesFolder: Bool
    /// Whether the prefix is on disk and readable.
    public let isAvailable: Bool

    public init(url: URL, role: BottleRole, hasGamesFolder: Bool, isAvailable: Bool) {
        self.url = url
        self.role = role
        self.hasGamesFolder = hasGamesFolder
        self.isAvailable = isAvailable
    }

    /// Reads the two facts that are not already in settings.
    public init(url: URL, settings: BottleSettings) {
        self.init(
            url: url,
            role: settings.role,
            hasGamesFolder: GamesRoot(bottleURL: url).exists,
            isAvailable: FileManager.default.fileExists(
                atPath: url.appending(path: "drive_c").path(percentEncoded: false)
            )
        )
    }
}

/// Picks the one bottle casual mode uses.
///
/// Deliberately a pure function over facts, so the decision can be tested
/// without a Wine prefix and so it cannot quietly create, move or merge
/// anything. Nothing here writes.
public enum MainBottleResolver {
    /// The bottle to run everything in, or `nil` when there is none to pick.
    ///
    /// In order: a bottle the user marked as the main one; the bottle that
    /// already holds the games; whatever is left. The middle rule is the one
    /// that matters on an existing install — the games are already somewhere,
    /// and that somewhere is the answer.
    public static func choose(from candidates: [BottleCandidate]) -> BottleCandidate? {
        let usable = candidates.filter(\.isAvailable)
        guard !usable.isEmpty else { return nil }

        // Sorted by path so that a tie — two bottles marked main, two holding
        // games — resolves the same way on every launch instead of following
        // whatever order the registry happened to hand over.
        let ordered = usable.sorted { $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false) }

        if let chosen = ordered.first(where: { $0.role == .main }) {
            return chosen
        }
        if let withGames = ordered.first(where: \.hasGamesFolder) {
            return withGames
        }
        return ordered.first
    }

    /// The Games folder of the chosen bottle.
    public static func gamesRoot(from candidates: [BottleCandidate]) -> GamesRoot? {
        guard let bottle = choose(from: candidates) else { return nil }
        return GamesRoot(bottleURL: bottle.url)
    }
}

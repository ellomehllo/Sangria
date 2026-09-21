//
//  MainBottleTests.swift
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

@Suite("Casual mode picks one bottle")
struct MainBottleTests {
    private func candidate(
        _ name: String,
        role: BottleRole = .unset,
        games: Bool = false,
        available: Bool = true
    ) -> BottleCandidate {
        BottleCandidate(
            url: URL(filePath: "/Bottles/\(name)"),
            role: role,
            hasGamesFolder: games,
            isAvailable: available
        )
    }

    @Test("With nothing to choose from there is no main bottle")
    func noBottles() {
        #expect(MainBottleResolver.choose(from: []) == nil)
    }

    @Test("One bottle is the main bottle")
    func onlyOne() {
        let only = candidate("A")
        #expect(MainBottleResolver.choose(from: [only]) == only)
    }

    @Test("The bottle holding the games wins over one that does not")
    func gamesFolderWins() {
        let empty = candidate("A")
        let games = candidate("B", games: true)
        #expect(MainBottleResolver.choose(from: [empty, games]) == games)
        // And the order it was handed them in makes no difference.
        #expect(MainBottleResolver.choose(from: [games, empty]) == games)
    }

    @Test("An explicit choice beats the games folder")
    func explicitRoleWins() {
        let games = candidate("A", games: true)
        let chosen = candidate("B", role: .main)
        #expect(MainBottleResolver.choose(from: [games, chosen]) == chosen)
    }

    @Test("A bottle that is not on disk is never chosen")
    func unavailableIsSkipped() {
        let missing = candidate("A", role: .main, games: true, available: false)
        let present = candidate("B")
        #expect(MainBottleResolver.choose(from: [missing, present]) == present)
        #expect(MainBottleResolver.choose(from: [missing]) == nil)
    }

    @Test("A tie resolves the same way every time")
    func tiesAreStable() {
        let first = candidate("A", games: true)
        let second = candidate("B", games: true)
        #expect(MainBottleResolver.choose(from: [first, second]) == first)
        #expect(MainBottleResolver.choose(from: [second, first]) == first)
    }

    @Test("A compatibility bottle is not treated as the main one")
    func compatibilityIsNotMain() {
        let compat = candidate("A", role: .compatibility, games: true)
        let plain = candidate("B")
        // It still wins here, but on the games folder rather than its role —
        // a bottle marked compatibility is not a bottle marked main.
        #expect(MainBottleResolver.choose(from: [compat, plain]) == compat)
        let realMain = candidate("C", role: .main)
        #expect(MainBottleResolver.choose(from: [compat, realMain]) == realMain)
    }

    @Test("The Games root follows the chosen bottle")
    func gamesRootFollows() throws {
        let chosen = candidate("B", role: .main)
        let root = try #require(MainBottleResolver.gamesRoot(from: [candidate("A", games: true), chosen]))
        #expect(root.url.path(percentEncoded: false) == "/Bottles/B/drive_c/Games")
    }

    // MARK: - Storage

    @Test("A bottle written before roles existed decodes as unset")
    func legacySettingsHaveNoRole() throws {
        let legacy = """
        {"info": {"name": "Games XO", "pins": [], "blocklist": []}}
        """
        let decoded = try JSONDecoder().decode(BottleSettings.self, from: Data(legacy.utf8))
        #expect(decoded.role == .unset)
        #expect(decoded.name == "Games XO")
    }

    @Test("A role round-trips through the bottle's plist")
    func roleSurvivesEncoding() throws {
        var settings = BottleSettings()
        settings.role = .main
        let encoded = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: encoded)
        #expect(decoded.role == .main)
    }
}

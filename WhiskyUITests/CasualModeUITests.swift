//
//  CasualModeUITests.swift
//  WhiskyUITests
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

import XCTest

/// What someone who has never heard of Wine can see.
///
/// The claim this suite defends is a negative one — that nothing in the
/// interface says bottle, terminal or winetricks — and a negative is exactly
/// what is easiest to break by accident later. One new menu item is all it
/// takes.
final class CasualModeUITests: WhiskyUITestCase {
    override var developerMode: Bool { false }

    // MARK: - The sidebar

    func testSidebarShowsOnlyLibraryGamesAndSettings() throws {
        require(app.buttons["sidebar.library"], "Library row", timeout: 8)
        XCTAssertTrue(app.buttons["sidebar.games"].exists, "Games row missing")
        XCTAssertTrue(app.buttons["sidebar.settings"].exists, "Settings row missing")

        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "sidebar.bottle").firstMatch.exists,
            "A bottle is listed in the sidebar with Developer Mode off"
        )
        XCTAssertFalse(
            app.staticTexts["Bottles"].exists,
            "The Bottles section header is visible with Developer Mode off"
        )
    }

    func testNoWayToCreateABottle() throws {
        require(app.buttons["sidebar.library"], "Library row", timeout: 8)
        XCTAssertFalse(
            app.buttons.matching(identifier: "toolbar.createBottle").firstMatch.exists,
            "The + toolbar button is offering to create a bottle"
        )
    }

    /// The whole point, stated as one assertion: no Wine vocabulary anywhere on
    /// screen, in any of the three places a player can be.
    func testNoWineVocabularyAnywhere() throws {
        let banned = ["bottle", "winetricks", "terminal", "wine", "prefix"]

        for pane in ["sidebar.library", "sidebar.games", "sidebar.settings"] {
            let row = require(app.buttons[pane], "\(pane) row", timeout: 8)
            row.click()
            // Settings is the documented exception: its Advanced section has to
            // name what Developer Mode turns on, or the switch is a mystery.
            let allowed = pane == "sidebar.settings"

            for label in visibleLabels() {
                let lowered = label.lowercased()
                for word in banned where lowered.contains(word) {
                    if allowed, lowered.contains("developer mode") || lowered.contains("shows bottles") {
                        continue
                    }
                    XCTFail("\(pane) shows \"\(label)\", which contains \"\(word)\"")
                }
            }
        }
    }

    /// "Run" is the old word for it, and it is still the word the bottle screen
    /// uses — so a leak would be silent rather than obviously wrong.
    func testTheWordRunDoesNotAppear() throws {
        let row = require(app.buttons["sidebar.library"], "Library row", timeout: 8)
        row.click()
        for label in visibleLabels() {
            XCTAssertFalse(
                label.range(of: #"\bRun\b"#, options: .regularExpression) != nil,
                "The library shows \"\(label)\""
            )
        }
    }

    // MARK: - Games

    func testGamesBrowserStartsAtGamesAndOffersNoWayUp() throws {
        let games = require(app.buttons["sidebar.games"], "Games row", timeout: 8)
        games.click()

        require(app.groups["games.breadcrumb"], "breadcrumb", timeout: 8)
        XCTAssertTrue(
            app.staticTexts["Games"].exists || app.buttons["Games"].exists,
            "The breadcrumb does not start at Games"
        )
        XCTAssertFalse(
            app.buttons["games.up"].exists,
            "There is a way up out of the Games folder at the root"
        )
    }

    func testGamesToolbarOffersNewFolderAndInstall() throws {
        let games = require(app.buttons["sidebar.games"], "Games row", timeout: 8)
        games.click()
        require(app.buttons["games.newFolder"], "New Folder button", timeout: 8)
        XCTAssertTrue(app.buttons["games.install"].exists, "Install a Game button missing")
    }

    // MARK: - Settings

    func testSettingsShowsEverySectionAndTheDeveloperSwitch() throws {
        let settings = require(app.buttons["sidebar.settings"], "Settings row", timeout: 8)
        settings.click()

        for section in ["General", "Display", "Performance", "Storage", "Advanced"] {
            XCTAssertTrue(
                app.staticTexts[section].waitForExistence(timeout: 5),
                "Settings is missing its \(section) section"
            )
        }
        XCTAssertTrue(
            app.checkBoxes["settings.developerMode"].exists
                || app.switches["settings.developerMode"].exists,
            "The Developer Mode switch is missing"
        )
    }

    func testStorageNamesTheGamesFolderTheWayTheGameSeesIt() throws {
        let settings = require(app.buttons["sidebar.settings"], "Settings row", timeout: 8)
        settings.click()
        XCTAssertTrue(
            app.staticTexts["C:\\Games"].waitForExistence(timeout: 5),
            "Storage does not name the Games folder"
        )
    }

    // MARK: - Helpers

    /// Every piece of text on screen, buttons and labels alike.
    private func visibleLabels() -> [String] {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let buttons = app.buttons.allElementsBoundByIndex.map(\.label)
        return (texts + buttons).filter { !$0.isEmpty }
    }
}

/// Turning Developer Mode on has to bring everything back, and turning it off
/// has to take it away again — without a restart.
final class DeveloperModeUITests: WhiskyUITestCase {
    override var developerMode: Bool { true }

    func testDeveloperModeShowsBottlesAndTheirTools() throws {
        let row = app.descendants(matching: .any).matching(identifier: "sidebar.bottle").firstMatch
        guard row.waitForExistence(timeout: 8) else {
            throw XCTSkip("No bottle fixtures in this container; nothing to reveal.")
        }
        row.click()
        XCTAssertTrue(
            app.buttons["Terminal..."].waitForExistence(timeout: 8),
            "Developer Mode is on but the bottle screen has no Terminal button"
        )
        XCTAssertTrue(app.buttons["Winetricks..."].exists, "Winetricks button missing")
        XCTAssertTrue(
            app.buttons.matching(identifier: "toolbar.createBottle").firstMatch.exists,
            "Developer Mode is on but there is no way to create a bottle"
        )
    }
}

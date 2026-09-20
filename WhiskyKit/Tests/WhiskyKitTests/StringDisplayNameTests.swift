//
//  StringDisplayNameTests.swift
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

import Testing
@testable import WhiskyKit

@Suite("Executable names read back as titles")
struct StringDisplayNameTests {
    @Test("Camel case splits at its humps")
    func camelCase() {
        #expect("MetroExodus".titleCasedFromFileName == "Metro Exodus")
        #expect("TheWitcher3".titleCasedFromFileName == "The Witcher3")
    }

    @Test("Separators become spaces")
    func separators() {
        #expect("dark_souls_iii".titleCasedFromFileName == "dark souls iii")
        #expect("half-life".titleCasedFromFileName == "half life")
    }

    @Test("Acronyms are not broken apart")
    func acronyms() {
        #expect("RE2".titleCasedFromFileName == "RE2")
        #expect("DOOM".titleCasedFromFileName == "DOOM")
        #expect("DOOMEternal".titleCasedFromFileName == "DOOM Eternal")
    }

    @Test("A name that already reads as a title is left alone")
    func alreadySpaced() {
        #expect("Resident Evil 2".titleCasedFromFileName == "Resident Evil 2")
        #expect("Grand Theft AutoV".titleCasedFromFileName == "Grand Theft AutoV")
    }

    @Test("Ordinary lowercase names pass through")
    func lowercase() {
        #expect("steam".titleCasedFromFileName == "steam")
        #expect("".titleCasedFromFileName == "")
    }
}

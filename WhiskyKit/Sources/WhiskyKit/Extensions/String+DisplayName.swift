//
//  String+DisplayName.swift
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

public extension String {
    /// This string as a title, for names that came from a filename.
    ///
    /// An executable is called `MetroExodus.exe` or `dark_souls_iii`, and that
    /// is what ends up on a library card unless something turns it back into
    /// the name on the box. Separators become spaces and camel case is split at
    /// its humps.
    ///
    /// Acronyms survive: the split only fires where a lowercase letter meets an
    /// uppercase one, or where a run of capitals is followed by a word, so
    /// `RE2` and `DOOM` stay whole while `DOOMEternal` becomes `DOOM Eternal`.
    /// A name that already reads as a title is returned unchanged, which is why
    /// a string that already contains a space is left alone entirely.
    var titleCasedFromFileName: String {
        let separated = replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Somebody already wrote this one out; second-guessing their spacing
        // only risks mangling it.
        guard !separated.contains(" ") else {
            return separated.trimmingCharacters(in: .whitespaces)
        }

        var result = ""
        let characters = Array(separated)
        for (index, character) in characters.enumerated() {
            if index > 0, character.isUppercase {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // "oE" in MetroExodus, or the "ME" of DOOMEternal where the M
                // starts a word of its own. A capital between two capitals is
                // inside an acronym and stays put.
                if previous.isLowercase || previous.isNumber || (next?.isLowercase ?? false) {
                    result.append(" ")
                }
            }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

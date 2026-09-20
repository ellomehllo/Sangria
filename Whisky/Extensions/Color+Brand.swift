//
//  Color+Brand.swift
//  Whisky
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

import SwiftUI

public extension Color {
    /// The red-pink end of the app's palette — the top of the S in the icon.
    ///
    /// Not a status colour. Anything that means "this went wrong" stays `.red`,
    /// because a brand colour that also signals failure teaches people to read
    /// the brand as a warning.
    ///
    /// Both brand colours are fixed rather than appearance-aware: they are the
    /// icon's own values, meant for dark artwork such as a library card. On a
    /// system background use `Color.accentColor`, which darkens in light mode
    /// to keep white text on it legible.
    static let brandPink = Color("BrandPink")

    /// The sky-blue end of the palette. `Color.accentColor` is the same hue,
    /// adjusted per appearance for use on system backgrounds.
    static let brandBlue = Color("BrandBlue")
}

public extension LinearGradient {
    /// The icon's own sweep, pink through to blue, on the diagonal it runs on
    /// there. Used where a control should read as the app itself rather than as
    /// a system control — the play button on a library card, and little else.
    static var brand: LinearGradient {
        LinearGradient(
            colors: [.brandPink, .brandBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

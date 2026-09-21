//
//  SettingsView.swift
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
import WhiskyKit

/// What ⌘, opens.
///
/// The same settings the sidebar shows, rather than a second set. Two windows
/// offering different subsets of the same switches is how an app ends up with
/// two answers to "did I turn that on?" — and the old Settings window was
/// exactly that, with a terminal picker and a bottle location in it.
struct SettingsView: View {
    var body: some View {
        GameSettingsView()
            .frame(width: ViewWidth.medium)
            .frame(maxHeight: 640)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
        .environmentObject(BottleVM.shared)
}

//
//  ProcessRegistry+Notifications.swift
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

public extension Notification.Name {
    /// Posted after a Wine process starts or stops being tracked.
    ///
    /// Which one changed does not matter; whether *anything* is running does.
    /// It is how the app can follow that without polling, and it is the one
    /// point every way of starting a game passes through — there are five, and
    /// a sixth would otherwise have to remember to announce itself.
    static let wineProcessesChanged = Notification.Name("wineProcessesChanged")
}

extension ProcessRegistry {
    /// Tells anyone listening that the set of running processes moved.
    ///
    /// Deferred off the caller's thread: an observer that asks the registry
    /// what is running would otherwise deadlock against the lock the caller
    /// is still holding.
    func announceChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wineProcessesChanged, object: nil)
        }
    }
}

//
//  BottleVM+MainBottle.swift
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

import Foundation
import WhiskyKit

/// Which bottle casual mode runs everything in.
///
/// Its own file because it is its own concern: the rest of ``BottleVM`` is
/// about making and listing prefixes, and this is about never having to
/// mention that there is more than one.
extension BottleVM {
    /// The bottle everything runs in, or `nil` when there is none.
    var mainBottle: Bottle? {
        guard let mainBottleURL else { return nil }
        return bottles.first { $0.url == mainBottleURL }
    }

    /// The Games folder of that bottle.
    var gamesRoot: GamesRoot? {
        mainBottle.map { GamesRoot(bottleURL: $0.url) }
    }

    /// Which bottle should be the main one, given what is on disk now.
    ///
    /// Returns rather than assigns so that `mainBottleURL` keeps its
    /// `private(set)`: the only place that writes it is `loadBottles()`, which
    /// is the only place it can change.
    ///
    /// Worked out on load rather than computed on demand, because choosing
    /// stats the filesystem once per bottle and the answer is read from view
    /// bodies.
    func chosenMainBottleURL() -> URL? {
        let candidates = bottles.map { bottle in
            BottleCandidate(
                url: bottle.url,
                role: bottle.settings.role,
                hasGamesFolder: GamesRoot(bottleURL: bottle.url).exists,
                isAvailable: bottle.isAvailable
            )
        }
        return MainBottleResolver.choose(from: candidates)?.url
    }

    /// Makes the one bottle casual mode needs, if there is not one already.
    ///
    /// A player who has just installed Sangria has nowhere to put a game, and
    /// "create a bottle" is not a question they can be asked — it is the first
    /// word of the vocabulary this whole change exists to remove. So the app
    /// makes it, once, and never mentions it.
    ///
    /// Creates nothing when a bottle already exists, when the Wine runtime is
    /// not installed yet (the setup sheet is showing, and creation would fail),
    /// or when a creation is already in flight.
    func ensureMainBottleExists() {
        guard bottles.isEmpty, !isCreatingFirstBottle else { return }
        guard WhiskyWineInstaller.isWhiskyWineInstalled() else { return }

        isCreatingFirstBottle = true
        _ = createNewBottle(
            bottleName: String(localized: "bottle.default.name"),
            winVersion: .win10,
            bottleURL: BottleData.defaultBottleDir
        )
    }

    /// Re-registers bottles that are on disk but missing from the list.
    ///
    /// In normal mode this happens without asking. The alert it replaces talks
    /// about bottles and re-importing, and the honest answer for someone who
    /// only wants to play a game is that their games came back — re-importing
    /// only adds paths that already exist and changes nothing on disk.
    func reimportOrphansSilently() {
        guard !orphanedBottles.isEmpty else { return }
        reimportOrphanedBottles()
    }

    /// Gives the main bottle's shortcuts their path relative to `C:\Games`.
    ///
    /// Additive and idempotent, so running it on every load costs one pass
    /// over the pins and nothing else.
    func migrateShortcutsToRelativePaths() {
        guard let bottle = mainBottle else { return }
        let root = GamesRoot(bottleURL: bottle.url)
        guard root.exists else { return }
        var settings = bottle.settings
        if settings.migratePinsToRelativePaths(gamesRoot: root) {
            bottle.settings = settings
        }
    }
}

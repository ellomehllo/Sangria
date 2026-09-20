//
//  FrameRateLimiter.swift
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

/// Holds a Wine process to a frame rate, whatever graphics backend it uses.
///
/// None of the backends can be asked to do it themselves here: DXMT 0.80
/// reads `d3d11.preferredMaxFrameRate` and ignores it, D3DMetal 4.0's
/// `D3DM_MAX_FPS` belongs to its windowless render-to-file mode, and both
/// present at the display rate whatever sync interval a game passes. What
/// they share, with MoltenVK under DXVK and vkd3d, is Metal: every frame starts
/// with `-[CAMetalLayer nextDrawable]`. `libsangriafps.dylib`, built from
/// `Whisky/FrameLimiter/sangria_fps.c` into the app's Resources and loaded
/// with `DYLD_INSERT_LIBRARIES`, paces that call. Wine's binaries are unsigned
/// x86_64, so dyld honours the variable for them.
public enum FrameRateLimiter {
    /// The frame rate the limiter reads. Unset or zero leaves a process as is.
    public static let rateVariable = "SANGRIA_MAX_FPS"
    /// How the limiter gets into the process.
    public static let insertVariable = "DYLD_INSERT_LIBRARIES"
    /// Lets a tool running WhiskyKit outside the app, which has no Resources
    /// of its own, name a built limiter.
    static let libraryOverrideVariable = "SANGRIA_FPS_LIBRARY"

    /// The limiter the app ships, or the one a tool names.
    public static func libraryURL(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment[libraryOverrideVariable], !override.isEmpty {
            return URL(filePath: override)
        }
        return bundle.url(forResource: "libsangriafps", withExtension: "dylib")
    }

    /// The variables that hold a launch to `limit` frames per second.
    ///
    /// Empty when the limit is off or the limiter is missing, so an uncapped
    /// launch loads nothing extra.
    public static func environment(
        limit: Int,
        library: URL? = libraryURL()
    ) -> [(key: String, value: String)] {
        guard limit > 0, let library,
              FileManager.default.fileExists(atPath: library.path(percentEncoded: false))
        else { return [] }
        return [
            (key: insertVariable, value: library.path(percentEncoded: false)),
            (key: rateVariable, value: String(limit))
        ]
    }
}

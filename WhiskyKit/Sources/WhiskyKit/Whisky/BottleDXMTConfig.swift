//
//  BottleDXMTConfig.swift
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

/// DXMT tuning for a bottle, rendered into the bottle's `dxmt.conf`.
///
/// Only options the bundled DXMT (0.80) actually reads live here. The file is
/// regenerated from these values on every DXMT launch, so the bottle settings
/// stay the single source of truth and a hand edit to the file is not lost
/// silently: it goes in ``extraOptions`` instead.
public struct BottleDXMTConfig: Codable, Equatable {
    /// `d3d11.preferredMaxFrameRate`. Zero leaves pacing to the game.
    ///
    /// DXMT hands pacing to Metal and CoreAnimation, so the value should be a
    /// factor of the display's refresh rate: ask for 40 on a 60 Hz panel and
    /// you get 30.
    var frameRateLimit: Int = 0

    /// Whether `DXMT_METALFX_SPATIAL_SWAPCHAIN=1` is exported, which runs the
    /// swapchain through MetalFX spatial upscaling.
    var metalFXSpatial: Bool = false

    /// `d3d11.metalSpatialUpscaleFactor`, the output/source ratio. Only read
    /// when ``metalFXSpatial`` is on. DXMT documents 1.0 through 2.0.
    var metalFXUpscaleFactor: Double = 2.0

    /// Raw `key = value` lines appended after the managed options, for the
    /// DXMT settings the UI does not model (`dxgi.customVendorId`, ...).
    /// Later lines win in DXMT's parser, so these can override the above.
    var extraOptions: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.frameRateLimit = (try? container.decodeIfPresent(Int.self, forKey: .frameRateLimit)) ?? 0
        self.metalFXSpatial = (try? container.decodeIfPresent(Bool.self, forKey: .metalFXSpatial)) ?? false
        self.metalFXUpscaleFactor = (try? container.decodeIfPresent(Double.self, forKey: .metalFXUpscaleFactor))
            ?? 2.0
        self.extraOptions = (try? container.decodeIfPresent(String.self, forKey: .extraOptions)) ?? ""
    }
}

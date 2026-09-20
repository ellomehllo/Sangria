//
//  generate.swift
//  Sangria icon generator
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

// Draws the Sangria app icon: an S in the system font, rendered as a grid of
// glowing dots that run from red-pink through purple to sky blue, on nothing.
//
// The background is transparent by design — there is no squircle behind the
// letter. The dots along the glyph's outline fade out instead of stopping, so
// the S dissolves into the space around it rather than being cut from it.
//
// Run with:  swift tools/sangria-icon/generate.swift <output-dir>

import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Palette

struct RGB {
    var red: Double
    var green: Double
    var blue: Double

    static func mix(_ start: RGB, _ end: RGB, _ amount: Double) -> RGB {
        RGB(
            red: start.red + (end.red - start.red) * amount,
            green: start.green + (end.green - start.green) * amount,
            blue: start.blue + (end.blue - start.blue) * amount
        )
    }

    /// Towards white, which is what gives the dots their hot centres. The
    /// purple in the middle of the sweep is not a third stop — it is what these
    /// two make on the way past each other.
    func lightened(_ amount: Double) -> RGB {
        RGB.mix(self, RGB(red: 1, green: 1, blue: 1), amount)
    }

    func cgColor(alpha: Double) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

let pink = RGB(red: 1.00, green: 0.15, blue: 0.40)
let purple = RGB(red: 0.68, green: 0.33, blue: 0.96)
let blue = RGB(red: 0.18, green: 0.74, blue: 1.00)

/// The sweep across the letter: pink, through the purple the two of them make,
/// to sky blue. The middle is an explicit stop rather than a straight pink-blue
/// interpolation, which lands on a grey-mauve and reads as a smudge between two
/// colours rather than as a colour of its own.
func sweepColour(_ amount: Double) -> RGB {
    amount < 0.5
        ? RGB.mix(pink, purple, amount * 2)
        : RGB.mix(purple, blue, (amount - 0.5) * 2)
}

// MARK: - Geometry

/// The S, scaled to fill the canvas.
///
/// Taken from the system font so the letter matches the app's own type rather
/// than being drawn by hand.
func letterPath(canvas: Double, inset: Double) -> CGPath? {
    let font = NSFont.systemFont(ofSize: canvas, weight: .black) as CTFont
    var characters = Array("S".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1),
          let glyph = CTFontCreatePathForGlyph(font, glyphs[0], nil)
    else { return nil }

    let bounds = glyph.boundingBox
    guard bounds.width > 0, bounds.height > 0 else { return nil }

    // Fits the tighter axis so nothing clips, then centres what is left over.
    // The S is taller than it is wide, so it is widened a little to use more of
    // the canvas — enough to fill it, not enough to read as a squashed letter.
    let target = canvas - inset * 2
    let scale = min(target / bounds.width, target / bounds.height)
    let scaleX = min(scale * 1.05, target / bounds.width)
    var transform = CGAffineTransform.identity
        .translatedBy(
            x: (canvas - bounds.width * scaleX) / 2 - bounds.minX * scaleX,
            y: (canvas - bounds.height * scale) / 2 - bounds.minY * scale
        )
        .scaledBy(x: scaleX, y: scale)
    return glyph.copy(using: &transform)
}

/// A grayscale bitmap of the letter, which every dot is then sampled against.
func letterMask(size: Int, path: CGPath) -> [UInt8] {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(path)
    context.fillPath()

    guard let data = context.data else { return [] }
    let buffer = data.bindMemory(to: UInt8.self, capacity: size * size)
    return Array(UnsafeBufferPointer(start: buffer, count: size * size))
}

/// How much of the letter covers the disc around a point, from 0 outside to 1
/// well inside. Values in between are the outline, and they are what the fade
/// is made of: a dot reads its own distance from the edge without anyone having
/// to compute a distance field.
func coverage(mask: [UInt8], size: Int, centreX: Double, centreY: Double, radius: Double) -> Double {
    let minX = max(0, Int(centreX - radius)), maxX = min(size - 1, Int(centreX + radius))
    let minY = max(0, Int(centreY - radius)), maxY = min(size - 1, Int(centreY + radius))
    guard minX <= maxX, minY <= maxY else { return 0 }

    var total = 0.0
    var weight = 0.0
    let radiusSquared = radius * radius
    for y in minY ... maxY {
        for x in minX ... maxX {
            let dx = Double(x) + 0.5 - centreX
            let dy = Double(y) + 0.5 - centreY
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared <= radiusSquared else { continue }
            // Centre-weighted, so a dot is judged mostly by where it sits
            // rather than by what is happening at the rim of its sample.
            let sampleWeight = 1 - (distanceSquared / radiusSquared) * 0.7
            total += Double(mask[y * size + x]) / 255 * sampleWeight
            weight += sampleWeight
        }
    }
    return weight > 0 ? total / weight : 0
}

func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Drawing

func makeContext(size: Int) -> CGContext {
    CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

/// One dot: a white core inside a coloured body, inside a wider glow.
///
/// The glow is what makes a grid of flat circles read as light rather than as
/// confetti, and it is also what lets neighbouring dots bleed into each other
/// deep inside the letter where the S should feel solid.
func drawGlow(
    in context: CGContext,
    at point: CGPoint,
    radius: Double,
    colour: RGB,
    alpha: Double,
    space: CGColorSpace
) {
    let colours = [
        colour.cgColor(alpha: alpha * 0.30),
        colour.cgColor(alpha: 0)
    ] as CFArray
    guard let glow = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) else { return }
    context.drawRadialGradient(
        glow,
        startCenter: point, startRadius: 0,
        endCenter: point, endRadius: radius * 2.2,
        options: []
    )
}

func drawBody(
    in context: CGContext,
    at point: CGPoint,
    radius: Double,
    colour: RGB,
    alpha: Double,
    space: CGColorSpace
) {
    // A small hot core and then straight into the colour. Lightening most of
    // the dot washed the purple out of the middle of the sweep entirely, which
    // left the icon reading as pink-to-blue with a pale gap between them.
    let colours = [
        colour.lightened(0.92).cgColor(alpha: alpha),
        colour.lightened(0.20).cgColor(alpha: alpha),
        colour.cgColor(alpha: alpha * 0.92)
    ] as CFArray
    guard let body = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.3, 1]) else { return }
    context.drawRadialGradient(
        body,
        startCenter: point, startRadius: 0,
        endCenter: point, endRadius: radius,
        options: []
    )
}


// MARK: - Backdrop

/// Whether the art carries its own background.
///
/// macOS 26 draws every app icon inside the same rounded container and fills
/// whatever the art leaves transparent with a light grey. A transparent icon
/// therefore does not read as transparent on the Dock — it reads as a pale grey
/// tile, and glowing dots on pale grey are just washed-out dots. So the art
/// brings its own near-black backdrop and the dots glow against that; the
/// system still rounds and shadows it exactly as before.
///
/// Pass `--transparent` to get the free-form art instead, which is the right
/// file for anywhere that is not an app icon.
let wantsBackdrop = !CommandLine.arguments.contains("--transparent")

func drawBackdrop(in context: CGContext, canvas: Double, space: CGColorSpace) {
    let base = [
        RGB(red: 0.09, green: 0.08, blue: 0.12).cgColor(alpha: 1),
        RGB(red: 0.04, green: 0.03, blue: 0.06).cgColor(alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: base, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: canvas),
            end: CGPoint(x: canvas, y: 0),
            options: []
        )
    }

    // The two ends of the palette, bled into the corners they belong to, so the
    // background is not flat black behind a coloured letter.
    context.setBlendMode(.plusLighter)
    for (colour, centre) in [(pink, CGPoint(x: canvas * 0.18, y: canvas * 0.86)),
                             (blue, CGPoint(x: canvas * 0.84, y: canvas * 0.16))] {
        let wash = [colour.cgColor(alpha: 0.30), colour.cgColor(alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: wash, locations: [0, 1]) {
            context.drawRadialGradient(
                gradient,
                startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: canvas * 0.72,
                options: []
            )
        }
    }
    context.setBlendMode(.normal)
}

/// The dot-grid rendering, used at every size big enough to resolve a grid.
func renderDotted(size: Int) -> CGImage? {
    let canvas = Double(size)
    let inset = canvas * (wantsBackdrop ? 0.17 : 0.06)
    guard let path = letterPath(canvas: canvas, inset: inset) else { return nil }

    // A fixed cell count rather than a fixed cell size, so the letter is built
    // from the same grid at 128pt as at 1024pt.
    let cells = 34.0
    let cell = canvas / cells
    let mask = letterMask(size: size, path: path)
    guard !mask.isEmpty else { return nil }

    // Worked out once, then drawn twice: the glows all go down first in an
    // additive pass so they pool into light between neighbours, and the bodies
    // go on top normally so the colour inside a dot is the colour, not the sum
    // of everything around it.
    struct Dot {
        let point: CGPoint
        let radius: Double
        let colour: RGB
        let alpha: Double
    }

    var dots: [Dot] = []
    var row = 0.0
    while row < cells {
        var column = 0.0
        while column < cells {
            // Every other row steps half a cell across. A square grid puts the
            // dots in visible columns; an offset one reads as texture.
            let offset = row.truncatingRemainder(dividingBy: 2) == 0 ? 0 : cell / 2
            let x = column * cell + cell / 2 + offset
            let y = row * cell + cell / 2
            column += 1
            guard x < canvas else { continue }

            // Sampled well wider than the cell so the coverage keeps falling
            // off for a row or two outside the letter. That overspill is the
            // fade: the outline is not a line, it is where the dots run out.
            let cover = coverage(mask: mask, size: size, centreX: x, centreY: y, radius: cell * 0.92)
            guard cover > 0.02 else { continue }

            // Fully inside the letter a dot is at full strength; across the
            // outline it thins out to nothing over several cells.
            let strength = smoothstep(0.02, 0.80, cover)

            // Diagonal sweep, top-left pink to bottom-right blue, pushed
            // towards its ends. An S puts most of its mass near the middle of
            // this axis, so a straight ramp spent almost all of the letter in
            // purple and left pink and blue as corners.
            let axis = min(max((x / canvas) * 0.5 + (1 - y / canvas) * 0.5, 0), 1)
            let sweep = smoothstep(0.20, 0.80, axis)

            // Edge dots shrink as well as dim, which is what stops the outline
            // reading as a dotted line drawn around the shape.
            dots.append(Dot(
                point: CGPoint(x: x, y: y),
                radius: cell * 0.40 * (0.45 + 0.55 * strength),
                colour: sweepColour(sweep),
                alpha: strength
            ))
        }
        row += 1
    }

    let context = makeContext(size: size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if wantsBackdrop {
        drawBackdrop(in: context, canvas: canvas, space: space)
    }

    context.setBlendMode(.plusLighter)
    for dot in dots {
        drawGlow(in: context, at: dot.point, radius: dot.radius, colour: dot.colour, alpha: dot.alpha, space: space)
    }
    context.setBlendMode(.normal)
    for dot in dots {
        drawBody(in: context, at: dot.point, radius: dot.radius, colour: dot.colour, alpha: dot.alpha, space: space)
    }
    return context.makeImage()
}

/// Below about 64px a dot grid is smaller than the dots, so the letter is drawn
/// solid with the same sweep across it. It is the same icon at a distance.
func renderSolid(size: Int) -> CGImage? {
    let canvas = Double(size)
    let inset = canvas * (wantsBackdrop ? 0.17 : 0.06)
    guard let path = letterPath(canvas: canvas, inset: inset) else { return nil }

    let context = makeContext(size: size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if wantsBackdrop {
        drawBackdrop(in: context, canvas: canvas, space: space)
    }
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colours = [
        pink.lightened(0.18).cgColor(alpha: 1),
        purple.lightened(0.22).cgColor(alpha: 1),
        blue.lightened(0.18).cgColor(alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.5, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: canvas),
            end: CGPoint(x: canvas, y: 0),
            options: []
        )
    }
    context.restoreGState()
    return context.makeImage()
}

func render(size: Int) -> CGImage? {
    size >= 64 ? renderDotted(size: size) : renderSolid(size: size)
}

// MARK: - Output

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SangriaIcon", code: 1)
    }
    try data.write(to: url)
}

let pathArguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let outputDirectory = pathArguments.first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    guard let image = render(size: pixels) else {
        FileHandle.standardError.write(Data("failed to render \(pixels)\n".utf8))
        exit(1)
    }
    let url = outputDirectory.appending(path: "icon_\(pixels).png")
    try write(image, to: url)
    print("wrote \(url.lastPathComponent)")
}

//
//  LibraryCard.swift
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

extension Color {
    init(_ palette: IconPalette) {
        self.init(.sRGB, red: palette.red, green: palette.green, blue: palette.blue)
    }
}

/// Where an entry is in a launch.
enum LibraryEntryState: Equatable {
    /// Not started, or started and already exited.
    case idle
    /// Whisky has been asked to start it and Wine has not put a window up yet.
    case launching
    /// It has a process of its own in ``ProcessRegistry``.
    case running
}

/// One library entry, coloured by its own icon.
///
/// A 2:3 poster, the shape every other game library uses and the shape Steam
/// already caches art in. An entry with no poster is not stretched into one:
/// the icon sits at its native size on a gradient sampled from itself, so a
/// 32px icon stays crisp instead of turning to mush at 300px.
struct LibraryCard: View {
    let item: LibraryEntry
    /// Only shown when there is more than one bottle, since with a single bottle
    /// the prefix is plumbing and naming it on every card is noise.
    let bottleName: String?
    let lastPlayed: Date?
    let state: LibraryEntryState
    let launch: () -> Void

    @State private var icon: Image?
    @State private var artwork: Image?
    @State private var palette: IconPalette = .neutral
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    /// Both stops are opaque. A gradient that fades towards transparent
    /// composites against the window, which is near-white in light mode, and
    /// the white label on top of that corner falls to about 2:1 contrast.
    private var backdrop: Color { Color(palette.deepened()) }
    private var backdropDeep: Color { Color(palette.deepened(toLuminance: 0.07)) }

    /// Taken from the palette rather than hardcoded, so the label cannot end up
    /// the same lightness as what is behind it if the deepening target moves.
    private var foreground: Color {
        palette.deepened().prefersLightForeground ? .white : .black
    }

    /// A launcher is named by what it is. A pin takes its name from the
    /// executable, which is how the Steam client ends up on screen as "steam"
    /// and Metro Exodus as "MetroExodus" — so a filename gets read back as a
    /// title before it goes on the card.
    private var title: String {
        item.launcher?.displayName ?? item.name.titleCasedFromFileName
    }

    var body: some View {
        Button(action: launch) {
            card
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        // The system ring is a rectangle around the button's frame, so on a
        // rounded card it draws a second, squarer outline outside the one below
        // that follows the card's own shape.
        .focusEffectDisabled()
        .onKeyPress(.return) {
            launch()
            return .handled
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
        }
        .task(id: item.id) {
            await loadIcon()
        }
        .help(detail)
        .accessibilityLabel(title)
        .accessibilityValue(Text(detail))
        .accessibilityHint(Text("library.card.hint"))
    }

    /// Hover is a mouse-only signal, so anything shown only on hover does not
    /// exist for somebody on the keyboard.
    private var isActive: Bool { isHovering || isFocused }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [backdrop, backdropDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let artwork {
                // Steam cached this art inside the bottle, so a Steam game shows
                // its own banner with nothing fetched. Sized by an empty layer
                // rather than by the image: scaledToFill on its own reports the
                // image's size upward and the card grows to fit it.
                Color.clear
                    .overlay {
                        artwork
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .overlay {
                        // The scrim is what keeps the name readable over art we
                        // do not control.
                        LinearGradient(
                            colors: [.black.opacity(0.05), .black.opacity(0.75)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Spacer()
                    statusView
                }
                // The icon is the identity when there is no poster, so it sits
                // in the middle of the card the way a poster would. With a
                // poster it would cover the thing it stands in for, so it goes.
                if artwork == nil {
                    Spacer(minLength: 8)
                    HStack {
                        Spacer()
                        iconView
                        Spacer()
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                            // Tail, not middle: a game's name is recognisable
                            // from its start, and "The Elder Scro...Special
                            // Edition" reads worse than losing the suffix.
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(artwork == nil ? foreground.opacity(0.7) : .white.opacity(0.75))
                            .lineLimit(1)
                            // A poster leaves about 110pt beside the play
                            // button. Shrinking a little beats "Last played 2
                            // ho…", which is the part people are reading.
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    playButton
                }
            }
            .padding(14)
        }
        // Artwork brings its own scrim, so a card showing art is always dark
        // under the label whatever the sampled palette says.
        .foregroundStyle(artwork == nil ? foreground : .white)
        // 2:3, the poster ratio Steam's own cached art is cut to.
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isActive ? 0.22 : 0.08), lineWidth: 1)
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .shadow(color: .black.opacity(isActive ? 0.28 : 0.16), radius: isActive ? 10 : 5, y: 3)
        .scaleEffect(isActive ? 1.015 : 1)
    }

    /// The top-right corner: what it is doing, when it is doing something.
    ///
    /// Only states that are not the resting one appear here. Starting it is the
    /// card's own job, and that lives in ``playButton``.
    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .launching:
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
                .cardGlass(.circle)
                .help("library.card.launching")
        case .running:
            Label("library.card.running", systemImage: "circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .imageScale(.small)
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .cardGlass(.capsule)
        case .idle:
            EmptyView()
        }
    }

    /// Always on screen, not only on hover: it is the one thing a library card
    /// is for, and a control that appears only under a mouse pointer does not
    /// exist for anyone reading the screen or driving it from the keyboard. It
    /// brightens on hover rather than materialising.
    private var playButton: some View {
        Image(systemName: state == .running ? "arrow.up.forward" : "play.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            // The icon's own pink-to-blue sweep. This is the one control in the
            // app that should look like the app rather than like macOS.
            .background(LinearGradient.brand.opacity(isActive ? 1 : 0.85), in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .scaleEffect(isActive ? 1.08 : 1)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            // 72 rather than the icon's own 44: it is the poster now. Executable
            // icons go up to 256px, so this is still inside the source art on
            // anything modern, and a small one is padded rather than upscaled by
            // the frame.
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: 72, height: 72)
        }
    }

    /// The one line under the name: when it last ran.
    ///
    /// A poster card is about 180pt wide, which fits roughly one phrase. The
    /// four-part line this used to show truncated to "Steam · 2 hours a…" on
    /// every card, so everything except the part people scan for moved to
    /// ``detail``, which the tooltip and VoiceOver still read in full.
    private var subtitle: String {
        guard let lastPlayed else {
            return String(localized: "library.card.neverRun")
        }
        return String(
            format: String(localized: "library.card.lastPlayed %@"),
            // Abbreviated ("2 hr. ago", not "2 hours ago"): a card is about
            // 110pt wide here once the play button has its corner.
            lastPlayed.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        )
    }

    /// Everything about the entry, for the tooltip and for VoiceOver: where it
    /// came from, which bottle holds it, and when it last ran.
    private var detail: String {
        var parts: [String] = []
        if item.isLauncher {
            parts.append(String(localized: "library.card.launcher"))
        }
        if item.source == .steam {
            parts.append(String(localized: "library.source.steam"))
        }
        parts.append(subtitle)
        if let bottleName {
            parts.append(bottleName)
        }
        return parts.joined(separator: " · ")
    }

    /// Decoding and palette sampling both happen inside ``IconCache``, which is
    /// where the reasoning about repeating them lives.
    private func loadIcon() async {
        if let artworkURL = item.artworkURL,
           let sampled = await IconCache.shared.sampledArtwork(for: artworkURL) {
            artwork = Image(nsImage: sampled.image)
            // Still sampled: the border and the hover glow pick up the art's own
            // colour, so a card reads as one object rather than art in a frame.
            palette = sampled.palette
            return
        }
        guard let iconURL = item.iconURL else {
            palette = .neutral
            return
        }
        let sampled = await IconCache.shared.sampledIcon(for: iconURL)
        palette = sampled.palette
        icon = Image(nsImage: sampled.image)
    }
}

private extension View {
    /// Liquid Glass where the system has it, a plain material where it does not.
    /// The affordance matters more than the material, so the older path is a
    /// real control rather than nothing.
    @ViewBuilder
    func cardGlass(_ shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.thinMaterial, in: shape)
        }
    }
}

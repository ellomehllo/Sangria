//
//  ProgramMenuView.swift
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

import AppKit
import SwiftUI
import WhiskyKit

struct ProgramMenuView: View {
    @ObservedObject var program: Program
    @Binding var path: NavigationPath

    var body: some View {
        Button("button.run", systemImage: "play") {
            Telemetry.capture(.firstProgramLaunchAttempted)
            // Program-list and pin launches historically skipped launcher
            // detection; only FileOpenView and the bottle Run button had it.
            LauncherFixes.detectAndApply(from: program.url, for: program.bottle)
            program.run()
        }
        .labelStyle(.titleAndIcon)
        Section("program.settings") {
            Button("program.config", systemImage: "gearshape") {
                path.append(program)
            }
            .labelStyle(.titleAndIcon)

            let buttonName = program.pinned
                ? String(localized: "button.unpin")
                : String(localized: "button.pin")

            Button(buttonName, systemImage: "pin") {
                program.pinned.toggle()
            }
            .labelStyle(.titleAndIcon)
            .symbolVariant(program.pinned ? .slash : .none)

            UseD3DMetalToggle(program: program)
        }
    }
}

extension Program {
    /// Whether this program runs on D3DMetal whatever its bottle is set to.
    var usesD3DMetal: Bool {
        settings.overrides?.graphicsBackend == .d3dMetal
    }

    /// Turns the per-program D3DMetal override on or off. Off hands the
    /// program back to its bottle's backend.
    func setUsesD3DMetal(_ isOn: Bool) {
        var overrides = settings.overrides ?? ProgramOverrides()
        overrides.graphicsBackend = isOn ? .d3dMetal : nil
        settings.overrides = overrides
    }
}

/// "Use D3DMetal" for one program: in its menus (program list, pins, library)
/// and next to Run on its page.
///
/// It sets the same per-program backend override as Program Settings →
/// Graphics Backend, so the launch check, the resolver and the run log all
/// see it, and a Direct3D 12 program in a DXMT bottle launches instead of
/// being refused.
struct UseD3DMetalToggle: View {
    @ObservedObject var program: Program

    var body: some View {
        let installed = WhiskyWineInstaller.isD3DMetalInstalled()
        Toggle("Use D3DMetal", isOn: Binding(
            get: { program.usesD3DMetal },
            set: { program.setUsesD3DMetal($0) }
        ))
        // Always possible to turn off, so a program is never stranded on a
        // backend that has since been removed.
        .disabled(!installed && !program.usesD3DMetal)
        .help(
            installed
                ? "Run this program on D3DMetal, whatever its bottle uses."
                : "D3DMetal isn't installed. Import Apple's Game Porting Toolkit in Settings."
        )
    }
}

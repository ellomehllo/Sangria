//
//  MouseReleaseHotkey.swift
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
import Carbon.HIToolbox
import os.log
import WhiskyKit

/// ⌥⌘C, to get the pointer back from a game that has taken it.
///
/// A game holding the mouse for camera look has asked Wine to keep the pointer
/// inside its window, and the only thing that reliably ends that is Wine's own
/// app losing focus — its Mac driver releases the pointer on deactivation.
/// So this hotkey does not try to unpick the clip; it simply brings Sangria to
/// the front, and the release follows.
///
/// ⌘Tab would do the same thing, except that a game with the keyboard grabbed
/// often swallows it. A hotkey registered with the system is delivered before
/// the game ever sees the keystroke, which is the whole reason this exists.
///
/// Registered through Carbon's `RegisterEventHotKey` rather than
/// `NSEvent.addGlobalMonitorForEvents`: the monitor needs Accessibility
/// permission, and this must work for someone who has granted nothing.
@MainActor
final class MouseReleaseHotkey {
    static let shared = MouseReleaseHotkey()

    private static let logger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier, category: "MouseReleaseHotkey"
    )

    /// ⌥⌘C.
    static let displayName = "⌥⌘C"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var idleCheck: Timer?

    private init() {}

    /// Claims ⌥⌘C because a game is starting, and arranges to give it back.
    ///
    /// Called from the launch path rather than driven by ``ProcessRegistry``:
    /// nothing in this app ever calls `ProcessRegistry.register`, so the
    /// registry is permanently empty and anything waiting on it waits forever.
    /// A wineserver, by contrast, exists exactly while something is alive in a
    /// prefix, which is the question actually being asked.
    func gameStarted() {
        enable()
        startIdleCheck()
    }

    /// Gives the combination back once every prefix has gone quiet.
    ///
    /// A poll, because there is no notification to wait for. Fifteen seconds
    /// is slow enough to cost nothing and quick enough that ⌥⌘C is not held
    /// hostage long after a game exits, and it only runs while it is held.
    private func startIdleCheck() {
        guard idleCheck == nil else { return }
        idleCheck = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in
                for bottle in BottleVM.shared.bottles where bottle.isAvailable {
                    if await Wine.isWineserverRunning(for: bottle) { return }
                }
                MouseReleaseHotkey.shared.disable()
            }
        }
    }

    /// Claims the hotkey, if it is not claimed already.
    func enable() {
        guard hotKey == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The callback is a C function pointer and cannot capture, so it hops
        // straight back to the singleton. Carbon delivers it on the main run
        // loop, which is what makes `assumeIsolated` true rather than hopeful.
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                MainActor.assumeIsolated {
                    MouseReleaseHotkey.shared.releasePointer()
                }
                return noErr
            },
            1, &spec, nil, &handler
        )
        guard status == noErr else {
            Self.logger.warning("Could not install the hotkey handler: \(status)")
            return
        }

        let identifier = EventHotKeyID(signature: OSType(0x534E_4752), id: 1) // 'SNGR'
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registered == noErr else {
            // Someone else owns ⌥⌘C. Worth saying once; not worth an alert.
            Self.logger.warning("Could not register \(Self.displayName): \(registered)")
            hotKey = nil
            return
        }
        Self.logger.info("\(Self.displayName) is live")
    }

    /// Gives the combination back to the rest of the system.
    func disable() {
        idleCheck?.invalidate()
        idleCheck = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    /// Brings Sangria forward, which makes Wine's Mac driver let go.
    private func releasePointer() {
        NSApp.activate(ignoringOtherApps: true)
        // The main window may have been closed while the game ran; without a
        // window to come forward, activating does nothing and the pointer
        // stays captured.
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

}

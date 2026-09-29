import SwiftUI
import AppKit

// MARK: - Bindings for the recorders

extension AppSettings {
    /// For a recorder: through `setShortcut`, so the two shortcuts stay
    /// apart. The recorder has already said why a colliding one won't do.
    var shortcutBinding: Binding<Shortcut> {
        Binding(get: { self.shortcut }, set: { if !self.setShortcut($0) { NSSound.beep() } })
    }

    /// For a recorder, shown only while there is a screenshot shortcut.
    var screenshotShortcutBinding: Binding<Shortcut> {
        Binding(
            get: { self.screenshotShortcut ?? .screenshotDefault },
            set: { if !self.setScreenshotShortcut($0) { NSSound.beep() } }
        )
    }

    /// On is the first default that doesn't collide with what opens Flyby.
    var screenshotEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.screenshotShortcut != nil },
            set: { on in
                if !on {
                    self.screenshotShortcut = nil
                } else if let pick = self.screenshotShortcutToEnable {
                    self.setScreenshotShortcut(pick)
                } else {
                    NSSound.beep()
                }
            }
        )
    }
}

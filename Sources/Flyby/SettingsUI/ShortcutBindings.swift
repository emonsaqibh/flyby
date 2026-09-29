import SwiftUI
import AppKit

// MARK: - Bindings for the recorders

extension AppSettings {
    /// For a recorder: through `setShortcut`, so the two shortcuts stay apart.
    var shortcutBinding: Binding<Shortcut> {
        Binding(get: { self.shortcut }, set: { self.setShortcut($0) })
    }

    /// For a recorder, shown only while there is a screenshot shortcut. The
    /// keys that open Flyby are refused, with a beep.
    var screenshotShortcutBinding: Binding<Shortcut> {
        Binding(
            get: { self.screenshotShortcut ?? .screenshotDefault },
            set: { if !self.setScreenshotShortcut($0) { NSSound.beep() } }
        )
    }

    /// On means the default shortcut, unless that's what opens Flyby.
    var screenshotEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.screenshotShortcut != nil },
            set: { on in
                if !on {
                    self.screenshotShortcut = nil
                } else if !self.setScreenshotShortcut(.screenshotDefault) {
                    NSSound.beep()
                }
            }
        )
    }
}

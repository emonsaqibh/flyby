import AppKit

/// Keeps Flyby to one running copy per build.
///
/// Two copies means two menu bar icons and two hot key registrations fighting
/// over one shortcut, and it happens more easily than it sounds: open the disk
/// image's copy while the installed one is running, or launch a second clone
/// of the app from somewhere else. The newcomer hands over to the copy already
/// running — which opens Flyby, as though the launch had been a request for
/// it — and leaves.
///
/// Matched on the running bundle's own identifier, so the dev and release
/// builds (different identifiers) still run side by side.
enum SingleInstance {
    /// Posted by a newcomer to the copy already running. Carries the bundle
    /// identifier so one build's request never reaches the other. The name's
    /// last part is from when Flyby was a pill; it stays, so a newer copy
    /// can still hand over to an older one that's running.
    static var showRequest: Notification.Name {
        Notification.Name((Bundle.main.bundleIdentifier ?? "com.fringecore.flyby") + ".showPill")
    }

    /// Passed by the installer to the copy it relaunches, naming the process
    /// being replaced. That process is still quitting when the new one
    /// starts, and mustn't count as a rival.
    static let replacingArgument = "--flyby-replacing-pid"

    /// False when another copy is already running and has been asked to take
    /// over — this process should then exit without starting anything.
    @MainActor
    static func claim() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        let replacing = replacedProcess

        let rival = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            $0.processIdentifier != me && $0.processIdentifier != replacing && !$0.isTerminated
        }
        guard let rival else { return true }

        // Cooperative activation: the newcomer is the app the user just
        // launched, so it's allowed to pass the focus on.
        NSApplication.shared.yieldActivation(to: rival)
        // Delivered immediately: the running copy is usually in the
        // background, where distributed notifications otherwise wait.
        DistributedNotificationCenter.default().postNotificationName(
            showRequest,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return false
    }

    private static var replacedProcess: pid_t? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: replacingArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return pid_t(arguments[index + 1])
    }
}

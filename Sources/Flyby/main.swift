import AppKit

// Top-level code isn't main-actor isolated by default, but everything below
// genuinely does run on the main thread before the run loop starts.
MainActor.assumeIsolated {
    // A second copy of the same build hands over to the first and leaves,
    // before it has a menu bar icon or a hot key to fight over.
    guard SingleInstance.claim() else { exit(0) }

    let app = NSApplication.shared
    // NSApplication only holds its delegate weakly; `AppDelegate.shared` is
    // the strong reference, for the life of the process.
    app.delegate = AppDelegate.shared
    app.setActivationPolicy(.accessory)
    app.run()
}

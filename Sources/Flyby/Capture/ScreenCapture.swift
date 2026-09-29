import AppKit
import ScreenCaptureKit
import os

private let captureLog = Logger(subsystem: "com.fringecore.flyby", category: "capture")

/// Screen Recording permission, and taking the screenshot a question is
/// asked about.
///
/// What's captured is the front window of the app the user was in — just
/// that window, as if nothing overlapped it, without its shadow. When that
/// app has no window, it's the whole display — what the user is looking at;
/// when there's no app to go by (Flyby itself was in front, from Settings,
/// say), the frontmost ordinary window that isn't Flyby's. Alongside it, the display
/// Flyby's bar is on, without anything of Flyby's, for `CaptureWave` to play
/// over; that picture is never sent anywhere.
enum ScreenCapture {
    struct Capture {
        let screenshot: Screenshot
        /// `screen` as it looked, without Flyby.
        let display: CGImage
        /// Where the bar is, or will open: the wave's screen.
        let screen: NSScreen
        /// The captured window, in AppKit's screen coordinates.
        let windowFrame: CGRect
    }

    enum Failure: LocalizedError {
        /// No Screen Recording permission.
        case notAllowed
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAllowed:          return "\(BuildFlavor.appName) isn't allowed to record the screen."
            case .failed(let message): return "Couldn't take the screenshot: \(message)"
            }
        }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// The first time, macOS asks and puts Flyby in the list in System
    /// Settings; after that it does nothing, and only System Settings can
    /// change the answer.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// `app` is the app the user was in — never Flyby. `waveScreen` is where
    /// Flyby's bar is or will open; without one, the window's screen.
    @MainActor
    static func capture(windowOf app: NSRunningApplication?, waveScreen: NSScreen? = nil) async throws -> Capture {
        guard hasPermission else { throw Failure.notAllowed }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            captureLog.error("Shareable content unavailable: \(error.localizedDescription, privacy: .public)")
            let declined = (error as NSError).domain == SCStreamErrorDomain
                && (error as NSError).code == SCStreamError.Code.userDeclined.rawValue
            throw declined ? Failure.notAllowed : Failure.failed(error.localizedDescription)
        }

        let window = frontWindow(of: app).flatMap { id in content.windows.first { $0.windowID == id } }
        let frame = window.map { appKitFrame(fromGlobal: $0.frame) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame
            ?? NSScreen.main?.frame ?? .zero
        guard let screen = waveScreen ?? screen(containing: frame),
              let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw Failure.failed("the window isn't on a display")
        }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }

        do {
            async let displayImage = image(of: SCContentFilter(display: display, excludingApplications: own, exceptingWindows: []),
                                           size: screen.frame.size)
            let shot: CGImage
            let title: String
            if let window {
                shot = try await image(of: SCContentFilter(desktopIndependentWindow: window),
                                       size: window.frame.size, singleWindow: true)
                title = describe(window)
            } else {
                shot = try await displayImage
                title = "Screen"
            }
            guard let screenshot = Screenshot(image: shot, title: title) else {
                throw Failure.failed("the picture couldn't be encoded")
            }
            captureLog.notice("Captured \(shot.width, privacy: .public)×\(shot.height, privacy: .public): \(window == nil ? "the display" : "a window of \(window?.owningApplication?.applicationName ?? "?")", privacy: .public) (asked for \(app?.localizedName ?? "no app", privacy: .public))")
            return Capture(screenshot: screenshot, display: try await displayImage, screen: screen, windowFrame: frame)
        } catch let failure as Failure {
            throw failure
        } catch {
            captureLog.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            throw Failure.failed(error.localizedDescription)
        }
    }

    // MARK: - Pieces

    /// The app's frontmost ordinary window; with no app to go by, the
    /// frontmost ordinary window of any app but Flyby — from the window
    /// server's front-to-back list. IDs and bounds need no permission; names
    /// would.
    private static func frontWindow(of app: NSRunningApplication?) -> CGWindowID? {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let candidates: [(pid: pid_t, id: CGWindowID)] = list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 60, (bounds["Height"] ?? 0) > 40,
                  let number = info[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            return (pid, number)
        }
        if let app {
            // Its window or none: another app's would be a surprise.
            return candidates.first { $0.pid == app.processIdentifier }?.id
        }
        captureLog.notice("No previous app; taking the frontmost window")
        return candidates.first?.id
    }

    private static func image(of filter: SCContentFilter, size: CGSize, singleWindow: Bool = false) async throws -> CGImage {
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        if singleWindow { config.ignoreShadowsSingleWindow = true }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// "Safari — Flyby on GitHub", or just the app when the window has no title.
    private static func describe(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? ""
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (app.isEmpty, title.isEmpty) {
        case (false, false): return "\(app) — \(title)"
        case (false, true):  return app
        case (true, false):  return title
        case (true, true):   return "Window"
        }
    }

    /// The window server's space (top-left origin, from the primary display)
    /// to AppKit's (bottom-left).
    private static func appKitFrame(fromGlobal rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen holding most of `frame` — its middle, in practice.
    @MainActor
    private static func screen(containing frame: CGRect) -> NSScreen? {
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(middle) }
            ?? NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

import AppKit
import ScreenCaptureKit
import os

private let captureLog = Logger(subsystem: "com.fringecore.flyby", category: "capture")

/// Screen Recording permission, and taking the screenshot a question is
/// asked about.
///
/// What's captured is the front window of the app the user was in — just
/// that window, as if nothing overlapped it, without its shadow. With no such
/// window (the desktop, an app with none open) it's the whole display under
/// the pointer instead. Alongside it, the display the window is on, without
/// anything of Flyby's, for `CaptureWave` to play over; that picture is never
/// sent anywhere.
enum ScreenCapture {
    struct Capture {
        let screenshot: Screenshot
        /// The window's display as it looked, without Flyby.
        let display: CGImage
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

    /// `app` is the app the user was in — never Flyby.
    @MainActor
    static func capture(windowOf app: NSRunningApplication?) async throws -> Capture {
        guard hasPermission else { throw Failure.notAllowed }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            captureLog.error("Shareable content unavailable: \(error.localizedDescription, privacy: .public)")
            throw Failure.notAllowed
        }

        let window = frontWindow(of: app).flatMap { id in content.windows.first { $0.windowID == id } }
        let frame = window.map { appKitFrame(fromGlobal: $0.frame) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame
            ?? NSScreen.main?.frame ?? .zero
        guard let screen = screen(containing: frame),
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
            captureLog.info("Captured \(shot.width, privacy: .public)×\(shot.height, privacy: .public) (\(window == nil ? "display" : "window", privacy: .public))")
            return Capture(screenshot: screenshot, display: try await displayImage, screen: screen, windowFrame: frame)
        } catch let failure as Failure {
            throw failure
        } catch {
            captureLog.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            throw Failure.failed(error.localizedDescription)
        }
    }

    // MARK: - Pieces

    /// The app's frontmost ordinary window, from the window server's
    /// front-to-back list. IDs and bounds need no permission; names would.
    private static func frontWindow(of app: NSRunningApplication?) -> CGWindowID? {
        guard let pid = app?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 60, (bounds["Height"] ?? 0) > 40,
                  let number = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            return number
        }
        return nil
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

import AppKit
import WebKit
import os
import FlybyCore

private let debugLog = Logger(subsystem: "com.fringecore.flyby", category: "debug")

/// Dev builds only: launch arguments that run an AI Mode conversation without
/// anyone typing, and log what came back — so follow-ups can be checked
/// against real Google from a script. They land in the volatile arguments
/// domain, so nothing is remembered, and a release build ignores them all:
///
///     open "build/Flyby Dev.app" --args -FlybyDebugShowPanel YES \
///         -FlybyDebugAsk "iPhone 16 Pro performance" \
///         -FlybyDebugFollowUp "what is its AnTuTu score?"
///
/// - `-FlybyDebugAsk <question>`: asks it of AI Mode, whatever the provider
///   setting says.
/// - `-FlybyDebugShowPanel YES`: opens Flyby first and asks in it, so the
///   page is in a window on screen, as it is for a user. Without it there's
///   no window at all, and Google's page doesn't render — its composer then
///   takes only the first follow-up. A click elsewhere closes Flyby and ends
///   the chat, as it would for anyone.
/// - `-FlybyDebugFollowUp <question>`: asked once the first answer is in, as
///   a follow-up in the same chat.
/// - `-FlybyDebugThen <question>`: a second follow-up, after the first.
/// - `-FlybyDebugRetry YES`: then asks the last question again, as ⌘R does.
/// - `-FlybyDebugReopen YES`: before the follow-up, puts the chat away and
///   reopens it from history, as Recent Chats does — so there's no page to
///   continue.
/// - `-FlybyDebugForceFallback YES`: the engine never continues on its page,
///   as if the composer had gone.
/// - `-FlybyDebugProbe <path>`: after each answer, writes what the page's
///   composer and turns look like to `<path>.<n>.json` — the first thing to
///   look at when Google changes its markup.
/// - `-FlybyDebugConsole <path>`: a live console into the AI Mode page, for
///   working out Google's markup without rebuilding. The page gets a window
///   of its own, and whenever `<path>` changes it runs as the body of an
///   async function — in Flyby's content world, or the page's own when its
///   first line is `// page`. What it returns goes to `<path>.out`, and a
///   picture of the page to `<path>.png`. `image` (base64) and `imageName`
///   are in scope when `-FlybyDebugImage` is given.
/// - `-FlybyDebugImage <path>`: a picture sent with the first question, as
///   if it had been captured — and, with the console, the file the page gets
///   when it opens a file picker.
/// - `-FlybyDebugFollowUpImage <path>`: a picture sent with the follow-up.
/// - `-FlybyDebugCapture YES`: a second after launch, a real screenshot of
///   the frontmost window, wave and all, as the shortcut takes one.
///
/// A scripted run doesn't listen for Flyby's shortcuts, so using Flyby
/// meanwhile can't open, close or reset the chat under it; if something
/// resets it anyway, the run says so and stops.
///
/// Each answer's first 300 characters are logged publicly under the `debug`
/// category, at notice level so they're kept, and the engine logs (under
/// `aimode`) which way each follow-up went:
///
///     log show --last 5m --info \
///         --predicate 'subsystem == "com.fringecore.flyby"'
@MainActor
enum AIModeDebug {
    /// `-FlybyDebugForceFallback YES`.
    static var forcesFallback: Bool { flag("FlybyDebugForceFallback") }

    /// A scripted conversation is running (`-FlybyDebugAsk`).
    static var isScripted: Bool { string("FlybyDebugAsk") != nil }

    /// `showPanel` opens Flyby as the hot key does.
    static func runIfAsked(_ controller: SearchController, showPanel: @escaping () -> Void) {
        if flag("FlybyDebugCapture") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                debugLog.notice("Capturing the frontmost window")
                controller.captureScreen()
            }
        }
        guard let first = string("FlybyDebugAsk") else { return }
        let followUp = string("FlybyDebugFollowUp")
        Task { @MainActor in
            if flag("FlybyDebugShowPanel") {
                showPanel()
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            attachImage("FlybyDebugImage", to: controller, for: "Q1")
            debugLog.notice("Q1: \(first, privacy: .public)")
            guard await ask("Q1", of: controller, step: 1, { controller.send(first, with: .aiMode) }) else { return finish() }

            guard let followUp else { return finish() }
            if flag("FlybyDebugReopen") {
                guard await reopen(controller, titled: first) else { return finish() }
            }
            debugLog.notice("Q2: \(followUp, privacy: .public)")
            let composed = AIModeFollowUp.query(followUp, after: controller.earlierTurns + [liveTurn(controller)])
            debugLog.notice("Q2 as a search, if it comes to that: \(composed, privacy: .public)")
            attachImage("FlybyDebugFollowUpImage", to: controller, for: "Q2")
            guard await ask("Q2", of: controller, step: 2, { controller.send(followUp, with: .aiMode) }) else { return finish() }

            if let then = string("FlybyDebugThen") {
                debugLog.notice("Q3: \(then, privacy: .public)")
                guard await ask("Q3", of: controller, step: 3, { controller.send(then, with: .aiMode) }) else { return finish() }
            }
            if flag("FlybyDebugRetry") {
                debugLog.notice("Retrying the last question")
                guard await ask("Retried", of: controller, step: 4, { controller.retry() }) else { return finish() }
            }
            finish()
        }
    }

    /// The picture at the path in `key`, waiting over the input as a capture
    /// would, for the next question.
    private static func attachImage(_ key: String, to controller: SearchController, for label: String) {
        guard let path = string(key) else { return }
        if let screenshot = Screenshot(contentsOf: URL(fileURLWithPath: path)) {
            controller.attach(screenshot)
            debugLog.notice("\(label, privacy: .public) goes with \(path, privacy: .public) (\(screenshot.upload.count, privacy: .public) bytes)")
        } else {
            debugLog.error("Couldn't read \(path, privacy: .public) as an image")
        }
    }

    /// Does `action`, waits for the turn to settle, and reports on it.
    /// False when the chat was reset before it did.
    private static func ask(_ label: String, of controller: SearchController, step: Int, _ action: () -> Void) async -> Bool {
        action()
        let settled = await settle(controller)
        report(controller, label: label)
        await probe(controller, step: step)
        if !settled {
            debugLog.error("\(label, privacy: .public): the chat was reset before it was answered (Flyby opened or closed?); stopping")
        }
        return settled
    }

    private static func finish() {
        debugLog.notice("Debug run finished")
    }

    /// Stands in for the live turn when predicting the fallback query; only
    /// its question and answer matter.
    private static func liveTurn(_ controller: SearchController) -> ConversationTurn {
        ConversationTurn(query: controller.submittedQuery, provider: ProviderKind.aiMode.rawValue, answer: controller.answer)
    }

    /// New Chat, then the chat picked from Recent Chats.
    private static func reopen(_ controller: SearchController, titled title: String) async -> Bool {
        controller.newChat()
        for _ in 0..<40 {
            if let summary = controller.history.summaries.first(where: { $0.title == title }) {
                controller.openConversation(summary.id)
                for _ in 0..<40 where !controller.isRestored {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                debugLog.notice("Reopened the chat from history (restored: \(controller.isRestored, privacy: .public))")
                return controller.isRestored
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        debugLog.error("The chat never showed up in history")
        return false
    }

    /// Until the turn is done one way or another, or two minutes pass.
    /// False if the chat went back to idle — reset — on the way.
    private static func settle(_ controller: SearchController) async -> Bool {
        for _ in 0..<240 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            switch controller.phase {
            case .complete, .failed, .needsAttention: return true
            case .idle: return false
            case .working, .streaming: continue
            }
        }
        return true
    }

    private static func report(_ controller: SearchController, label: String) {
        let text = String(controller.answer.bodyText.prefix(300)).replacingOccurrences(of: "\n", with: " ")
        debugLog.notice("\(label, privacy: .public) [\(String(describing: controller.phase), privacy: .public)] bubble: \"\(controller.submittedQuery, privacy: .public)\" answer: \(text, privacy: .public)")
    }

    private static func probe(_ controller: SearchController, step: Int) async {
        guard let base = string("FlybyDebugProbe") else { return }
        let json = await controller.aiMode.webView.flybyString(probeScript, in: AIModeEngine.contentWorld) ?? "null"
        let path = "\(base).\(step).json"
        do {
            try json.write(toFile: path, atomically: true, encoding: .utf8)
            debugLog.notice("Page described in \(path, privacy: .public)")
        } catch {
            debugLog.error("Couldn't write \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Console

    private static var consoleWindow: NSWindow?

    static func runConsoleIfAsked(_ controller: SearchController) {
        guard let path = string("FlybyDebugConsole") else { return }
        let engine = controller.aiMode
        var arguments: [String: Any] = ["image": NSNull(), "imageName": NSNull()]
        if let imagePath = string("FlybyDebugImage") {
            let url = URL(fileURLWithPath: imagePath)
            engine.fileForPicker = url
            if let data = FileManager.default.contents(atPath: imagePath) {
                arguments = ["image": data.base64EncodedString(), "imageName": url.lastPathComponent]
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
            styleMask: [.titled, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "AI Mode console — \(path)"
        window.isReleasedWhenClosed = false
        window.contentView = engine.webView
        window.center()
        window.orderFrontRegardless()
        consoleWindow = window
        engine.prewarm()
        debugLog.notice("Console watching \(path, privacy: .public)")

        Task { @MainActor in
            var lastRun: Date?
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                      modified != lastRun,
                      let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                lastRun = modified
                let world: WKContentWorld = source.hasPrefix("// page") ? .page : AIModeEngine.contentWorld
                let body = """
                try {
                  var result = await (async function () {
                \(source)
                  })();
                  return typeof result === 'string' ? result : JSON.stringify(result, null, 1);
                } catch (e) {
                  return 'error: ' + e + '\\n' + (e && e.stack);
                }
                """
                let result = await engine.webView.flybyCallAsync(body, arguments: arguments, in: world) ?? "(no string result)"
                try? result.write(toFile: path + ".out", atomically: true, encoding: .utf8)
                if let image = try? await engine.webView.takeSnapshot(configuration: nil),
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path + ".png"))
                }
                debugLog.notice("Console ran \(path, privacy: .public)")
            }
        }
    }

    private static func string(_ key: String) -> String? {
        guard BuildFlavor.isDev else { return nil }
        return UserDefaults.standard.string(forKey: key)
    }

    private static func flag(_ key: String) -> Bool {
        BuildFlavor.isDev && UserDefaults.standard.bool(forKey: key)
    }

    /// The URL, the turns with the start of each one's text, and every text
    /// field with its chain of ancestors and the buttons around it.
    private static let probeScript = #"""
(function () {
  function attrs(el) {
    var a = {};
    for (var i = 0; i < el.attributes.length; i++) {
      var at = el.attributes[i];
      if (at.name !== 'style') a[at.name] = String(at.value).slice(0, 140);
    }
    return a;
  }
  function describe(el) {
    var r = el.getBoundingClientRect();
    return { tag: el.localName, attrs: attrs(el), rect: [r.x | 0, r.y | 0, r.width | 0, r.height | 0],
             text: (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 80) };
  }
  function hook(el) {
    return el.localName + ['data-xid', 'jsname', 'role', 'data-container-id'].map(function (n) {
      return el.getAttribute(n) ? '[' + n + '=' + el.getAttribute(n) + ']' : '';
    }).join('');
  }
  var out = { url: location.href, title: document.title, fields: [], turns: [] };
  var turns = document.querySelectorAll('[data-tr-rsts]');
  for (var t = 0; t < turns.length; t++) {
    var turn = turns[t];
    out.turns.push({ parent: turn.parentElement && hook(turn.parentElement),
                     answers: turn.querySelectorAll('[data-container-id="main-col"]').length,
                     footers: turn.querySelectorAll('[data-xid="Gd7Hsc"]').length,
                     text: (turn.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 400) });
  }
  var fields = document.querySelectorAll('textarea, input:not([type=hidden]), [contenteditable]:not([contenteditable=false]), [role=textbox]');
  for (var i = 0; i < fields.length; i++) {
    var field = describe(fields[i]);
    field.ancestors = [];
    var p = fields[i].parentElement;
    for (var k = 0; k < 8 && p; k++, p = p.parentElement) field.ancestors.push(hook(p));
    var around = fields[i];
    for (var up = 0; up < 6 && around.parentElement; up++) around = around.parentElement;
    field.buttons = Array.prototype.slice.call(around.querySelectorAll('button, [role=button]'), 0, 20).map(describe);
    out.fields.push(field);
  }
  return JSON.stringify(out, null, 1);
})()
"""#
}

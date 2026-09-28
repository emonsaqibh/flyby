import Foundation
import WebKit
import FlybyCore

/// How every Google web view in Flyby presents itself: Flyby's own persistent
/// data store, and exactly the user agent Safari would send.
enum GoogleWebIdentity {
    /// "Version/<installed Safari> Safari/605.1.15", appended by WebKit to its
    /// own UA — so the result is Safari's UA, from the WebKit Safari itself
    /// runs on. See `SafariIdentity`.
    static let applicationNameForUserAgent: String =
        SafariIdentity.applicationName(safariVersion: installedSafariVersion())

    /// Read from Safari's Info.plist rather than hard-coded, so the UA keeps
    /// step with the WebKit that macOS updates underneath us.
    static func installedSafariVersion() -> String? {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    /// Deliberately no `customUserAgent`: that replaces WebKit's UA wholesale
    /// and goes stale; `applicationNameForUserAgent` only appends to it.
    @MainActor
    static func configuration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        return configuration
    }
}

// The completion-handler forms of these WebKit calls are wrapped by hand: they
// have been stable since macOS 10.13, while the async spellings WebKit's Swift
// overlay generates have shifted between SDKs.

@MainActor
extension WKHTTPCookieStore {
    func flybyAllCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            getAllCookies { cookies in continuation.resume(returning: cookies) }
        }
    }

    func flybySetCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            setCookie(cookie) { continuation.resume() }
        }
    }

    func flybyDeleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delete(cookie) { continuation.resume() }
        }
    }
}

@MainActor
extension WKWebsiteDataStore {
    func flybyDataRecords() async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                continuation.resume(returning: records)
            }
        }
    }

    func flybyRemoveData(for records: [WKWebsiteDataRecord]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                continuation.resume()
            }
        }
    }
}

@MainActor
extension WKWebView {
    /// Fire-and-forget script in `world`.
    func flybyRun(_ script: String, in world: WKContentWorld) {
        evaluateJavaScript(script, in: nil, in: world, completionHandler: nil)
    }

    /// Runs `body` as the body of an async function in `world`, with
    /// `arguments` as its parameters, and returns what it resolves to if
    /// that's a string. Arguments travel as values, never spliced into the
    /// source, so any text is safe to pass.
    func flybyCallAsync(_ body: String, arguments: [String: Any], in world: WKContentWorld) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            callAsyncJavaScript(body, arguments: arguments, in: nil, in: world) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value as? String)
                case .failure:            continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Runs `script` in `world` and returns its result if it's a string.
    func flybyString(_ script: String, in world: WKContentWorld) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            evaluateJavaScript(script, in: nil, in: world) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value as? String)
                case .failure:            continuation.resume(returning: nil)
                }
            }
        }
    }
}

import Foundation

/// How Flyby's web views introduce themselves.
///
/// A WKWebView's default user agent is Safari's minus the trailing
/// "Version/x Safari/605.1.15", and Google treats that bare form as an
/// embedded browser. Appending that suffix — with the version of the Safari
/// actually installed, which ships the same WebKit — gives exactly Safari's UA.
/// A hard-coded UA would drift out of step with the engine underneath it, and a
/// UA that disagrees with the engine's real feature set is a bot signal.
public enum SafariIdentity {
    /// Used when Safari's version can't be read.
    public static let fallbackVersion = "26.0"

    /// For `WKWebViewConfiguration.applicationNameForUserAgent`.
    public static func applicationName(safariVersion: String?) -> String {
        "Version/\(sanitizedVersion(safariVersion) ?? fallbackVersion) Safari/605.1.15"
    }

    /// "26.0", "18.3.1"; nil for anything that isn't one to three numeric
    /// components. A bare major version gets ".0", as Safari writes it.
    public static func sanitizedVersion(_ raw: String?) -> String? {
        guard let version = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
            return nil
        }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        return parts.count == 1 ? version + ".0" : version
    }
}

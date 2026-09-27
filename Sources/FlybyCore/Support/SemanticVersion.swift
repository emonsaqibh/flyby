import Foundation

/// A release version as Flyby's tags spell it: `v1.2.3`, `1.2.3`,
/// `1.3.0-beta.2`.
///
/// Deliberately strict about the numeric core, so tags that were never
/// versions — the legacy `Golden` and `beta` releases — don't parse and can't
/// be mistaken for an update.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated identifiers after the hyphen: `["beta", "2"]`.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Accepts an optional leading "v", two or three numeric components, an
    /// optional `-prerelease`, and ignores `+build` metadata. Anything else is
    /// nil.
    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        if let plus = text.firstIndex(of: "+") { text = text[..<plus] }

        let core: Substring
        var pre: [String] = []
        if let hyphen = text.firstIndex(of: "-") {
            core = text[..<hyphen]
            let rest = text[text.index(after: hyphen)...]
            pre = rest.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !pre.isEmpty, pre.allSatisfy({ !$0.isEmpty }) else { return nil }
        } else {
            core = text
        }

        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(numbers.count),
              numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(numbers[0]), let minor = Int(numbers[1])
        else { return nil }
        let patch = numbers.count == 3 ? Int(numbers[2]) : 0
        guard let patch else { return nil }

        self.init(major: major, minor: minor, patch: patch, prerelease: pre)
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    /// SemVer 2.0 precedence: numeric core first; a pre-release sorts before
    /// its release (1.0.0-beta < 1.0.0); numeric identifiers compare as
    /// numbers and sort before alphanumeric ones.
    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        if a.prerelease.isEmpty != b.prerelease.isEmpty { return !a.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (m?, n?): return m < n
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):   return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}

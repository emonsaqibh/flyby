import SwiftUI

/// Which of the two builds this is.
///
/// `./build.sh` makes **Flyby Dev** (`com.fringecore.flyby.dev`), the build all
/// development happens in; `./release.sh <version>` makes **Flyby**
/// (`com.fringecore.flyby`), the frozen build that gets published. Different
/// bundle identifiers mean separate settings, Keychain entries, Google
/// session, login item and Screen Recording grant — so the two run side by side
/// and a dev build can never damage the installed release's state.
enum BuildFlavor {
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

    /// `CFBundleShortVersionString`. A dev build's comes from git (`build.sh`),
    /// e.g. "0.3.0-dev.14 · pill": 14 commits past v0.3.0, built on feature/pill.
    static let versionLabel = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    /// The short commit hash the build was made from, when build.sh knew it.
    static let commit = Bundle.main.infoDictionary?["FlybyCommit"] as? String

    /// "Flyby" or "Flyby Dev" — whatever this bundle calls itself.
    static let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
        ?? "Flyby"

    /// Matches the dev icon's gradient (`IconGenerator --dev`), so the badge and
    /// the icon agree about which build is in front.
    static let devColor = Color(red: 0.96, green: 0.52, blue: 0.12)
}

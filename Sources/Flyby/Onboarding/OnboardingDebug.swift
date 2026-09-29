import SwiftUI

/// Dev builds only: launch arguments for looking at the walkthrough — and
/// screenshotting its motion — without clicking through it. They land in the
/// volatile arguments domain, so nothing is remembered, and a release build
/// ignores them all:
///
///     open "build/Flyby Dev.app" --args -FlybyDebugOpen onboarding \
///         -FlybyDebugOnboardingStep practice -FlybyDebugPracticeSuccess YES
///
/// - `-FlybyDebugOnboardingStep <step>`: start on `welcome`, `provider`,
///   `google`, `hotkey`, `practice`, `screenshot` or `done`.
/// - `-FlybyDebugOpen whatsnew`: What's new, as an update shows it.
/// - `-FlybyDebugOnboardingAutoplay <seconds>`: move on by itself every so
///   often, back to the start after the last step, to watch transitions.
/// - `-FlybyDebugPracticeSuccess YES`: the practice step succeeds on its own,
///   a moment after it appears.
/// - `-FlybyDebugReduceMotion YES`, `-FlybyDebugReduceTransparency YES`: the
///   walkthrough behaves as if those accessibility settings were on, to check
///   its fallbacks without changing the Mac's.
///
/// Any other setting can be pinned the same way, by its own key — e.g.
/// `-provider gemini` to open on Gemini.
enum OnboardingDebug {
    static var initialStep: OnboardingView.Step? {
        guard let name = string("FlybyDebugOnboardingStep") else { return nil }
        return OnboardingView.Step.allCases.first { "\($0)" == name }
    }

    static var autoplayInterval: TimeInterval? {
        positive("FlybyDebugOnboardingAutoplay")
    }

    static var practiceSucceeds: Bool {
        BuildFlavor.isDev && UserDefaults.standard.bool(forKey: "FlybyDebugPracticeSuccess")
    }


    /// Turns Reduce Motion and Reduce Transparency on for the walkthrough
    /// when asked to; otherwise passes the system's settings through.
    struct AccessibilityOverrides: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        func body(content: Content) -> some View {
            content
                .environment(\._accessibilityReduceMotion, reduceMotion || flag("FlybyDebugReduceMotion"))
                .environment(\._accessibilityReduceTransparency, reduceTransparency || flag("FlybyDebugReduceTransparency"))
        }

        private func flag(_ key: String) -> Bool {
            BuildFlavor.isDev && UserDefaults.standard.bool(forKey: key)
        }
    }

    private static func string(_ key: String) -> String? {
        guard BuildFlavor.isDev else { return nil }
        return UserDefaults.standard.string(forKey: key)
    }

    private static func positive(_ key: String) -> TimeInterval? {
        guard BuildFlavor.isDev else { return nil }
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : nil
    }
}

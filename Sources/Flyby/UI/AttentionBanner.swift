import SwiftUI
import FlybyCore

/// Pinned above Google's page whenever Flyby has had to reveal it: what Google
/// wants, what to do about it, and — when the real fix is connecting an
/// account rather than solving this one page — a way to do that instead.
///
/// The page stays live underneath; the banner never covers it.
struct AttentionBanner: View {
    let attention: AIModeEngine.Attention
    let onOpenInBrowser: () -> Void

    @ObservedObject private var google = GoogleSession.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    if offersConnect {
                        // Settings, not the page: a sign-in inside an
                        // embedded page is exactly what Google distrusts.
                        Button("Connect Google…") {
                            SettingsNavigation.showGoogleAccount()
                        }
                        .flybyGlassButton(prominent: true)
                    }
                    Button("Open in Browser", action: onOpenInBrowser)
                        .flybyGlassButton()
                        .help("Open this search in your browser (⌘↩)")
                }
            }
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surface(RoundedRectangle(cornerRadius: PanelMetrics.innerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Copy

    private var symbol: String {
        switch attention {
        case .captcha:    return "checkmark.shield.fill"
        case .consent:    return "hand.raised.fill"
        case .signIn:     return "person.crop.circle.badge.exclamationmark"
        case .unreadable: return "doc.text.magnifyingglass"
        }
    }

    private var title: String {
        switch attention {
        case .captcha:    return "Google wants to check you're human."
        case .consent:    return "Choose your cookie settings below — Google asks once."
        case .signIn:     return "Google wants you signed in."
        case .unreadable: return "Flyby couldn't read this answer, so here's Google's page."
        }
    }

    private var detail: String? {
        switch attention {
        case .captcha:
            return google.isConnected
                ? "Solve it below once — Flyby remembers."
                : "Solve it below once — Flyby remembers. Connecting your Google account makes this rare."
        case .signIn:
            return "Connect your Google account and Flyby will use it from now on."
        case .consent, .unreadable:
            return nil
        }
    }

    private var offersConnect: Bool {
        switch attention {
        case .captcha:              return !google.isConnected
        case .signIn:               return true
        case .consent, .unreadable: return false
        }
    }
}

import SwiftUI

/// Why each shortcut isn't working right now — a combo another app already
/// owns — for the places that record them: Settings › Shortcut, and the
/// walkthrough and What's new. The app delegate keeps it current as it
/// registers the hot keys.
@MainActor
final class ShortcutHealthModel: ObservableObject {
    static let shared = ShortcutHealthModel()

    @Published var main: String?
    @Published var screenshot: String?
}

/// Why a shortcut isn't working, right under the one it's about.
struct ShortcutProblemNote: View {
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Not available")
                    .font(.system(size: 12, weight: .semibold))
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// "DEV", in the dev icon's orange.
///
/// The dev and release builds run side by side with separate settings and
/// shortcuts, so the pill and Settings say which one answered — small enough to
/// ignore once you know, loud enough to notice when it's the wrong one.
struct DevBadge: View {
    var body: some View {
        Text("DEV")
            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(BuildFlavor.devColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(BuildFlavor.devColor.opacity(0.16)))
            .fixedSize()
            .accessibilityLabel("Development build")
    }
}

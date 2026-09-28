import SwiftUI
import AppKit

// The parts every pane shares: the sidebar, and the hero each pane opens with.

// MARK: - Sidebar

/// The source list: Flyby's own face at the top, where System Settings shows
/// your account, then the panes in their groups, each with its badge.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection?

    var body: some View {
        List(selection: $selection) {
            SidebarIdentity()
                .selectionDisabled()

            ForEach(SettingsSection.sidebarGroups, id: \.first) { group in
                Section {
                    ForEach(group) { section in
                        Label {
                            Text(section.title)
                        } icon: {
                            section.badge(size: 20)
                        }
                        .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// Icon, name and version: a menu-bar app has nowhere else to show its face,
/// and it answers "which Flyby is this?" before anything is clicked.
private struct SidebarIdentity: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(BuildFlavor.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if BuildFlavor.isDev {
                        DevBadge()
                    }
                }
                Text("Version \(BuildFlavor.versionLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero

/// The top of every pane: its badge, large, over its name and one line on
/// what it's for — how System Settings opens each of its panes, so the pane
/// says where you are before it asks anything of you.
///
/// On Flyby's dark surfaces the badge glows faintly in its own hue, the way
/// the overlay's glass is lit rather than merely shaded. Settles in as the
/// pane appears — a small scale and blur resolving to crisp — or simply fades
/// in under Reduce Motion.
struct PaneHero: View {
    let section: SettingsSection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        Section {
            VStack(spacing: 0) {
                section.badge(size: 60)
                    .shadow(color: section.tint.opacity(0.45), radius: 16, y: 6)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .scaleEffect(settled || reduceMotion ? 1 : 0.86)
                    .blur(radius: settled || reduceMotion ? 0 : 6)
                    .opacity(settled ? 1 : 0)
                    .padding(.bottom, 12)

                Text(section.title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .padding(.bottom, 5)
                    .accessibilityAddTraits(.isHeader)

                Text(section.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .onAppear {
                withAnimation(reduceMotion ? .smooth(duration: 0.2) : .spring(duration: 0.5, bounce: 0.22)) {
                    settled = true
                }
            }
        }
    }
}

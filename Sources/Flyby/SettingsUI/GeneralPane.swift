import SwiftUI
import AppKit

/// Settings › General: which Flyby this is, how it starts, and updates.
struct GeneralPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            PaneHero(section: .general)

            Section {
                AboutRow()
            }

            // The dev build runs from build/ on purpose.
            if !BuildFlavor.isDev && !Installer.isInstalled {
                moveToApplications
            }

            Section {
                Toggle("Open at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("Startup")
            } footer: {
                loginItemFooter
            }

            UpdateSettingsSection()
        }
        .formStyle(.grouped)
    }

    /// Login items and the Accessibility grant both key off the app's path,
    /// so this is the fix for half the ways Flyby can appear broken — worth a
    /// section of its own, not a footnote.
    private var moveToApplications: some View {
        Section {
            LabeledContent {
                Button("Move to Applications") { Installer.performInstall() }
            } label: {
                Label {
                    Text("Not in your Applications folder")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
        } footer: {
            Text("Flyby is running from \(Installer.bundleURL.deletingLastPathComponent().path). Permissions and open-at-login follow the app’s location, so they won’t stick until it’s in Applications.")
        }
    }

    /// What macOS says about the login item, when it has something to say;
    /// otherwise, where else it can be turned off.
    @ViewBuilder
    private var loginItemFooter: some View {
        if let error = settings.loginItemError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let status = LoginItem.statusDescription {
            Label(status, systemImage: "info.circle")
        } else {
            Text("Managed by macOS — you can also turn this off in System Settings › General › Login Items. Registration follows where the app lives, so turn it on again after moving Flyby.")
        }
    }
}

/// The app's own icon and version — the only place a menu-bar app gets to
/// show its face — with the commit, selectable, for bug reports.
private struct AboutRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(BuildFlavor.appName)
                        .font(.system(size: 15, weight: .semibold))
                    if BuildFlavor.isDev {
                        DevBadge()
                    }
                }
                Text(Self.versionString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Search from anywhere on your Mac with one gesture.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private static var versionString: String {
        var version = "Version \(BuildFlavor.versionLabel)"
        if let commit = BuildFlavor.commit, !commit.isEmpty {
            version += " (\(commit))"
        }
        return version
    }
}

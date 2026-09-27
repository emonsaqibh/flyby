import AppKit
import SwiftUI

/// Settings › General › Updates.
///
/// A `Section`, so it drops straight into the grouped settings form.
struct UpdateSettingsSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section("Updates") {
            if updater.isEnabled {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                Toggle("Include beta versions", isOn: $updater.includesPrereleases)

                LabeledContent {
                    HStack(spacing: 8) {
                        if updater.state == .checking {
                            ProgressView().controlSize(.small)
                        }
                        Button("Check Now") { Task { await updater.check() } }
                            .disabled(updater.state == .checking)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(BuildFlavor.versionLabel)")
                        Text(lastChecked)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let release = updater.available {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Text("Version \(release.version.description) is available.")
                                .font(.callout.weight(.semibold))
                            Button("What’s New") { NSWorkspace.shared.open(release.page) }
                                .buttonStyle(.link)
                        }
                        UpdateSteps()
                    }
                    .padding(.vertical, 4)
                } else if updater.state == .upToDate {
                    Label("You’re up to date.", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else if case .failed(let message) = updater.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Updates are off in the dev build — rebuild it with ./build.sh, or install a release.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastChecked: String {
        guard let date = updater.lastChecked else { return "Not checked yet" }
        return "Last checked " + date.formatted(.relative(presentation: .named))
    }
}

/// How to install an update, as two steps: copy the command, paste it into
/// Terminal. A button that did it for you would need an unsandboxed helper and
/// admin rights; this needs neither and is what the README tells people anyway.
struct UpdateSteps: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                step(1)
                Button {
                    Updater.copyInstallCommand()
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy Install Command",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
                .help(Updater.installCommand)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                step(2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste it into Terminal and press Return.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Terminal") { Updater.openTerminal() }
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.accentColor))
            .accessibilityLabel("Step \(n)")
    }
}

/// "Check for Updates…" from the menu bar: always answers, unlike the
/// automatic checks, which stay quiet unless there's something to say.
@MainActor
enum UpdateCommand {
    static func checkNow() {
        let updater = Updater.shared
        guard updater.isEnabled else {
            alert("Updates are off in the dev build", "Rebuild it with ./build.sh, or install a release.")
            return
        }
        Task {
            let found = await updater.check()
            if found, let release = updater.available {
                let alert = NSAlert()
                alert.messageText = "Flyby \(release.version.description) is available"
                alert.informativeText = """
                You have \(BuildFlavor.versionLabel). To update:

                1. Copy the install command.
                2. Paste it into Terminal and press Return.

                It quits Flyby, installs the new version and reopens it. Your settings \
                and Google connection are kept.
                """
                alert.addButton(withTitle: "Copy Command")
                alert.addButton(withTitle: "What’s New")
                alert.addButton(withTitle: "Later")
                NSApp.activate()
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    Updater.copyInstallCommand()
                    Updater.openTerminal()
                case .alertSecondButtonReturn:
                    NSWorkspace.shared.open(release.page)
                default:
                    break
                }
            } else if case .failed(let message) = updater.state {
                alert("Couldn’t check for updates", message)
            } else {
                alert("You’re up to date", "Flyby \(BuildFlavor.versionLabel) is the newest version.")
            }
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}

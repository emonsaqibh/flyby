import SwiftUI
import AppKit
import FlybyCore

/// Just above the input, over its leading edge: the screenshot waiting to go
/// with the next question — its thumbnail, what it's of, and a button to take
/// it off — in a small smoked card like the command list's. Or, when a
/// screenshot couldn't be taken, why, and the way to fix it.
struct AttachmentTray: View {
    @ObservedObject var controller: SearchController
    @ObservedObject private var settings = AppSettings.shared

    static let maxWidth: CGFloat = 440

    var body: some View {
        Group {
            if let notice = controller.captureNotice {
                NoticeCard(notice: notice, controller: controller)
            } else if let screenshot = controller.pendingScreenshot {
                attachment(screenshot)
            }
        }
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func attachment(_ screenshot: Screenshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AttachmentThumbnail(attachment: screenshot.attachment, maxSize: CGSize(width: 96, height: 60), cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot")
                    .font(.system(size: 13, weight: .semibold))
                Text(screenshot.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !settings.provider.takesScreenshots {
                    Text("\(settings.provider.label) can't see screenshots — ⌘\(ProviderKind.aiMode.number) Google or ⌘\(ProviderKind.gemini.number) Gemini can.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RemoveButton(help: "Remove the screenshot") { controller.removeScreenshot() }
        }
        .padding(8)
        .padding(.trailing, 2)
        .surface(RoundedRectangle(cornerRadius: 16, style: .continuous), style: .smoke)
        .animation(.easeOut(duration: 0.18), value: settings.provider.takesScreenshots)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot attached: \(screenshot.title)")
    }
}

/// Why there's no screenshot, and what to do about it.
private struct NoticeCard: View {
    let notice: CaptureNotice
    @ObservedObject var controller: SearchController

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RemoveButton(help: "Dismiss") { controller.captureNotice = nil }
        }
        .padding(12)
        .surface(RoundedRectangle(cornerRadius: 16, style: .continuous), style: .smoke)
        .accessibilityElement(children: .contain)
    }

    private var name: String { BuildFlavor.appName }

    private var symbol: String {
        switch notice {
        case .needsPermission, .permissionLost: return "rectangle.dashed.badge.record"
        case .failed:                           return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch notice {
        case .needsPermission: return "Let \(name) see your screen"
        case .permissionLost:  return "macOS doesn't recognise this \(name)"
        case .failed:          return "No screenshot"
        }
    }

    private var message: String {
        switch notice {
        case .needsPermission:
            return "Turn on \(name) in System Settings › Privacy & Security › Screen & System Audio Recording, then try again. macOS may ask to reopen \(name) first."
        case .permissionLost:
            // An entry left from a build signed differently (ad-hoc, up to
            // 0.5.1) looks on, and no longer matches.
            return "Screenshots worked before, so an entry for \(name) is probably there but for an earlier build. In Screen & System Audio Recording, remove \(name) with the − button, add it again, then try again."
        case .failed(let message):
            return message
        }
    }

    private var actionTitle: String {
        switch notice {
        case .needsPermission, .permissionLost: return "Open System Settings"
        case .failed:                           return "Try Again"
        }
    }

    private func action() {
        switch notice {
        case .needsPermission, .permissionLost:
            ScreenCapture.openSettings()
        case .failed:
            controller.captureNotice = nil
            controller.captureScreen()
        }
    }
}

private struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A screenshot's thumbnail, fitted into `maxSize` without cropping, with a
/// hairline edge so a white window doesn't bleed into a light answer.
struct AttachmentThumbnail: View {
    let attachment: Attachment
    let maxSize: CGSize
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if let image = ThumbnailCache.image(for: attachment) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: maxSize.height, height: maxSize.height)
            }
        }
        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .accessibilityLabel("Screenshot: \(attachment.title)")
    }
}

/// Decoded once per screenshot, not on every redraw.
@MainActor
private enum ThumbnailCache {
    private static let cache = NSCache<NSUUID, NSImage>()

    static func image(for attachment: Attachment) -> NSImage? {
        let key = attachment.id as NSUUID
        if let image = cache.object(forKey: key) { return image }
        guard let image = NSImage(data: attachment.thumbnail) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

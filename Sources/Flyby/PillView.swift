import SwiftUI
import AppKit
import FlybyCore

/// The pill: the text capsule, and the ↩ and provider controls.
///
/// Two layouts, because glass changes what the right shape is. With Liquid
/// Glass the ↩ badge and the provider chip become small glass bubbles beside
/// the bar that flow out of it and back in — the Spotlight arrangement. Glass
/// shapes that overlap merge into one, so a glass badge *inside* the capsule
/// would simply vanish into it. Without glass the classic single capsule,
/// with both inside it, is the one that reads as a single object.
///
/// Both fold down to a small blob when Flyby isn't presented, which is where
/// opening springs out from and closing shrinks back to.

/// A glass bar with glass bubbles beside it. The root view renders it in the
/// same glass container as the panel, so the bubbles morph out of the bar and
/// the panel out of the whole pill.
@available(macOS 26.0, *)
struct GlassPill: View {
    @ObservedObject var controller: SearchController
    var focus: FocusState<Bool>.Binding
    let glass: Namespace.ID
    let isPresented: Bool
    @ObservedObject private var settings = AppSettings.shared

    enum Element: Hashable, Sendable {
        case field, submit, provider, panel
    }

    var body: some View {
        HStack(spacing: PillMetrics.bubbleSpacing) {
            PillField(controller: controller, focus: focus)
                .padding(.horizontal, PillMetrics.horizontalPadding)
                .frame(width: capsuleWidth, height: PillMetrics.height)
                .opacity(isPresented ? 1 : 0)
                .clipShape(Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID(Element.field, in: glass)

            if isPresented, hasQuery {
                ReturnBadge(style: .bubble) { controller.submit() }
                    .glassEffect(
                        .regular.tint(settings.accent.color.opacity(0.22)).interactive(),
                        in: Circle()
                    )
                    .glassEffectID(Element.submit, in: glass)
            }

            if isPresented {
                ProviderMenu(style: .bubble)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID(Element.provider, in: glass)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: capsuleWidth)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: hasQuery)
    }

    private var hasQuery: Bool { !controller.query.isEmpty }

    /// Folded up, the bar is a circle — the blob Flyby opens out of.
    private var capsuleWidth: CGFloat {
        isPresented
            ? PillMetrics.glassCapsuleWidth(for: controller.query, inConversation: controller.isResultVisible)
            : PillMetrics.height
    }

    /// How far the capsule's centre sits left of the row's, once the bubbles
    /// beside it are counted — where the panel folds down to.
    static func capsuleOffset(hasQuery: Bool, isPresented: Bool) -> CGFloat {
        isPresented ? -PillMetrics.glassBubblesWidth(hasQuery: hasQuery) / 2 : 0
    }
}

/// One blurred capsule with everything inside it — the pill without glass
/// (macOS 14–15, and Reduce Transparency).
struct ClassicPill: View {
    @ObservedObject var controller: SearchController
    var focus: FocusState<Bool>.Binding
    let isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            PillField(controller: controller, focus: focus)

            if hasQuery {
                ReturnBadge(style: .well) { controller.submit() }
                    .transition(.scale.combined(with: .opacity))
            }

            ProviderMenu(style: .well)
        }
        .padding(.horizontal, PillMetrics.horizontalPadding)
        .frame(width: width, height: PillMetrics.height)
        .opacity(isPresented ? 1 : 0)
        .surface(Capsule(), interactive: true)
        .shadow(
            color: .black.opacity(0.32),
            radius: PillMetrics.shadowRadius,
            y: PillMetrics.shadowOffsetY
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hasQuery)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: width)
    }

    private var hasQuery: Bool { !controller.query.isEmpty }

    private var width: CGFloat {
        isPresented
            ? PillMetrics.classicWidth(for: controller.query, inConversation: controller.isResultVisible)
            : PillMetrics.height
    }
}

// MARK: - Pieces

/// Leading glyph and the text field — the part both layouts share verbatim.
private struct PillField: View {
    @ObservedObject var controller: SearchController
    var focus: FocusState<Bool>.Binding
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: PillMetrics.leadingIconSpacing) {
            // The glass becomes a pulsing sparkle while an answer is on its
            // way: the pill is where your eyes are, and the panel above may
            // not have anything to show yet.
            Image(systemName: controller.isBusy ? "sparkles" : "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(controller.isBusy ? AnyShapeStyle(settings.accent.color) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: controller.isBusy && !reduceMotion)
                .frame(width: PillMetrics.leadingIconWidth)
                .animation(.easeOut(duration: 0.2), value: controller.isBusy)
                .accessibilityHidden(true)

            TextField(PillMetrics.placeholder(inConversation: controller.isResultVisible), text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: PillMetrics.fontSize))
                .focused(focus)
                .onSubmit { controller.submit() }
                .accessibilityLabel(controller.isResultVisible ? "Follow-up question" : "Search")

            if BuildFlavor.isDev {
                DevBadge()
                    .frame(width: PillMetrics.devBadgeWidth)
            }
        }
    }
}

private enum PillElementStyle {
    /// Drawn inside the classic capsule.
    case well
    /// A glass bubble beside the glass capsule; the layout adds the glass.
    case bubble
}

/// Appears once there's something to submit, so the affordance shows up
/// exactly when it becomes true. Clickable too — not everyone reaches for
/// Return.
private struct ReturnBadge: View {
    let style: PillElementStyle
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            Text("↩")
                .font(font)
                .foregroundStyle(settings.accent.color)
                .frame(width: size, height: size)
                .background {
                    if style == .well {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(settings.accent.color.opacity(0.16))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search (Return)")
        .accessibilityLabel("Submit search")
    }

    private var size: CGFloat {
        style == .bubble ? PillMetrics.bubbleSize : PillMetrics.returnBadgeSize
    }

    private var font: Font {
        switch style {
        case .bubble: return .system(size: 16, weight: .semibold)
        case .well:   return .system(size: 12, weight: .medium)
        }
    }
}

/// Icon-only so the pill stays narrow — but drawn as an actual control: a
/// filled well (or a glass bubble), a chevron, and a hover state. A bare
/// symbol with the menu indicator hidden reads as decoration, and nobody
/// clicks decoration.
private struct ProviderMenu: View {
    let style: PillElementStyle
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var google = GoogleSession.shared
    @State private var hovering = false

    var body: some View {
        Menu {
            // macOS 27 hides menu item icons unless asked; these ones say
            // where each answer lands, so ask.
            menuItems.labelStyle(.titleAndIcon)
        } label: {
            label
        }
        // `.borderlessButton` flattens a composed label down to its first
        // image, which loses the well and the chevron. `.button` + `.plain`
        // renders the label as written.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("\(settings.provider.label) — click to change")
        .accessibilityLabel("Answer with: \(settings.provider.label)")
    }

    @ViewBuilder
    private var menuItems: some View {
        Section("Answer with") {
            Picker("Provider", selection: $settings.provider) {
                ForEach(ProviderKind.allCases) {
                    Label($0.label, systemImage: $0.icon).tag($0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        // Only the browser hop uses this — including ⌘Return from any
        // provider — so it stays reachable but visibly separate.
        Section("Open in browser with") {
            Picker("Engine", selection: $settings.engine) {
                ForEach(SearchEngine.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Divider()
        Button {
            NotificationCenter.default.post(name: .flybyShouldShowHistory, object: nil)
        } label: {
            Label("Recent Chats  ↑", systemImage: "clock.arrow.circlepath")
        }

        // AI Mode without an account is the CAPTCHA-prone path; the fix is
        // one click away, so offer it where the choice is made.
        if settings.provider == .aiMode, !google.isConnected {
            Divider()
            Button {
                SettingsNavigation.showGoogleAccount()
            } label: {
                Label("Connect Google Account…", systemImage: "person.crop.circle.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .well:
            glyphs
                .frame(width: PillMetrics.providerChipWidth, height: PillMetrics.providerChipHeight)
                .background(Color.primary.opacity(hovering ? 0.14 : 0.07), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(hovering ? 0.16 : 0.09), lineWidth: 1))
                .contentShape(Capsule())
        case .bubble:
            // The whole bubble is the hit target, not just the glyphs.
            glyphs
                .frame(width: PillMetrics.glassChipWidth, height: PillMetrics.bubbleSize)
                .contentShape(Capsule())
        }
    }

    private var glyphs: some View {
        HStack(spacing: 3) {
            Image(systemName: settings.provider.icon)
                .font(.system(size: style == .bubble ? CGFloat(14) : CGFloat(12), weight: .medium))
                .frame(width: 16)

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .frame(width: 7)
                .opacity(0.7)
        }
        .foregroundStyle(hovering ? AnyShapeStyle(settings.accent.color) : AnyShapeStyle(.secondary))
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension Notification.Name {
    static let quickSearchDidShow = Notification.Name("quickSearchDidShow")
    /// Opens the history list, from the pill's menu.
    static let flybyShouldShowHistory = Notification.Name("flybyShouldShowHistory")
}

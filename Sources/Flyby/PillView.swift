import SwiftUI
import AppKit
import FlybyCore

/// The capsule. Sits centred in an oversized transparent window and animates
/// its own width, so growing as you type costs no window resizing.
///
/// Two layouts, because glass changes what the right shape is. With Liquid
/// Glass the ↩ badge and the provider chip become small glass bubbles beside
/// the bar that flow out of it and back in — the Spotlight arrangement. Glass
/// shapes that overlap merge into one, so a glass badge *inside* the capsule
/// would simply vanish into it. Without glass the classic single capsule,
/// with both inside it, is the one that reads as a single object.
struct PillView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject private var settings = AppSettings.shared
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            pill
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themed()
        .onAppear { inputFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .quickSearchDidShow)) { _ in
            inputFocused = true
        }
    }

    /// Same condition `Surface` uses, so the two can't disagree about whether
    /// glass is on.
    @ViewBuilder
    private var pill: some View {
        if #available(macOS 26.0, *), settings.liquidGlass, !reduceTransparency {
            GlassPill(controller: controller, focus: $inputFocused)
        } else {
            ClassicPill(controller: controller, focus: $inputFocused)
        }
    }
}

// MARK: - Layouts

/// A glass bar with glass bubbles beside it, rendered together so the bubbles
/// morph out of the bar as they appear.
@available(macOS 26.0, *)
private struct GlassPill: View {
    @ObservedObject var controller: SearchController
    var focus: FocusState<Bool>.Binding
    @ObservedObject private var settings = AppSettings.shared
    @Namespace private var glass

    private enum Element: Hashable, Sendable {
        case field, submit, provider
    }

    var body: some View {
        // Container spacing equal to the stack's: the bubbles sit apart at
        // rest and only flow into the bar while they appear or leave. Larger
        // and they'd melt into it permanently.
        GlassEffectContainer(spacing: PillMetrics.bubbleSpacing) {
            HStack(spacing: PillMetrics.bubbleSpacing) {
                PillField(controller: controller, focus: focus)
                    .padding(.horizontal, PillMetrics.horizontalPadding)
                    .frame(width: capsuleWidth, height: PillMetrics.height)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID(Element.field, in: glass)

                if hasQuery {
                    ReturnBadge(style: .bubble) { controller.submit() }
                        .glassEffect(
                            .regular.tint(settings.accent.color.opacity(0.22)).interactive(),
                            in: Circle()
                        )
                        .glassEffectID(Element.submit, in: glass)
                }

                ProviderMenu(style: .bubble)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID(Element.provider, in: glass)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: capsuleWidth)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: hasQuery)
    }

    private var hasQuery: Bool { !controller.query.isEmpty }
    private var capsuleWidth: CGFloat { PillMetrics.glassCapsuleWidth(for: controller.query) }
}

/// One blurred capsule with everything inside it — the pre-glass pill, and
/// what Reduce Transparency gets.
private struct ClassicPill: View {
    @ObservedObject var controller: SearchController
    var focus: FocusState<Bool>.Binding

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
    private var width: CGFloat { PillMetrics.classicWidth(for: controller.query) }
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

            TextField(PillMetrics.placeholder, text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: PillMetrics.fontSize))
                .focused(focus)
                .onSubmit { controller.submit() }
                .accessibilityLabel("Search")

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
}

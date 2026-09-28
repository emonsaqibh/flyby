import SwiftUI

/// Whether Apple Intelligence can answer on this Mac, shown wherever it's
/// picked as the provider — so "it's turned off" is found out here, with the
/// fix a click away, rather than as a failed first question.
///
/// Redraws by itself when the model becomes available: the readiness it reads
/// comes from an observable `SystemLanguageModel`. The symbol morphs between
/// states, and bounces once when the model turns ready.
struct AppleIntelligenceStatus: View {
    var body: some View {
        let readiness = AppleIntelligenceProvider.readiness
        Group {
            if let problem = readiness.problem {
                LabeledContent {
                    if readiness == .turnedOff {
                        Button("Open System Settings…") { AppleIntelligenceProvider.openSystemSettings() }
                    }
                } label: {
                    Label {
                        Text(problem)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        icon(for: readiness)
                    }
                }
            } else {
                Label {
                    Text("Ready. Questions and answers never leave this Mac.")
                        .foregroundStyle(.secondary)
                } icon: {
                    icon(for: readiness)
                }
            }
        }
        .font(.callout)
        .animation(.smooth, value: readiness)
    }

    private func icon(for readiness: AppleIntelligenceProvider.Readiness) -> some View {
        Image(systemName: symbol(for: readiness))
            .symbolRenderingMode(readiness == .turnedOff ? .multicolor : .monochrome)
            .foregroundStyle(tint(for: readiness))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: readiness == .preparing)
            .symbolEffect(.bounce, value: readiness == .ready)
    }

    private func tint(for readiness: AppleIntelligenceProvider.Readiness) -> AnyShapeStyle {
        switch readiness {
        case .ready:        return AnyShapeStyle(.green)
        case .preparing:    return AnyShapeStyle(.tint)
        case .turnedOff, .unsupported: return AnyShapeStyle(.secondary)
        }
    }

    private func symbol(for readiness: AppleIntelligenceProvider.Readiness) -> String {
        switch readiness {
        case .ready:        return "checkmark.circle.fill"
        case .turnedOff:    return "exclamationmark.triangle.fill"
        case .preparing:    return "arrow.down.circle.dotted"
        case .unsupported:  return "xmark.circle.fill"
        }
    }
}

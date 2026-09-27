import SwiftUI

/// Wraps chips onto as many lines as they need.
///
/// A chip wider than the whole row is offered the row's width instead of its
/// ideal one, so a long follow-up question wraps or truncates inside the
/// column rather than running off the edge of it.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width == .infinity ? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: item.proposal
                )
            }
        }
    }

    private struct Item {
        var index: Int
        var x: CGFloat
        var proposal: ProposedViewSize
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [Item]
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            var proposal = ProposedViewSize.unspecified
            var size = subview.sizeThatFits(proposal)
            if width.isFinite, size.width > width {
                proposal = ProposedViewSize(width: width, height: nil)
                size = subview.sizeThatFits(proposal)
            }
            if x + size.width > width, !current.items.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing, height: 0, items: [])
                x = 0
            }
            current.items.append(Item(index: index, x: x, proposal: proposal))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

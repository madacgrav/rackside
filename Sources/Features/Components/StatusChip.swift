import SwiftUI

struct StatusChip: View {
    let status: SessionStatus

    var body: some View {
        if let spec {
            Label(spec.text, systemImage: spec.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(spec.color.opacity(0.18), in: Capsule())
                .foregroundStyle(spec.color)
                .accessibilityLabel(spec.text)
        }
    }

    private var spec: (text: String, symbol: String, color: Color)? {
        switch status {
        case .scheduled: nil
        case .completed: ("Completed", "checkmark.circle.fill", Theme.Colors.success)
        case .cancelled: ("Cancelled", "xmark.circle.fill", Color.secondary)
        case .noShow: ("No-show", "person.fill.xmark", Theme.Colors.warning)
        }
    }
}

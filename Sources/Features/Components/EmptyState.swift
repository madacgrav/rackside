import SwiftUI

/// Standardizes the copy and symbol of a `ContentUnavailableView` overlay.
struct EmptyState: View {
    let title: String
    let area: Theme.Area
    var description: String? = nil
    var action: (title: String, run: () -> Void)? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 88

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: Theme.Spacing.md) {
                // Capped so the badge leaves room for the title in short overlays (Schedule) at AX sizes.
                SymbolBadge(systemImage: area.systemImage, fill: area.color, size: min(badgeSize, 96))
                Text(title).font(Theme.Fonts.display(.title2))
            }
            .accessibilityElement(children: .combine)
        } description: {
            if let description { Text(description) }
        } actions: {
            if let action {
                Button(action.title, action: action.run).buttonStyle(.borderedProminent)
            }
        }
    }
}

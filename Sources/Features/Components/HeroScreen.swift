import SwiftUI

/// Centered icon + headline + primary button (lock screen, recovery).
struct HeroScreen<Extra: View>: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    let fill: AnyShapeStyle
    let symbol: Color
    let primary: (title: String, run: () -> Void)
    @ViewBuilder var extra: () -> Extra
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 96

    init(systemImage: String, title: String, message: String? = nil,
         fill: some ShapeStyle = Theme.Gradients.brand, symbol: Color = .white,
         primary: (title: String, run: () -> Void),
         @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.fill = AnyShapeStyle(fill)
        self.symbol = symbol
        self.primary = primary
        self.extra = extra
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SymbolBadge(systemImage: systemImage, fill: fill, size: iconSize, symbol: symbol)
            Text(title)
                .font(Theme.Fonts.display(.title2))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(primary.title, action: primary.run)
                .buttonStyle(.borderedProminent)
            extra()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }
}

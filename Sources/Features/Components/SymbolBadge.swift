import SwiftUI

/// SF Symbol knocked out of a filled rounded square (Settings-style app badge).
struct SymbolBadge<Fill: ShapeStyle>: View {
    let systemImage: String
    let fill: Fill
    var size: CGFloat
    var symbol: Color = .white

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbol)
            }
            .accessibilityHidden(true)
    }
}

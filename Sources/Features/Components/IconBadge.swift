import SwiftUI

/// 28pt Settings-style row icon.
struct IconBadge: View {
    let systemImage: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        SymbolBadge(systemImage: systemImage, fill: color, size: size)
    }
}

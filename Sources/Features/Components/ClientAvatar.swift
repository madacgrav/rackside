import SwiftUI

/// Initials on a stable per-client color.
struct ClientAvatar: View {
    let name: String
    let id: UUID
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Theme.avatarColor(for: id.uuidString))
            .frame(width: size, height: size)
            .overlay {
                Text(Self.initials(name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

import SwiftUI

/// Drop-in replacement for `Section { Text(msg).foregroundStyle(.red) }`.
struct ErrorBanner: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label(message, systemImage: "exclamationmark.octagon.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.Colors.danger)
                    .font(.callout)
                    .accessibilityLabel("Error: \(message)")
            }
        }
    }
}

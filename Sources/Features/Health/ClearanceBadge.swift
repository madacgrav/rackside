import SwiftUI

/// One-line summary of a client's medical-clearance state.
struct ClearanceBadge: View {
    let status: ClearanceStatus

    var body: some View {
        switch status {
        case .needed:
            Label("Medical clearance recommended", systemImage: "cross.case.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.warning)
        case .received(let date):
            Label("Clearance received \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.success)
        case .clear:
            Label("No screening flags", systemImage: "checkmark.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.success)
        case .notScreened:
            Label("Not screened yet", systemImage: "questionmark.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.brandTertiary)
        }
    }
}

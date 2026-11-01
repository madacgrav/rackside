import SwiftUI

struct OptionalStepper: View {
    let label: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let defaultValue: Int
    var step: Int = 1

    var body: some View {
        if let current = value {
            AdaptiveLabeledRow(label: label) {
                HStack(spacing: Theme.Spacing.xs) {
                    MetricStepper(
                        label: label,
                        value: Binding(get: { Double(current) }, set: { value = Int($0) }),
                        step: Double(step),
                        range: Double(range.lowerBound)...Double(range.upperBound),
                        fractionDigits: 0
                    )
                    IconButton(title: "Clear", systemImage: "xmark.circle.fill", tint: .tertiary) { value = nil }
                }
            }
        } else {
            HStack {
                Text(label)
                Spacer()
                Button("Set") { value = defaultValue }
            }
        }
    }
}

/// Label beside its control when there is room; label above it at accessibility sizes.
struct AdaptiveLabeledRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label)
                Spacer()
                control()
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(label)
                control()
            }
        }
    }
}

/// `OptionalStepper` for fractional values (sleep hours, body measurements).
struct OptionalDecimalStepper: View {
    let label: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let defaultValue: Double
    var step: Double = 1
    var fractionDigits: Int = 1

    var body: some View {
        if let current = value {
            AdaptiveLabeledRow(label: label) {
                HStack(spacing: Theme.Spacing.xs) {
                    MetricStepper(
                        label: label,
                        value: Binding(get: { current }, set: { value = $0 }),
                        step: step,
                        range: range,
                        fractionDigits: fractionDigits
                    )
                    IconButton(title: "Clear", systemImage: "xmark.circle.fill", tint: .tertiary) { value = nil }
                }
            }
        } else {
            HStack {
                Text(label)
                Spacer()
                Button("Set") { value = defaultValue }
            }
        }
    }
}

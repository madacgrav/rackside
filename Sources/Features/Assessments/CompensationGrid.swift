import SwiftUI

/// One row per compensation with tinted R/L (or Yes) toggle buttons, like the
/// weekday picker in SessionEditView.
struct CompensationGrid<T: CompensationSet>: View {
    /// Per-side scoring; nil for single yes/no views (lateral, modified retests).
    var right: Binding<T>?
    var left: Binding<T>?
    var single: Binding<T>?

    var body: some View {
        ForEach(T.items, id: \.0.rawValue) { item, label in
            AdaptiveLabeledRow(label: label) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let single {
                        toggle("Yes", item: item, in: single, accessibility: label)
                    } else {
                        if let right { toggle("R", item: item, in: right, accessibility: "\(label), right side") }
                        if let left { toggle("L", item: item, in: left, accessibility: "\(label), left side") }
                    }
                }
            }
        }
    }

    private func toggle(_ title: String, item: T, in set: Binding<T>, accessibility: String) -> some View {
        let isOn = set.wrappedValue.contains(item)
        return Button(title) {
            if isOn { set.wrappedValue.remove(item) } else { set.wrappedValue.insert(item) }
        }
        .buttonStyle(.bordered)
        .tint(isOn ? Theme.Colors.accent : Color.secondary)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension CompensationGrid {
    init(right: Binding<T>, left: Binding<T>) {
        self.init(right: right, left: left, single: nil)
    }

    init(single: Binding<T>) {
        self.init(right: nil, left: nil, single: single)
    }
}

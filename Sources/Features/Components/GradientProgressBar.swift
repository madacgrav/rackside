import SwiftUI

/// Capsule progress bar filled with the brand gradient.
struct GradientProgressBar: View {
    private enum Source { case value(Double), countdown(ClosedRange<Date>) }
    private let source: Source
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 6

    init(value: Double, total: Double = 1) {
        source = .value(total > 0 ? value / total : 0)
    }

    /// Remaining fraction of a countdown, like `ProgressView(timerInterval:countsDown: true)`.
    init(countdown interval: ClosedRange<Date>) { source = .countdown(interval) }

    static func remainingFraction(of interval: ClosedRange<Date>, at now: Date) -> Double {
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard total > 0 else { return 0 }
        return min(max(interval.upperBound.timeIntervalSince(now) / total, 0), 1)
    }

    var body: some View {
        switch source {
        case .value(let fraction):
            bar(fraction)
        case .countdown(let interval):
            TimelineView(.animation(minimumInterval: 0.2)) { context in
                bar(Self.remainingFraction(of: interval, at: context.date))
            }
        }
    }

    private func bar(_ fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Theme.Gradients.brand)
                    .frame(width: max(clamped > 0 ? height : 0, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

import SwiftUI

/// Header + one row per planned set. Logged rows are read-only and success-tinted;
/// the first unlogged row is the editable draft with a stepper strip beneath it.
struct SetTableView: View {
    let entry: PlannedEntryDTO
    let exercise: ExerciseDTO?
    let logged: [SetRecordDTO]
    let previous: SetRecordDTO?
    let onLog: (SetDraft) -> Void
    let onDelete: (SetRecordDTO) -> Void
    /// Starts a countdown of the given seconds for this entry; nil hides the control.
    let onStartTimer: ((Int) -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TimerStore.self) private var timers
    @State private var draft: SetDraft
    @State private var focusedMetric: Metric
    /// True once the trainer edits or logs the draft; a seeded-but-untouched draft is
    /// replaced when the exercise or previous set arrives after the first render.
    @State private var draftTouched = false

    enum Metric: CaseIterable {
        case weight, reps, duration, distance
    }

    init(entry: PlannedEntryDTO, exercise: ExerciseDTO?, logged: [SetRecordDTO], previous: SetRecordDTO?,
         onLog: @escaping (SetDraft) -> Void, onDelete: @escaping (SetRecordDTO) -> Void,
         onStartTimer: ((Int) -> Void)? = nil) {
        self.entry = entry
        self.exercise = exercise
        self.logged = logged
        self.previous = previous
        self.onLog = onLog
        self.onDelete = onDelete
        self.onStartTimer = onStartTimer
        let metrics = exercise?.metrics ?? [.weight, .reps]
        _draft = State(initialValue: Self.initialDraft(entry: entry, previous: previous, metrics: metrics))
        _focusedMetric = State(initialValue: Self.firstMetric(in: metrics))
    }

    private var metrics: MetricSet { exercise?.metrics ?? [.weight, .reps] }
    private var unit: Unit { exercise?.defaultUnit ?? .lb }
    private var columns: [Metric] { Metric.allCases.filter { metrics.contains(metricSet($0)) } }
    private var plannedCount: Int { max(entry.targetSets ?? 1, logged.count + 1) }
    private var stacked: Bool { typeSize >= .accessibility1 }
    private var countdownRunningHere: Bool {
        if case .timedSet(let id, _) = timers.active?.kind { id == entry.id } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !stacked { header }
            ForEach(0..<plannedCount, id: \.self) { index in
                if index < logged.count {
                    loggedRow(logged[index], index: index)
                } else if index == logged.count {
                    draftRow(index: index)
                    if metrics.contains(.duration), let onStartTimer { countdownControl(onStartTimer) }
                    if !columns.isEmpty { stepperStrip }
                } else {
                    placeholderRow(index: index)
                }
            }
        }
        // The exercise and previous set arrive after the first render; re-seed the
        // draft from them as long as the trainer has not touched it.
        .onChange(of: exercise?.id) { resetDraftIfUntouched() }
        .onChange(of: previous?.id) { resetDraftIfUntouched() }
        // A finished countdown for this entry fills in the seconds; logging stays a tap.
        .onChange(of: timers.lastCompletion) { _, completion in
            guard let completion, case .timedSet(let id, _) = completion.kind, id == entry.id else { return }
            draft = draft.prefilled(duration: completion.seconds, metrics: metrics)
            draftTouched = true
            focusedMetric = .duration
        }
    }

    // MARK: - Rows

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("Set").frame(width: 36, alignment: .leading)
            Text("Prev").frame(maxWidth: .infinity)
            ForEach(columns, id: \.self) { Text(title($0)).frame(maxWidth: .infinity) }
            Color.clear.frame(width: 44, height: 1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func loggedRow(_ set: SetRecordDTO, index: Int) -> some View {
        layout(index: index) {
            Text(previousText).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.tertiary)
        } cells: {
            ForEach(columns, id: \.self) { metric in
                labeled(metric) { Text(valueText(set, metric)) }
            }
        } trailing: {
            IconButton(title: "Delete set \(index + 1)", systemImage: "checkmark.circle.fill",
                       role: .destructive, tint: Theme.Colors.success) { onDelete(set) }
        }
        .font(Theme.Fonts.numeric)
        .padding(.horizontal, Theme.Spacing.xs)
        .background(Theme.Colors.success.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set \(index + 1) logged, \(summary(set))")
    }

    private func draftRow(index: Int) -> some View {
        layout(index: index) {
            Button(previousText) {
                if let previous {
                    draft = SetDraft(from: previous, metrics: metrics)
                    draftTouched = true
                }
            }
            .buttonStyle(.plain)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Copy previous set \(previousText)")
            .disabled(previous == nil)
        } cells: {
            ForEach(columns, id: \.self) { metric in
                labeled(metric) {
                    Button(draftText(metric)) { focusedMetric = metric }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            focusedMetric == metric ? Theme.Colors.accent.opacity(0.18) : Theme.Colors.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.row)
                        )
                        .accessibilityLabel("\(name(metric)) \(draftText(metric))")
                        .accessibilityHint("Edits this value with the stepper below")
                }
            }
        } trailing: {
            Button {
                draftTouched = true
                onLog(draft)
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Log set \(index + 1)")
        }
        .font(Theme.Fonts.numeric)
    }

    @ViewBuilder
    private func countdownControl(_ onStart: @escaping (Int) -> Void) -> some View {
        let seconds = draft.duration ?? 0
        Group {
            if countdownRunningHere {
                Button("Stop countdown", systemImage: "stop.fill") { timers.skip() }
            } else {
                Button("Start \(seconds) s countdown", systemImage: "timer") { onStart(seconds) }
                    .disabled(seconds <= 0)
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func placeholderRow(index: Int) -> some View {
        layout(index: index) {
            Text(previousText).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.tertiary)
        } cells: {
            ForEach(columns, id: \.self) { metric in
                labeled(metric) { Text("—").foregroundStyle(.quaternary) }
            }
        } trailing: {
            Color.clear.frame(width: 44, height: 44)
        }
        .font(Theme.Fonts.numeric)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set \(index + 1) not logged yet")
    }

    @ViewBuilder private var stepperStrip: some View {
        switch focusedMetric {
        case .weight:
            MetricStepper(
                label: "Weight (\(WeightFormatter.label(unit)))",
                value: Binding(get: { draft.weight ?? 0 }, set: { draft.weight = $0; draftTouched = true }),
                step: WeightFormatter.stepIncrement(for: unit)
            )
        case .reps:
            MetricStepper(
                label: "Reps",
                value: Binding(get: { Double(draft.reps ?? 0) }, set: { draft.reps = Int($0); draftTouched = true }),
                step: 1, fractionDigits: 0
            )
        case .duration:
            MetricStepper(
                label: "Duration (sec)",
                value: Binding(get: { Double(draft.duration ?? 0) }, set: { draft.duration = Int($0); draftTouched = true }),
                step: 15, fractionDigits: 0
            )
        case .distance:
            MetricStepper(
                label: "Distance (\(unit.rawValue))",
                value: Binding(get: { draft.distance ?? 0 }, set: { draft.distance = $0; draftTouched = true }),
                step: 0.25, fractionDigits: 2
            )
        }
    }

    // MARK: - Layout helpers

    /// HStack of cells when there is room; a labeled VStack at accessibility sizes.
    private func layout<Prev: View, Cells: View, Trailing: View>(
        index: Int,
        @ViewBuilder prev: () -> Prev,
        @ViewBuilder cells: () -> Cells,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("Set \(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        trailing()
                    }
                    HStack {
                        Text("Prev").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        prev()
                    }
                    cells()
                }
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("\(index + 1)").frame(width: 36, alignment: .leading)
                    prev().frame(maxWidth: .infinity)
                    cells()
                    trailing()
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// Stacked rows carry the column name beside each value; wide rows rely on the header.
    @ViewBuilder
    private func labeled<Content: View>(_ metric: Metric, @ViewBuilder content: () -> Content) -> some View {
        if stacked {
            HStack {
                Text(name(metric)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                content()
            }
        } else {
            content().frame(maxWidth: .infinity)
        }
    }

    // MARK: - Formatting

    private func title(_ metric: Metric) -> String {
        switch metric {
        case .weight: WeightFormatter.label(unit)
        case .reps: "Reps"
        case .duration: "Sec"
        case .distance: unit.rawValue
        }
    }

    private func name(_ metric: Metric) -> String {
        switch metric {
        case .weight: "Weight"
        case .reps: "Reps"
        case .duration: "Duration"
        case .distance: "Distance"
        }
    }

    private func metricSet(_ metric: Metric) -> MetricSet {
        switch metric {
        case .weight: .weight
        case .reps: .reps
        case .duration: .duration
        case .distance: .distance
        }
    }

    private var previousText: String { previous.map(summary) ?? "—" }

    /// "135 lb ×8 30s 1.5 mi" — the same shape the old entry row used.
    private func summary(_ set: SetRecordDTO) -> String {
        var parts: [String] = []
        if let weight = set.weight { parts.append(WeightFormatter.string(weight, unit: unit)) }
        if let reps = set.reps { parts.append("×\(reps)") }
        if let duration = set.duration { parts.append("\(duration)s") }
        if let distance = set.distance { parts.append("\(distance.formatted()) \(unit.rawValue)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private func valueText(_ set: SetRecordDTO, _ metric: Metric) -> String {
        switch metric {
        case .weight: set.weight.map { $0.formatted() } ?? "—"
        case .reps: set.reps.map { "\($0)" } ?? "—"
        case .duration: set.duration.map { "\($0)" } ?? "—"
        case .distance: set.distance.map { $0.formatted() } ?? "—"
        }
    }

    private func draftText(_ metric: Metric) -> String {
        switch metric {
        case .weight: (draft.weight ?? 0).formatted()
        case .reps: "\(draft.reps ?? 0)"
        case .duration: "\(draft.duration ?? 0)"
        case .distance: (draft.distance ?? 0).formatted()
        }
    }

    private static func initialDraft(entry: PlannedEntryDTO, previous: SetRecordDTO?, metrics: MetricSet) -> SetDraft {
        previous.map { SetDraft(from: $0, metrics: metrics) } ?? SetDraft(target: entry, metrics: metrics)
    }

    private static func firstMetric(in metrics: MetricSet) -> Metric {
        if metrics.contains(.weight) { return .weight }
        if metrics.contains(.reps) { return .reps }
        if metrics.contains(.duration) { return .duration }
        return .distance
    }

    private func resetDraftIfUntouched() {
        guard !draftTouched else { return }
        draft = Self.initialDraft(entry: entry, previous: previous, metrics: metrics)
        focusedMetric = Self.firstMetric(in: metrics)
    }
}

#Preview("Set table") {
    List {
        Section("Upper A") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                TitleCaptionRow(title: "Bench Press", caption: "Target: 3×8 @ 135 lb")
                SetTableView(
                    entry: PreviewFixtures.scheduledSession.instances[0].plannedEntries[0],
                    exercise: PreviewFixtures.bench,
                    logged: PreviewFixtures.loggedSets,
                    previous: PreviewFixtures.loggedSets[1],
                    onLog: { _ in },
                    onDelete: { _ in }
                )
            }
            .themedRows()
        }
    }
    .themedScreen()
    .environment(TimerStore.preview)
}

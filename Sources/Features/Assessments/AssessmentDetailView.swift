import SwiftUI

struct AssessmentDetailView: View {
    let assessment: AssessmentDTO
    let previous: AssessmentDTO?
    let weightUnit: Unit
    /// nil hides the Edit button (read-only, e.g. the intake review).
    var onEdit: (() -> Void)?

    private var usesImperial: Bool { weightUnit == .lb }
    private var diff: AssessmentDiff { AssessmentDTO.diff(assessment, previous: previous) }

    var body: some View {
        List {
            Section(previous.map { "Changes since \($0.performedOn.formatted(date: .abbreviated, time: .omitted))" } ?? "Changes") {
                if previous == nil {
                    Text("First assessment").foregroundStyle(.secondary)
                } else if diff.isEmpty {
                    Text("No changes").foregroundStyle(.secondary)
                }
                ForEach(diff.resolved, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.Colors.success)
                }
                ForEach(diff.new, id: \.self) { item in
                    Label(item, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Theme.Colors.warning)
                }
                ForEach(diff.measurementDeltas, id: \.field) { delta in
                    LabeledContent(delta.field.label, value: deltaText(delta))
                }
            }
            .themedRows()
            if assessment.sections.contains(.measurements) {
                Section("Measurements") {
                    measurementRows(assessment.measurements)
                }
                .themedRows()
            }
            if assessment.sections.contains(.overheadSquat) {
                Section("Overhead Squat") {
                    findings([
                        ("Anterior · Right", labels(assessment.ohsAnteriorRight)),
                        ("Anterior · Left", labels(assessment.ohsAnteriorLeft)),
                        ("Lateral", labels(assessment.ohsLateral)),
                        ("Posterior · Right", labels(assessment.ohsPosteriorRight)),
                        ("Posterior · Left", labels(assessment.ohsPosteriorLeft)),
                        ("Heels elevated — resolved", labels(assessment.ohsHeelsElevated)),
                        ("Arms down — resolved", labels(assessment.ohsArmsDown)),
                    ])
                    if let notes = assessment.ohsNotes {
                        LabeledContent("Notes", value: notes)
                    }
                }
                .themedRows()
            }
            if assessment.sections.contains(.singleLegSquat) {
                Section("Single Leg Squat") {
                    findings([
                        ("Right leg", labels(assessment.slsRight)),
                        ("Left leg", labels(assessment.slsLeft)),
                    ])
                    if let notes = assessment.slsNotes {
                        LabeledContent("Notes", value: notes)
                    }
                }
                .themedRows()
            }
        }
        .themedScreen()
        .navigationTitle(assessment.performedOn.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            if let onEdit {
                Button("Edit", action: onEdit)
            }
        }
    }

    @ViewBuilder
    private func findings(_ groups: [(String, [String])]) -> some View {
        let present = groups.filter { !$0.1.isEmpty }
        if present.isEmpty {
            Text("No compensations").foregroundStyle(.secondary)
        }
        ForEach(present, id: \.0) { title, items in
            LabeledContent(title, value: items.joined(separator: ", "))
        }
    }

    private func labels<T: CompensationSet>(_ set: T) -> [String] {
        T.items.filter { set.contains($0.0) }.map(\.1)
    }

    @ViewBuilder
    private func measurementRows(_ m: Measurements) -> some View {
        if let hr = m.restingHR { LabeledContent("Resting HR", value: "\(hr) bpm") }
        if let sys = m.systolic, let dia = m.diastolic { LabeledContent("Blood pressure", value: "\(sys)/\(dia)") }
        if let h = m.heightCm { LabeledContent("Height", value: length(h)) }
        if let w = m.weightKg { LabeledContent("Weight", value: mass(w)) }
        if let w = m.waistCm { LabeledContent("Waist", value: length(w)) }
        if let h = m.hipCm { LabeledContent("Hip", value: length(h)) }
        if let bf = m.bodyFatPct { LabeledContent("Body fat", value: "\(bf.formatted(.number.precision(.fractionLength(1))))%") }
        if let bmi = m.bmi { LabeledContent("BMI", value: bmi.formatted(.number.precision(.fractionLength(1)))) }
        if let r = m.waistToHip { LabeledContent("Waist-to-hip", value: r.formatted(.number.precision(.fractionLength(2)))) }
        if let p = m.pushUps { LabeledContent("Push-ups", value: "\(p)") }
        if let s = m.plankSeconds { LabeledContent("Plank", value: "\(s) sec") }
        if m.isEmpty { Text("No measurements recorded").foregroundStyle(.secondary) }
    }

    private func length(_ cm: Double) -> String {
        let v = usesImperial ? cm / Measurements.cmPerInch : cm
        return "\(v.formatted(.number.precision(.fractionLength(1)))) \(usesImperial ? "in" : "cm")"
    }

    private func mass(_ kg: Double) -> String {
        let v = usesImperial ? kg / Measurements.kgPerLb : kg
        return "\(v.formatted(.number.precision(.fractionLength(1)))) \(usesImperial ? "lb" : "kg")"
    }

    private func deltaText(_ d: MeasurementDelta) -> String {
        let value: Double
        let unit: String
        switch d.field {
        case .weight:
            value = usesImperial ? d.delta / Measurements.kgPerLb : d.delta
            unit = usesImperial ? " lb" : " kg"
        case .waist, .hip:
            value = usesImperial ? d.delta / Measurements.cmPerInch : d.delta
            unit = usesImperial ? " in" : " cm"
        case .bodyFat: value = d.delta; unit = "%"
        case .restingHR: value = d.delta; unit = " bpm"
        case .pushUps: value = d.delta; unit = ""
        case .plank: value = d.delta; unit = " sec"
        }
        return value.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always())) + unit
    }
}

#Preview("Assessment detail") {
    NavigationStack {
        AssessmentDetailView(
            assessment: PreviewFixtures.assessments[0],
            previous: PreviewFixtures.assessments[1],
            weightUnit: .lb,
            onEdit: {}
        )
    }
}

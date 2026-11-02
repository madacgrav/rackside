import SwiftUI
import UIKit

struct ReportFiles: Equatable {
    let pdf: URL
    let png: URL
}

/// Renders a report page to a shareable PDF and PNG.
enum ReportExporter {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter @72dpi

    /// Sweeps earlier reports, renders `page` as `<baseName>.pdf` and `<baseName>.png`.
    @MainActor
    static func render(_ page: some View, baseName: String) throws -> ReportFiles {
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = .init(pageSize)
        renderer.scale = 3

        // Reports hold client PII: keep them in their own tmp folder so the view
        // can sweep them on disappear, and protect the files like the data store.
        let fm = FileManager.default
        removeReports()
        try fm.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let name = sanitized(baseName)
        let pdf = reportsDirectory.appending(path: "\(name).pdf")
        let png = reportsDirectory.appending(path: "\(name).png")

        var renderError: Error?
        renderer.render { size, renderIn in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(pdf as CFURL, mediaBox: &mediaBox, nil) else {
                renderError = CocoaError(.fileWriteUnknown)
                return
            }
            context.beginPDFPage(nil)
            renderIn(context)
            context.endPDFPage()
            context.closePDF()
        }
        if let renderError { throw renderError }

        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: png, options: .completeFileProtection)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: pdf.path)
        return ReportFiles(pdf: pdf, png: png)
    }

    static let reportsDirectory = FileManager.default.temporaryDirectory
        .appending(path: "Reports", directoryHint: .isDirectory)

    /// Deletes every rendered report. Call when the report screen goes away.
    static func removeReports() {
        try? FileManager.default.removeItem(at: reportsDirectory)
    }

    /// Names come from user input; path separators and colons would otherwise
    /// make CGContext fail to create the file.
    private static func sanitized(_ name: String) -> String {
        let cleaned = name.map { "/:".contains($0) ? "-" : $0 }
        return String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The printable per-exercise page.
struct ExerciseReportPage: View {
    let clientName: String
    let exerciseName: String
    let points: [ProgressPoint]
    let personalBest: SetRecordDTO?
    let unit: Unit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rackside Progress Report").font(.title.bold())
            Text(clientName).font(.title2)
            Text(exerciseName).font(.headline).foregroundStyle(.secondary)
            if let pb = personalBest, let weight = pb.weight {
                Text("Personal best: \(WeightFormatter.string(weight, unit: unit)) on \(pb.performedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
            }
            Text("Top-set weight").font(.caption.bold())
            ExerciseProgressChart(points: points, personalBest: personalBest, metric: \.topSetWeight,
                                  unitLabel: WeightFormatter.label(unit), height: 150)
            Text("Estimated 1RM (Epley)").font(.caption.bold())
            ExerciseProgressChart(points: points, personalBest: nil, metric: \.est1RM,
                                  unitLabel: WeightFormatter.label(unit), height: 150)
            Text("Total reps").font(.caption.bold())
            ExerciseProgressChart(points: points, personalBest: nil, metric: \.totalRepsMetric,
                                  unitLabel: "reps", height: 150)
            Text("Generated \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(32)
        .frame(width: ReportExporter.pageSize.width, height: ReportExporter.pageSize.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

/// The printable client overview page.
struct ClientOverviewPage: View {
    let clientName: String
    let window: ReportWindow
    let consistency: ConsistencySummary?
    let weeks: [WeeklyVolume]
    /// (exercise name, detail line) already formatted by the view model.
    let topExercises: [(name: String, detail: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rackside Progress Report").font(.title.bold())
            Text(clientName).font(.title2)
            Text(window.title).font(.headline).foregroundStyle(.secondary)
            if let c = consistency, let rate = c.rate {
                Text("Consistency: \(rate.formatted(.percent.precision(.fractionLength(0)))) — \(c.completed) completed, \(c.cancelled) cancelled, \(c.noShow) no-show")
                    .font(.subheadline)
            }
            Text("Weekly volume").font(.caption.bold())
            VolumeChart(weeks: weeks, height: 180)
            Text("Top exercises").font(.caption.bold())
            ForEach(Array(topExercises.prefix(8).enumerated()), id: \.offset) { _, item in
                HStack { Text(item.name); Spacer(); Text(item.detail).foregroundStyle(.secondary) }
                    .font(.subheadline)
            }
            Text("Generated \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(32)
        .frame(width: ReportExporter.pageSize.width, height: ReportExporter.pageSize.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

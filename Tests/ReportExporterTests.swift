import Foundation
import Testing
import UIKit
@testable import Rackside

private func samplePoints() -> [ProgressPoint] {
    [ProgressPoint(date: .now.addingTimeInterval(-86_400 * 7), topSetWeight: 185, est1RM: 215, totalReps: 10),
     ProgressPoint(date: .now, topSetWeight: 195, est1RM: 227, totalReps: 10)]
}

@Test @MainActor func renderWritesPdfAndPng() throws {
    let page = ExerciseReportPage(clientName: "Sam", exerciseName: "Back Squat",
                                  points: samplePoints(), personalBest: nil, unit: .lb)
    let files = try ReportExporter.render(page, baseName: "Sam — Back Squat Progress")
    defer { ReportExporter.removeReports() }

    let fm = FileManager.default
    #expect(fm.fileExists(atPath: files.pdf.path))
    #expect(fm.fileExists(atPath: files.png.path))
    #expect(files.pdf.lastPathComponent == "Sam — Back Squat Progress.pdf")
    let data = try Data(contentsOf: files.png)
    #expect(!data.isEmpty)
    #expect(UIImage(data: data) != nil)
}

@Test @MainActor func renderSweepsPreviousReportsAndSanitizesNames() throws {
    let page = ClientOverviewPage(clientName: "A/B:C", window: .all, consistency: nil, weeks: [], topExercises: [])
    let first = try ReportExporter.render(page, baseName: "first")
    let second = try ReportExporter.render(page, baseName: "A/B:C — Overview")
    defer { ReportExporter.removeReports() }

    #expect(!FileManager.default.fileExists(atPath: first.pdf.path))
    #expect(second.pdf.lastPathComponent == "A-B-C — Overview.pdf")
    #expect(second.png.lastPathComponent == "A-B-C — Overview.png")
}

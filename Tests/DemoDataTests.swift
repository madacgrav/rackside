import Foundation
import SwiftData
import Testing
@testable import Rackside

@MainActor
@Test func demoContainerIsPopulated() throws {
    let container = try DemoData.container()
    let ctx = ModelContext(container)
    #expect(try ctx.fetchCount(FetchDescriptor<Client>()) == 6)
    #expect(try ctx.fetchCount(FetchDescriptor<Exercise>()) == 12)
    #expect(try ctx.fetchCount(FetchDescriptor<Workout>()) == 4)
    let completed = try ctx.fetch(FetchDescriptor<Session>()).filter { $0.status == .completed }
    #expect(completed.count >= 20)
    #expect(try ctx.fetchCount(FetchDescriptor<SetRecord>()) >= 100)
    #expect(try ctx.fetchCount(FetchDescriptor<Assessment>()) == 2)
}

@MainActor
@Test func demoTodaySessionIsScheduledWithLoggedSets() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let data = DemoData.dataset(now: now, calendar: .current)
    let today = try #require(data.todaySession)
    #expect(today.status == .scheduled)
    #expect(today.startAt > now)
    let instanceId = today.instances[0].id
    #expect(data.sets.filter { $0.workoutInstanceId == instanceId }.count == 2)
}

@MainActor
@Test func demoSquatLoadsRiseOverTime() {
    let data = DemoData.dataset(now: Date(timeIntervalSince1970: 1_800_000_000), calendar: .current)
    let squats = data.sets.filter { $0.exerciseId == DemoData.backSquat.id }.sorted { $0.performedAt < $1.performedAt }
    let first = squats.first?.weight ?? 0
    let last = squats.last?.weight ?? 0
    #expect(last > first)
}

@Test func parsesDemoLaunchArguments() {
    let launch = DemoLaunch(arguments: ["app", "-demoData", "-demoScreen", "report"])
    #expect(launch.enabled)
    #expect(launch.screen == .report)
    #expect(launch.screen?.tab == 1)
    #expect(DemoLaunch(arguments: ["app"]).enabled == false)
    #expect(DemoLaunch(arguments: ["app", "-demoData", "-demoScreen"]).screen == nil)
    #expect(DemoLaunch(arguments: ["app", "-demoData", "-demoScreen", "nope"]).screen == nil)
}

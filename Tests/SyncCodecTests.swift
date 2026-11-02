import Foundation
import Testing
@testable import TrainMe

private func snapshot(timer: ActiveTimer?) -> TimerSnapshot {
    TimerSnapshot(timer: timer, upNext: nil, defaultRest: 90, quickPicks: [60, 90, 120],
                  sentAt: Date(timeIntervalSince1970: 1_800_000_000))
}

@Test func snapshotRoundTrips() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let timer = ActiveTimer(id: UUID(), kind: .rest, startedAt: start, endAt: start.addingTimeInterval(90))
    for snap in [snapshot(timer: timer), snapshot(timer: nil)] {
        let dict = try SyncCodec.encode(snap, kind: "snapshot")
        #expect(SyncCodec.decode(TimerSnapshot.self, from: dict, kind: "snapshot") == snap)
    }
}

@Test func wrongKindReturnsNil() throws {
    let dict = try SyncCodec.encode(snapshot(timer: nil), kind: "snapshot")
    #expect(SyncCodec.decode(TimerSnapshot.self, from: dict, kind: "command") == nil)
}

@Test func missingPayloadReturnsNil() {
    #expect(SyncCodec.decode(TimerSnapshot.self, from: ["kind": "snapshot"], kind: "snapshot") == nil)
}

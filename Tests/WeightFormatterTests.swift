import Testing
@testable import Rackside

@Test func formatsLbAndKg() {
    #expect(WeightFormatter.string(185, unit: .lb) == "185 lb")
    #expect(WeightFormatter.string(82.5, unit: .kg) == "82.5 kg")
}

@Test func nonWeightUnitsFallBackToLb() {
    #expect(WeightFormatter.label(.mi) == "lb")
    #expect(WeightFormatter.label(.sec) == "lb")
}

@Test func stepIncrements() {
    #expect(WeightFormatter.stepIncrement(for: .lb) == 5)
    #expect(WeightFormatter.stepIncrement(for: .kg) == 2.5)
}

@Test func volumeStringOmitsZeroUnits() {
    #expect(WeightFormatter.volumeString(VolumeTotals(byUnit: [.lb: 12450])) == "12,450 lb")
    #expect(WeightFormatter.volumeString(VolumeTotals(byUnit: [.lb: 0, .kg: 300])) == "300 kg")
    #expect(WeightFormatter.volumeString(VolumeTotals()) == "—")
}

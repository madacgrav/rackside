import SwiftUI
import Testing
import UIKit
@testable import TrainMe

private func named(_ name: String, _ style: UIUserInterfaceStyle) throws -> UIColor {
    let bundle = Bundle(identifier: "com.madacgrav.trainme") ?? .main
    let color = try #require(UIColor(named: name, in: bundle, compatibleWith: nil))
    return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
}

private func luminance(_ c: UIColor) -> Double {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

func contrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

@Test(arguments: ["Success", "Warning", "Danger", "PersonalBest"])
func textRolesAreReadableOnSurfaces(name: String) throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
        for surface in ["Surface", "SurfaceRaised"] {
            #expect(contrastRatio(try named(name, style), try named(surface, style)) >= 4.5,
                    "\(name) on \(surface) in \(style == .light ? "light" : "dark")")
        }
    }
}

@Test func accentIsReadableAsTintAndAsButtonFill() throws {
    for style in [UIUserInterfaceStyle.light, .dark] {
        let accent = try named("AccentColor", style)
        #expect(contrastRatio(accent, try named("Surface", style)) >= 3)
        #expect(contrastRatio(.white, accent) >= 3)
    }
}

@Test(arguments: Theme.Area.allCases)
func areaFillsCarryWhiteSymbols(area: Theme.Area) throws {
    #expect(contrastRatio(.white, try named(area.colorName, .dark)) >= 4.4)
    #expect(!area.systemImage.isEmpty)
}

@Test func areaColorsAreDistinct() {
    #expect(Set(Theme.Area.allCases.map(\.colorName)).count == Theme.Area.allCases.count)
}

@Test func avatarIndexIsStableAndSpread() {
    let keys = (0..<50).map { String(format: "00000000-0000-0000-0000-%012d", $0) }
    #expect(keys.map(Theme.avatarIndex) == keys.map(Theme.avatarIndex))
    #expect(Set(keys.map(Theme.avatarIndex)).count == Theme.Fills.all.count)
}

@Test @MainActor func avatarInitials() {
    #expect(ClientAvatar.initials("Priya Shah") == "PS")
    #expect(ClientAvatar.initials("Jordan") == "J")
    #expect(ClientAvatar.initials("Mary Ann  Lee") == "ML")
    #expect(ClientAvatar.initials("") == "?")
}

import SwiftUI

/// Single source of visual identity. Views reference roles, never raw colors.
enum Theme {
    enum Colors {
        static let accent = Color("AccentColor")
        static let brandPrimary = Color("BrandPrimary")
        static let brandSecondary = Color("BrandSecondary")
        static let success = Color("Success")
        static let warning = Color("Warning")
        static let danger = Color("Danger")
        static let personalBest = Color("PersonalBest")
        static let surface = Color("Surface")
        static let surfaceRaised = Color("SurfaceRaised")
        static let brandTertiary = Color("BrandTertiary")
    }

    /// Fixed (non-adaptive) fills that always sit under a white symbol or initials.
    enum Fills {
        static let coral = Color("FillCoral")
        static let magenta = Color("FillMagenta")
        static let violet = Color("FillViolet")
        static let teal = Color("FillTeal")
        static let gray = Color("FillGray")
        static let all: [Color] = [coral, magenta, violet, teal]
    }

    enum Gradients {
        /// Sunset brand gradient; safe under white in both appearances.
        static let brand = LinearGradient(
            colors: [Fills.coral, Fills.magenta, Fills.violet],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// One color + symbol per app area, used by empty states and badges.
    enum Area: CaseIterable {
        case schedule, clients, workouts, exercises, settings

        var color: Color {
            switch self {
            case .schedule: Fills.coral
            case .clients: Fills.magenta
            case .workouts: Fills.violet
            case .exercises: Fills.teal
            case .settings: Fills.gray
            }
        }

        /// Asset name behind `color`, for tests.
        var colorName: String {
            switch self {
            case .schedule: "FillCoral"
            case .clients: "FillMagenta"
            case .workouts: "FillViolet"
            case .exercises: "FillTeal"
            case .settings: "FillGray"
            }
        }

        /// Matches the tab symbols in RootView.
        var systemImage: String {
            switch self {
            case .schedule: "calendar"
            case .clients: "person.2.fill"
            case .workouts: "list.clipboard.fill"
            case .exercises: "dumbbell.fill"
            case .settings: "gearshape.fill"
            }
        }
    }

    /// Stable palette pick for an identifier (FNV-1a; never `hashValue`, which is seeded per launch).
    static func avatarIndex(for key: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return Int(hash % UInt64(Fills.all.count))
    }
    static func avatarColor(for key: String) -> Color { Fills.all[avatarIndex(for: key)] }

    enum Fonts {
        /// Headline-weight rounded display text for row titles and hero copy.
        static func display(_ style: Font.TextStyle = .headline) -> Font {
            .system(style, design: .rounded, weight: .semibold)
        }
        /// Tabular digits for set tables and stat tiles.
        static let numeric: Font = .system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
    }

    enum Radius {
        static let row: CGFloat = 12
    }
}

extension View {
    /// Applies the themed surface to a List/Form and hides the system background.
    func themedScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.Colors.surface)
    }

    /// Applies the raised surface to every row in a Section.
    func themedRows() -> some View {
        self.listRowBackground(Theme.Colors.surfaceRaised)
    }
}

# Research Questions

## Context
Focus on the Icon Composer bundle at `Sources/AppIcon.icon/`, the color catalog at `Sources/Assets.xcassets/`, `Sources/Support/Theme.swift` and the shared components in `Sources/Features/Components/`, the SF Symbol usage across `Sources/` and `Watch/`, the screenshot pipeline in `scripts/screenshots.sh`, and the prior design records under `thoughts/qrspi/2026-10-26-*`.

## Questions
1. How is the app icon built in `Sources/AppIcon.icon/icon.json`: which layers exist, what do the SVG assets contain (shapes, colors, gradients), and how do the default, dark, clear, and tinted variants derive from those layers?
2. What color assets are defined in `Sources/Assets.xcassets/`, what light and dark values does each hold, and how does `Theme.swift` expose them to views (named colors, gradients, semantic roles)?
3. Where are theme colors and gradients actually consumed in iOS views, and which screens or components (hero, empty states, chips, badges, timer bar) carry the most visual weight?
4. How does the watchOS target source its colors and icons, given it has no asset catalog of its own, and what visual elements appear in the watch views?
5. What SF Symbols are used across the iOS and watch views, with which rendering modes, weights, and color treatments, and are any symbols reused with different meanings?
6. How does `scripts/screenshots.sh` produce the App Store and guide screenshots, what demo data drives them, and which docs or checks (metadata, guide labels, changelog) reference those images or the icon?
7. What decisions and constraints did the 2026-10-26 UI refresh and app icon design records settle, and what verification steps did they use for icon variants and theme changes?

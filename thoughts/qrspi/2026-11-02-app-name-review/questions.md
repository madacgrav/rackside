# Research Questions

## Context
Focus on the iOS app target and watch target configuration (`project.yml`, `Sources/Info.plist`, entitlements), user-facing strings in `Sources/` and `Watch/`, persistence and archive code, the docs site under `docs/` (including `docs/app-store/`), the scripts in `scripts/`, and the product documents (`PRD.md`, `README.md`). One question also needs public web sources outside the repo.

## Questions
1. Where does the string "TrainMe" (and the lowercase "trainme") appear across the app and watch targets, and for each occurrence, is it user-visible (display name, permission prompts, alerts, report titles, notification text, exported file names) or internal (type names, scheme and target names, logger subsystem, CI)?
2. Which runtime behaviours depend on the bundle identifiers `com.madacgrav.trainme` and `com.madacgrav.trainme.watchkitapp`: where is the SwiftData store located, how does the watch app pair with its companion, what do entitlements, keychain or app-group settings reference, and what happens to existing on-device data when the bundle identifier of an installed app changes?
3. How do the export archive format and the import path identify a valid file: does the archive body, its file name, or the import validation reference the product name, and how are older archives (v1, v2) recognised?
4. How is the product name used in the docs site (`docs/`, `_config.yml`, the GitHub Pages URL), the App Store metadata, screenshots and review sample in `docs/app-store/`, `CHANGELOG.md`, and which scripts (`check-metadata-lengths.sh`, `check-docs-links.sh`, `check-guide-labels.sh`, `screenshots.sh`, `sync-changelog.sh`) hard-code it or enforce length limits on it?
5. Do the app icon (`Sources/AppIcon.icon`), asset catalogs, screenshots or any rendered images contain the product name as text or a wordmark?
6. What do `PRD.md` and `README.md` say about the product's audience, core features, platforms, price and positioning?
7. Which existing apps (Apple App Store, Google Play), web products, companies and registered or pending trademarks (for example USPTO and EUIPO records) use the name "TrainMe" or close variants such as "Train Me", "TrainMe App" or "Trainme.co", and in which categories and countries?

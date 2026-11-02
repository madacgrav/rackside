# App Store submission checklist — Rackside 1.0.0

Steps only the owner can do. Work through them in order.

## Decisions

- [ ] **Licence.** Rackside is GPL v3. Apple's App Store terms add usage restrictions that are widely considered incompatible with GPL distribution, which matters most if other people contribute code. Choose one: keep GPL v3 and accept the risk (you own all the code), dual-license (GPL for the source, a separate licence for the App Store build), or relicense (e.g. MIT, or all rights reserved). Update `LICENSE`, the README and Settings › About to match.
- [ ] **Copyright name.** Replace `2026 Adam (madacgrav)` in `metadata.md` with your legal or business name.

## Publish the website

- [ ] Merge this branch to `main`.
- [ ] GitHub › repo **Settings › General** › rename `trainme` to `rackside`, then locally: `git remote set-url origin https://github.com/madacgrav/rackside.git`.
- [ ] GitHub › repo **Settings › Pages** › *Deploy from a branch* › branch `main`, folder `/docs` › Save.
- [ ] After a few minutes, check these load: https://madacgrav.github.io/rackside/, `/guide/`, `/privacy/`, `/support/`, `/changelog/`.
- [ ] Push the version tags: `git push origin v0.1.0 v0.2.0 v0.3.0 v0.4.0 v0.5.0 v0.6.0` (so the changelog's compare links work).

## App Store Connect setup

- [ ] **Agreements, Tax and Banking:** accept the **Paid Apps Agreement** and complete tax forms and bank details. A paid app can't go on sale until this is active (it can take a few days).
- [ ] **Apps › + › New App:** platform iOS, name *Rackside*, primary language English (U.S.), bundle ID `com.madacgrav.trainme`, SKU `rackside-ios`.
- [ ] **Pricing and Availability:** USD 0.99, all territories.
- [ ] **App Information:** subtitle, categories (Health & Fitness / Business), age rating questionnaire, copyright — from `metadata.md`.
- [ ] **App Privacy:** Data Not Collected. Privacy Policy URL from `metadata.md`.

## Build and upload

- [ ] Confirm `project.yml` has the version you're releasing (`MARKETING_VERSION: "1.0.0"`) and a build number higher than any previous upload (`CURRENT_PROJECT_VERSION`).
- [ ] `xcodegen generate`, open `Rackside.xcodeproj`, choose **Any iOS Device**, then **Product › Archive** (Release).
- [ ] In the Organizer: **Validate App**, then **Distribute App › App Store Connect**.

## Version page

- [ ] Description, promotional text, keywords, support and marketing URLs — from `metadata.md`.
- [ ] Screenshots: the six iPhone 6.9" images and the two Apple Watch images from `screenshots/`, in the order listed in `metadata.md`.
- [ ] What's New — from `whats-new/1.0.0.md`.
- [ ] Select the uploaded build. Export compliance: no non-exempt encryption (already declared in the build).
- [ ] **App Review Information:** contact details, *Sign-in required* off, review notes from `metadata.md`, and attach `Rackside Review Sample.json`.
- [ ] **Submit for Review.**

## After approval

- [ ] Tag the release commit: `git tag -a v1.0.0 -m "1.0.0" && git push origin v1.0.0`.
- [ ] In `CHANGELOG.md`, rename `[Unreleased] — 1.0.0` to `[1.0.0] — <release date>`, add `[1.0.0]` and update `[Unreleased]` compare links, then run `scripts/sync-changelog.sh`.

## Every later release

- [ ] Bump `MARKETING_VERSION` (semantic versioning: 1.0.1 fixes, 1.1.0 features) and increase `CURRENT_PROJECT_VERSION` in `project.yml`.
- [ ] Add the changes under `[Unreleased]` in `CHANGELOG.md` and write `whats-new/<version>.md`; run `scripts/sync-changelog.sh`.
- [ ] If the UI changed, run `scripts/screenshots.sh` and upload the new images.
- [ ] Run `scripts/check-metadata-lengths.sh`, `scripts/check-docs-links.sh` and `scripts/check-guide-labels.sh`.

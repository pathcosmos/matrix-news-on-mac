# Matrix News

Matrix-style Korean news viewer for Apple devices. The app shows one focused MBC news item at a time, types the title and summary character by character, pauses briefly, then advances to the next story. The background uses Korean Matrix rain while the foreground news remains readable.

## What is implemented

- SwiftUI app code for macOS, iPhone, iPad, and Apple TV.
- Testable `MatrixNewsCore` Swift package with models, RSS/MBC JSON parsing, URL normalization, deduplication, settings, and local personalization.
- `matrix-news-fetcher` command that reads configured feeds and writes `Data/manifest.json`, `Data/latest.json`, and `Data/sources.json`.
- GitHub Actions workflow that refreshes the data repository every 10 minutes.
- Default app data loading from `https://raw.githubusercontent.com/pathcosmos/matrix-news-on-mac/main/Data/`, with `NEWS_DATA_BASE_URL` still available as an override.
- iCloud KVS-backed settings/preference persistence in the app.

## Run locally

```bash
swift test
swift run matrix-news
```

To refresh news data manually:

```bash
swift run matrix-news-fetcher --sources Config/news-sources.json --output Data --license-scope test-only --limit 50 --minimum-items 50
```

## Xcode app

Open `MatrixNews.xcodeproj` and build the `MatrixNews` scheme. The project contains one app target with shared SwiftUI code for macOS, iOS, iPadOS, and tvOS.

For iCloud sync and device/App Store builds, set your Apple Developer Team in the target Signing & Capabilities settings. `MatrixNews.entitlements` already includes the iCloud key-value store entitlement placeholder.

## News source policy

The included MBC feed endpoint is marked `test-only`. It is suitable for development and private testing only until you secure the rights needed for a public commercial app. For a commercial release, set only licensed sources to `"licenseStatus" : "licensed"` and run the fetcher with:

```bash
swift run matrix-news-fetcher --sources Config/news-sources.json --output Data --license-scope licensed
```

# Hoopoe

A small, local-only time tracker that lives in the macOS menu bar.

- **Menu bar first.** Start, stop, resume and switch tasks from the popover. The elapsed time can be shown next to the icon and keeps counting while every window is closed.
- **Dashboard.** Totals for a day, week or month, a chart, and a per-task breakdown.
- **Calendar.** Hours per day for a month. Click a day to add, edit or delete time by hand.
- **Stops when you leave.** The timer stops on screen lock, sleep and lid close, and can resume on unlock.
- **Updates itself.** Checks GitHub Releases once a day (can be turned off) and installs a new version in place, after verifying it is signed by the same developer.
- **Light.** Native Swift and SwiftUI with no third-party dependencies. Data is a single SQLite file in `~/Library/Application Support/Hoopoe/`.

Requires macOS 14 or later.

## Develop

Full Xcode is not required; the Command Line Tools are enough.

```sh
swift run Hoopoe --demo     # run with throwaway sample data
swift run Hoopoe            # run against your real data
./scripts/test.sh           # unit tests
./scripts/build-app.sh      # build dist/Hoopoe.app (ad-hoc signed)
./scripts/package.sh        # zip and DMG from dist/Hoopoe.app
```

| Path | Contents |
|---|---|
| `Sources/HoopoeCore` | Storage, timer state machine and statistics. No UI; covered by the tests. |
| `Sources/Hoopoe` | The SwiftUI app: menu bar item, dashboard, lock and sleep handling. |
| `scripts/` | Test runner, app bundle and DMG builder, icon generator. |

## Release

Pushing a tag such as `v1.0.0` runs `.github/workflows/release.yml`, which tests, builds a universal app, signs and notarizes it, and attaches a DMG (for new installs) and a zip (for the in-app updater) to a GitHub Release.

Signing needs these repository secrets. Without them the release is still published, but ad-hoc signed and not notarized, and such builds cannot update themselves in place.

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE` | Your "Developer ID Application" certificate with its private key, exported from Keychain Access as `.p12`, then base64 encoded (`base64 -i cert.p12`) |
| `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |
| `APPLE_SIGNING_IDENTITY` | Optional. The certificate name, e.g. `Developer ID Application: Your Name (TEAMID)`. Defaults to the Developer ID certificate in the keychain. |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | Your 10-character team ID |
| `APPLE_APP_PASSWORD` | An app-specific password from account.apple.com |

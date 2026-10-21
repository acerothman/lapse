# Contributing

Lapse is a folder of Swift sources built with `swiftc` through `build.sh`. There is no Xcode project.

## Build

You need macOS 13 or later and the Command Line Tools (`xcode-select --install`). Full Xcode adds one step: the App Intents metadata that Shortcuts actions and the Focus filter need. Without it the app still builds, minus those.

```bash
./build.sh --no-open
```

That writes `build/Lapse.app` and does not copy it to `~/Applications` or launch it. Run `./build.sh` with no arguments to install and open.

macOS only connects Shortcuts actions and Focus filters to apps signed by a developer team. An ad hoc build has the metadata but macOS ignores it. The `lapse://` links in `Sources/Links.swift` work either way.

## Test

```bash
scripts/test.sh
```

Plain checks for feed rules, limits, focus hours, pause screens, links and reading data files from older versions. They run against a throwaway data folder.

## Screenshots

```bash
scripts/screenshots.sh
```

Launches the real app once per scene with made-up data (`Sources/Scenes.swift`) and writes the images in `docs/`. Your own data isn't touched. Your terminal needs Screen Recording access.

## Changes

- Match the style of the file you are editing. Shared colors, type and small components are in `Sources/Theme.swift`.
- Keep the usage log on the Mac. Do not add a network call other than the icon fetch for a site someone added, and the update check against GitHub releases.
- The menu bar label, the popover, and Settings are the product. Say what changed on screen in the pull request, with a screenshot.
- Feed rules live in `Sources/FeedRules.swift`. Add a check to `Tests/LapseTests.swift` for any rule you add or change.
- The welcome window is `Sources/Onboarding.swift`. Its wording is approved. Don't rewrite those strings in passing.
- No em dashes in the app, the README or release notes.

## Pull requests

Open a pull request against `main` and fill in the template. CI on macOS 14 runs `scripts/test.sh` and `./build.sh --no-open`, and uploads `Lapse-<version>.zip`.

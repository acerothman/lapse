# Contributing

Lapse is a folder of Swift sources built with `swiftc` through `build.sh`. There is no Xcode project.

## Build

You need macOS 13 or later and the Command Line Tools (`xcode-select --install`).

```bash
./build.sh --no-open
```

That writes `build/Lapse.app` and does not copy it to `~/Applications` or launch it. Run `./build.sh` with no arguments to install and open.

## Changes

- Match the style of the file you are editing.
- Keep the usage log on the Mac. Do not add a network call other than the icon fetch for a site someone added, and the update check against GitHub releases.
- The menu bar label, the popover, and Settings are the product. Say what changed on screen in the pull request.
- The welcome window is `Sources/Onboarding.swift`. It is the three-step lock-in intro. Don't rewrite those strings in passing.

## Pull requests

Open a pull request against `main` and fill in the template. CI on macOS 14 runs `./build.sh --no-open` and uploads a zip named from the version in `Info.plist` (`Lapse-1.2.0.zip` for this version).

<p align="center">
  <img src="docs/lapse-icon.png" width="112" alt="Lapse icon">
</p>

<h1 align="center">Lapse</h1>

<p align="center">Count time on the sites you choose.</p>

<p align="center">
  <img alt="Requires macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-black">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <a href="https://github.com/acerothman/lapse/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/acerothman/lapse"></a>
  <a href="https://github.com/acerothman/lapse/actions/workflows/build.yml"><img alt="Build status" src="https://github.com/acerothman/lapse/actions/workflows/build.yml/badge.svg"></a>
</p>

<p align="center">
  <img src="docs/lapse-desktop.png" width="880" alt="Lapse on the desktop, with today's total and time per site">
</p>

## Why

Screen Time is a long report. Lapse watches a short list of sites, keeps the total in the menu bar, and tells you when the day is used up. The record stays on your Mac.

## Features

- A welcome window the first time Lapse opens. Pick sites and apps, set the daily limit, allow browser access and notifications, and leave open at login on. Settings has Welcome to Lapse if you want it again.
- A popover with today's total, time and visits per site and app, and a chart of the last seven days.
- A menu bar ring that fills clockwise through the day. It follows the overall limit. Past the limit it becomes a red dot.
- On a tracked site, the site's logo and a timer for the current visit (4:12, or 1:02:09 past an hour). On a tracked app, the app's own icon. Past the limit, the icon and the timer turn red.
- An icon for sites you add, fetched from the site and cached locally. App icons come from the app on your Mac.
- A daily limit (1 h 30 min to start, from 15 min to 8 h) and a notification at 80% and at the limit, once each per day. Each site and app can have its own limit too.
- A calm screen when a site or app passes its limit. Snooze it for 5 or 15 minutes, or turn it off for the day. Settings can turn that screen off.
- Focus hours on the days and times you choose. A stricter limit during that window, or a block for the whole window.
- Check for updates from the menu bar or the popover. Lapse also checks on its own.
- Open at login.

It starts with X, Instagram, TikTok, YouTube, and Reddit turned on. Facebook, Threads, LinkedIn, Snapchat, and Twitch are in the list as well. Add any other domain, or right-click a site to remove it. Built-in logos are from Simple Icons (CC0).

Apps start off. X, Discord, Slack, and Messages are listed. Turn one on, or add any other app. Time counts while that app is in front.

## Screenshots

<p align="center">
  <img src="docs/lapse-popover.png" width="340" alt="Lapse popover with today's total, sites, and the week">
</p>

<p align="center">
  <img src="docs/lapse-onboarding.png" width="760" alt="Welcome window for choosing which sites to track">
</p>

The menu bar shows one thing at a time. A ring while you are not on a tracked site. The site's logo and a timer for this visit while you are.

<p align="center">
  <img src="docs/lapse-menubar-ring.png" width="720" alt="Menu bar with the daily progress ring">
</p>

<p align="center">
  <img src="docs/lapse-menubar-timer.png" width="720" alt="Menu bar with the X logo and a session timer">
</p>

## Download

<p align="center">
  <a href="https://github.com/acerothman/lapse/releases/latest"><img alt="Download" src="https://img.shields.io/static/v1?label=&message=Download&color=111111&style=for-the-badge"></a>
</p>

Unzip `Lapse-1.1.0.zip` and move `Lapse.app` to your Applications folder. When a newer version is out, Lapse says so in the popover. Download stays on the releases page.

The build is ad hoc signed, not notarized, so a normal double-click is blocked. Right-click the app, choose **Open**, then **Open** again. Or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /path/to/Lapse.app
```

## Privacy

Usage stays in `~/Library/Application Support/Lapse/data.json`: settings, seconds per site or app per day, and visit counts. Days older than 90 are dropped. Icons for sites you add are PNGs in the `icons` folder next to that file. App icons are read from the apps themselves and are not saved. Delete the `Lapse` folder to reset.

Lapse has no account and no analytics. It uses the network for two things: an icon for a site you added, and a check for a new version. The icon comes from the site's own `apple-touch-icon` and `icon` links, then `/favicon.ico`, then Google's favicon service if nothing else decodes. The update check reads the latest release from GitHub, on launch and once a day. Removing a site deletes its cached icon.

## Permissions

- **Automation.** Allow, in the welcome window, asks macOS to let Lapse control the browser in front (Safari, if none is open). That is how the active tab address is read. If you deny it: System Settings → Privacy & Security → Automation → Lapse.
- **Notifications.** Allow in the welcome window. They are only the 80% and limit alerts. The same switch is in Settings.
- **Open at login.** On in the welcome window, and a toggle in Settings. macOS may ask you to approve the login item.

## How tracking works

About every two seconds, Lapse checks the frontmost app. While a tracked site or app is in front it checks about once a second, so the visit timer stays current. A tracked app counts by its bundle id. In a supported browser it reads the active tab's address with AppleScript.

Time counts when that host matches an enabled site. Subdomains count: `old.reddit.com` counts for `reddit.com`.

Counting pauses after the idle threshold (60 seconds of no keyboard or mouse, by default) and while the Mac or the display is asleep. A visit shown in the menu bar ends when you leave the site for more than 30 seconds, or when you go idle.

## Browsers

| Browser | Tracked |
| --- | --- |
| Safari | Yes |
| Chrome | Yes |
| Arc | Yes |
| Brave | Yes |
| Edge | Yes |
| Vivaldi | Yes |
| Firefox | No |

Firefox does not expose the active tab to other apps, so Lapse cannot count it. Safari Technology Preview is tracked the same way as Safari.

## Build from source

macOS 13 or later, and the Command Line Tools (`xcode-select --install`). Xcode is not required.

```bash
git clone https://github.com/acerothman/lapse.git
cd lapse
./build.sh
```

`./build.sh` compiles with `swiftc`, draws the app icon, ad hoc signs the bundle, copies it to `~/Applications/Lapse.app`, and opens it.

```bash
./build.sh --no-open
```

`--no-open` stops after `build/Lapse.app`. It does not install into `~/Applications` and it does not launch the app. CI uses this flag.

## Roadmap

Not in this version:

- A notarized download, so the Gatekeeper step above can go away.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The license is [MIT](LICENSE).

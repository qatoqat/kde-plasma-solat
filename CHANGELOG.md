# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [0.4.4] - 2026-11-13

### Changed
- App icon is now a plain white {8/2} star on a flat, sharp-cornered square in the Breeze Dark
  window colour (`#202326`), shipped as PNGs (16 to 512 px) instead of an SVG with a gradient.

## [0.4.3] - 2026-11-13

### Changed
- Prayer rows in the widget behave like buttons: holding the left mouse button fills the row's
  background with the highlight colour.

## [0.4.2] - 2026-11-13

### Added
- Hovering a non-current prayer row in the widget draws a highlight border.

## [0.4.1] - 2026-11-13

### Fixed
- The widget failed to load in 0.4.0 because the footer used a property that does not exist in
  current Plasma (`PlasmoidHeading.location`); it now uses `position: ToolBar.Footer`.
- A property in the settings page named `states` overrode a built-in `Item` property.

### Added
- `scripts/smoke.sh`: restarts the shell in a live Plasma session and fails if the widget does not
  load.

## [0.4.0] - 2026-11-13

### Added
- Date in the widget header with left/right arrows to browse the cached days (yesterday to about
  60 days ahead). Click the date to return to today. Past days can be ticked.
- Footer with the countdown, the last update time and a resync button.
- Lock screen shows the last update time and a refresh button. The locked session has no network,
  so the button leaves a request that the widget acts on within about 15 seconds.
- Headless behaviour tests (`widget/tests`) that load the real `main.qml` against stub Plasma
  modules, plus a GitHub Actions workflow that runs them.

## [0.3.4] - 2026-11-13

### Fixed
- The `.plasmoid` archives no longer contain the test files.

## [0.3.3] - 2026-11-13

### Added
- Minimal {8/2} star icon.

## [0.3.2] - 2026-11-13

### Fixed
- Changing the zone (or other settings) in the widget's settings dialog now takes effect
  immediately. Config changes were not reliably noticed, so the new zone was not downloaded until
  the next restart.

## [0.3.1] - 2026-11-13

### Fixed
- Settings page has proper padding, and the zone picker is split into State and Zone so the
  dropdown no longer fills the whole dialog.

## [0.3.0] - 2026-11-13

### Changed
- **The widget is now self-contained.** It downloads the e-solat timetable itself (falling back to
  `curl` if Qt's network stack stalls), tracks check-offs, sends reminders and feeds the lock
  screen. The `solat` command, the systemd services and the Rust binary are gone, and the Arch
  package is architecture independent.
- Zone, language, 12-hour, reminder and lock screen options moved into the widget's own settings.
- Settings from the old lock-screen config are imported on first start.

## Earlier releases

- **0.2.x**: check marks reset at Imsak instead of midnight; panel widget; warnings 10 and 5
  minutes before the next prayer; last update time, settings, website and keep-open buttons;
  rename from `solat-lock` to `kde-plasma-solat`.
- **0.1.0**: JAKIM prayer times with check-offs and reminders on the KDE Plasma lock screen.

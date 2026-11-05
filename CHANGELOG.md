# Changelog

Notable changes to FNB58 Monitor. Add new changes under **Unreleased**. To release, rename that heading to the new version and date, add a fresh **Unreleased** heading, merge, then push a tag such as `v0.1.2`. The release takes its notes from this file, and fails if the version has no entry here.

## [Unreleased]

### Added

- Known issues section and this changelog in the project documentation.

### Changed

- Release notes now come from this changelog.

## [0.1.1] - 2026-11-05

A design update, with a floating sidebar and a cleaner window.

### Added

- Floating Liquid Glass sidebar: an inset panel beside the content, using the system's glass material on macOS 26 and later.
- Sidebar button and Control-Command-S to hide or show the sidebar.
- Bluetooth link logging, to help diagnose connection problems. It records connection events and command bytes, and stays on your Mac.

### Changed

- Record CSV is now a separate glass button in the toolbar, with connection status as plain text beside it.
- Cards use a quiet fill instead of outlines, and charts no longer sit in nested boxes.
- Text and dividers use system styles instead of fixed colours.
- Empty background areas can now also drag the window.
- The "Looking for your tester" message now explains that the tester only accepts one connection at a time.

### Removed

- The custom window colour and the hard line under the toolbar.

### Known issues

- The sidebar is custom, because the native sidebar stays flush with the window on macOS 27. It can't be resized by dragging its edge.
- Dragging the window and scrolling under the toolbar haven't been confirmed since the redesign.
- Rarely, the app may connect but receive no data. Quit and reopen it. This was seen once, in v0.1.0, and hasn't been reproduced.

## [0.1.0] - 2026-11-05

The first release: a native Mac app for the FNB58 over Bluetooth.

### Added

- Live voltage, current, power, D+, D−, temperature, and load resistance.
- History charts with ranges from 30 seconds to the full session.
- CSV recording and raw packet log export.
- Session energy and charge totals, compared with what the tester counted.
- All stored groups at a glance, and a selector to switch group from the Mac.
- Detected protocol names, trigger status, charger activity, voltage steps, and tester restarts.
- Packet inspector with decoded and raw frames.
- Command console that adds the length and checksum, and asks you to confirm before sending.
- Automatic reconnect, and a message when the app is waiting for Bluetooth access.
- Auto, Light, and Dark appearance, with Liquid Glass controls on macOS 26 and later.
- Universal and Apple Silicon DMGs.

### Known issues

- Rarely, the app may connect but receive no data. Quit and reopen it.

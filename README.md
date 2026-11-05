# FNB58 Monitor

A native macOS app for the FNIRSI FNB58 USB tester, which has no official Mac software. It connects over Bluetooth LE and needs no drivers or pairing.

This is an independent project, not affiliated with or endorsed by FNIRSI.

## Features

- **Live readings:** voltage, current, power, D+, D−, temperature, and load resistance
- **History charts:** voltage, current, power, data lines, and temperature, with ranges from 30 seconds to the full session
- **Recording:** stream every sample to a CSV file, or export a raw packet log
- **Session totals:** energy and charge, compared with what the tester counted
- **Stored groups:** read all the tester's groups at once, and switch the selected group from the Mac
- **Charger activity:** detected protocols, voltage steps up to the tester's 28 V range, and tester restarts
- **Packet inspector:** the latest decoded and raw frame of each type, with checksum counts
- **Command console:** send a raw command, with the length and checksum added for you
- **Appearance:** Auto, Light, and Dark, with Liquid Glass on macOS 26 and later

## Download

Tagged versions are published on the [Releases page](https://github.com/bucknova/FNB58-Monitor/releases) in two forms:

- **`FNB58-Monitor-AppleSilicon.dmg`:** smaller, for Macs with an M-series chip
- **`FNB58-Monitor-Universal.dmg`:** for both Apple Silicon and Intel Macs

Every push to `main` also builds both, available from that run's artifacts on the [Actions page](https://github.com/bucknova/FNB58-Monitor/actions) to anyone signed in to GitHub.

Open the DMG and drag the app to Applications. These builds are ad-hoc signed rather than signed with an Apple Developer ID, so macOS blocks them the first time. To open one, either:

- Try opening the app, then go to **System Settings > Privacy & Security** and choose **Open Anyway**.
- Or, if macOS says the app is damaged, remove the download flag in Terminal, but only for a copy you got from this repository:

```bash
xattr -dr com.apple.quarantine "/Applications/FNB58 Monitor.app"
```

When macOS asks for Bluetooth access, choose **Allow**, and turn on Bluetooth on your tester.

## Build from source

You need macOS 14 or later and the Xcode command line tools. Full Xcode isn't required. Liquid Glass needs a macOS 26 or later SDK.

```bash
git clone https://github.com/bucknova/FNB58-Monitor.git
```

```bash
cd FNB58-Monitor
```

```bash
./build-app.sh
```

This runs the protocol checks against recordings from a real tester, then creates a universal `dist/FNB58 Monitor.app` and both DMGs in `dist/`.

## Status

Tested on one FNB58 with firmware v1.15, on macOS 27.

| Area | Status |
|---|---|
| Live data, charts, and CSV recording | Tested on hardware |
| Listing groups, selecting a group, and trigger status | Tested on hardware |
| Automatic reconnect after a tester restart | Not yet tested in the app |
| Hover readouts, Reset session, and raw log export | Not yet tested on hardware |
| macOS 14 to 25 | Not tested |
| Intel Macs | Builds, not tested on an Intel Mac |
| Fast-charge trigger and release | Commands documented, available only through the console, untested |
| Clearing a stored group | Command documented, available only through the console, untested |
| Tester settings and other toolbox tools | No known remote command |
| USB connection | Planned |

Other FNIRSI models aren't supported. The app only connects to devices named `FNB58`.

## Safety

The command console sends what you type to your tester. Two commands need real care, and neither has been tested:

- **`86` triggers fast charge** and can raise VBUS on anything connected, up to 20 V or more. Connect only a charger when experimenting.
- **`89` clears a stored group** and can permanently erase its totals.

The app asks you to confirm before sending anything from the console, but you use it at your own risk.

## Protocol

[docs/PROTOCOL.md](docs/PROTOCOL.md) documents the Bluetooth frame format, packets, and commands, and marks which were observed on hardware.

The notes come from captured traffic and from studying FNIRSI's legacy Android Bluetooth app for interoperability. This repository contains no FNIRSI code or app files. The serial number in the test recordings was replaced with a placeholder.

## Credits

These projects helped with early protocol research. No code was copied from them.

- [OpenFNB58](https://github.com/yeckel/OpenFNB58)
- [FNB58_mqtt_forwarder](https://github.com/zhiyb/FNB58_mqtt_forwarder)
- [fnirsi-usb-power-data-logger](https://github.com/baryluk/fnirsi-usb-power-data-logger)
- [Article-Files](https://github.com/BoondockMark/Article-Files/tree/main/FNIRSI-FNB58)

## Licence

[MIT](LICENSE)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**rdzwx-go** is a hybrid Apache Cordova app for tracking radiosondes (weather balloons) via the rdz-ttgo-sonde firmware running on TTGO ESP32 hardware. The Cordova application lives at the **repo root** (`www/`, `config.xml`); the custom native plugin lives in `plugin-src/rdzwx-plugin/` and is installed from there as a `file:` dependency with plugin ID `rdzwx-plugin`.

Platforms: Android (primary, Kotlin), iOS (Objective-C, mostly ported), Electron (desktop testing, Node.js).

## Common Commands

```bash
# Initial setup
npm install
cordova prepare

# Makefile targets
make run          # cordova run android --device
make plugin       # Remove + re-add rdzwx-plugin (required after plugin changes)
make full         # plugin + run
make el           # Build for Electron
make release      # Signed release APK (needs decrypted my-release-key.jks)

# Direct Cordova
cordova build                  # Debug build (all installed platforms)
cordova build android
cordova build ios              # Requires macOS/Xcode
cordova run android --device
```

The Makefile hardcodes `ANDROID_HOME ?= /Users/hansr/Library/Android/sdk`; on other machines set it in the environment or `make ANDROID_HOME=/path/to/sdk ...`.

There is no unit test suite (`npm test` is a stub). Testing is done by deploying to a device/emulator, or against the simulator below.

### TTGO Simulator (test without hardware)

`ttgo_simulator.py` emulates a TTGO device: advertises `_jsonrdz._tcp` via mDNS, serves the JSON protocol over TCP (default port 12345), and replays balloon flights (built-in sample, or `--flight file.csv|file.json`, `--speed N`, `--loop`). Requires `pip install zeroconf`. See SIMULATOR.md.

## Critical Gotcha: Plugin Changes

`cordova build` does **not** pick up changes made in `plugin-src/rdzwx-plugin/` — plugin source is copied into `platforms/` at plugin-install time. After any native plugin change (Kotlin/ObjC/Electron/`plugin.xml`/`www/rdzwx.js`), reinstall the plugin first:

```bash
make plugin        # cordova plugin rm rdzwx-plugin && cordova plugin add plugin-src/rdzwx-plugin/ --link
```

## Architecture

### JS ↔ Native bridge

- `www/js/index.js` — entire frontend app (~1000 lines): Leaflet map, sonde markers, info box, landing prediction (Tawhiri via `RdzWx.fetchUrl`).
- `plugin-src/rdzwx-plugin/www/rdzwx.js` — plugin JS interface, exposed as global `RdzWx` with methods: `start`, `stop`, `closeconn`, `showmap`, `wgstoegm`, `gettile`, `selstorage`, `mdnsUpdateDiscovery`, `fetchUrl`.

### Data flow

1. `RdzWx.start(arg, callBack)` registers a long-lived native→JS callback (`callBack` in index.js).
2. Native side discovers the TTGO via mDNS (`_jsonrdz._tcp`) or manual IP:port, opens a TCP connection, and streams newline-delimited JSON.
3. Each message arrives in `callBack` → `update(obj)`. Messages with a `msgtype` field are status updates (`ttgostatus`, `gps`, `mdnsstatus`); anything else is sonde telemetry (id, lat/lon/alt, validPos/validId bitmasks, `res` result code).
4. GPS positions are posted back to the TTGO over the same socket. `periodicStatusCheck()` closes the connection after 10s of silence.

### Offline maps

Leaflet uses a custom tile layer that calls `RdzWx.gettile(x, y, z)`; the result's `tile` field is used directly as the `<img>` src. On Android, Mapsforge (JARs in `plugin-src/rdzwx-plugin/src/android/libs/`) renders tiles from user-selected `.map` files and returns `file://` PNG paths. On iOS, `OfflineTileCache.m` reads raster **MBTiles** files (sqlite, TMS row order) and returns base64 `data:` URIs (WKWebView blocks `file://` images); it overzooms up to 6 levels past the file's max zoom. The iOS map file is chosen via a `UIDocumentPickerViewController` (open-in-place, persisted as an `NSUserDefaults` bookmark) or dropped into the app folder via the Files app. `tools/make_test_mbtiles.py` generates a synthetic MBTiles for testing; see OFFLINE_MAPS_IOS.md.

### Native implementations

- **Android** (`src/android/`): `rdzwx.kt` (plugin entry point, TCP/JSON-RDZ handling, mDNS, GPS, tile serving) and `rdzwx-a.kt`; AIDL interface in `Result.aidl`, enabled via `build-extras.gradle` (AGP 8+ disables AIDL by default).
- **iOS** (`src/ios/`): one Objective-C class per concern — `RdzWx` (plugin entry), `JsonRdzHandler` (TCP), `GPSHandler` (Core Location), `MDNSHandler` (Bonjour), `WgsToEgm`, `OfflineTileCache` (stub).
- **Electron** (`src/electron/RdzWx.js`).

### Build hooks (files not in git are generated)

- `hooks/copy_version.js` (before_prepare): converts `version.json` → `www/version.js`, which sets `window.APP_VERSION`; the app compares it against the GitHub-hosted `version.json` to offer updates.
- `plugin-src/rdzwx-plugin/scripts/fetch-egm96.js` (before_plugin_install): downloads the EGM96 geoid grid `WW15MGH.DAC` (used for WGS84→EGM96 altitude conversion) into `src/android/assets/`.

## Build Requirements

- Java 17, Node.js, Cordova CLI, Android SDK API 35 / build-tools 35.0.0
- `config.xml`: minSdk 23, target/compileSdk 35, Kotlin 1.8.22 (avoids duplicate-class conflicts with cordova-android 14.x)
- iOS builds require macOS + Xcode; Xcode workspace is generated at `platforms/ios/rdzSonde.xcworkspace`

## Release Process

1. Update the version in `package.json`, `config.xml`, and `version.json`.
2. `make release` — builds a release APK (`--packageType=apk`), zipaligns, and signs with `my-release-key.jks` (stored gpg-encrypted as `my-release-key.jks.gpg`; decrypt first).
3. iOS sideloading is distributed via AltStore (`altstore-source.json`, see ALTSTORE.md).

## CI

GitHub Actions in `.github/workflows/` (documented in `.github/workflows/README.md` and CI_SETUP.md): `ci-full.yml` (security scan + Android + iOS builds on push/PR), `android-build.yml`, `ios-build.yml`, `security-and-quality.yml` (npm audit + code pattern checks, weekly), `release.yml`, `simulator-screenshots.yml`.

## iOS Port Status

Core features (TCP networking, GPS, mDNS discovery, coordinate conversion, plugin interface) are implemented and building. Offline maps are implemented via raster MBTiles (see OFFLINE_MAPS_IOS.md) rather than Mapsforge `.map` files; map themes (`selstorage("theme")`) are Android-only.

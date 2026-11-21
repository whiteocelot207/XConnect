# XConnect

[Bahasa Indonesia](README.id.md)

An iPhone app that shows a map, motorcycle data, music and photos on the TFT dash of the Yamaha NMAX / XMAX.
It talks to the dash over ExternalAccessory (iAP, `com.garmin.navilite.data`) and reads motorcycle data from the
CCU over Bluetooth LE. Unofficial and not affiliated with Yamaha.

Current version: **0.1.2** (see CHANGELOG.md).

## Features

- **Dash screens**: Map, Speedometer, Music and Photos. Switch with the handlebar buttons; the order and the start
  screen are configurable. Live previews on Home and in Settings.
- **Data Cards** on the Map screen: weather + greeting, phone battery, fuel left, fuel range, 12V battery, ODO,
  engine/air temperature, speed, RPM, clock, ignition, fault codes, volume, network, date, heading, altitude and raw
  CCU bytes. 1 large + 2/4 small, or 4 small cards.
- **Navigation**: search places, paste a Google Maps link, save Home / Office / favorites, up to 2 alternative routes,
  route preview map, navigation simulation, voice guidance (with music ducking and an optional volume booster).
- **Routing** with Valhalla (scooter profile: main roads, speed limit, hills, alleys, trails, ferries, tolls, shortest).
- **Offline maps**: save areas you often ride through. Day/night map style (automatic 18:00-06:00).
- **Motorcycle tab**: ODO (read from the CCU, not editable), battery, coolant, fuel estimate, maintenance items with history, trip history.
- **Warning colors** (Settings > Motorcycle and fuel): fuel range, 12V battery, engine temperature and phone battery
  turn amber/red at limits you set, on the dash Data Cards and the Bike tab.
- **Maintenance reminders**: a notification when an item is near its service distance and when it is overdue.
- **Update banner**: a floating banner at the top when a new version is on GitHub Releases.
- **Fuel estimate**: average consumption from the dash (CCU) when readable, else your own last 30 days, else a default.
- **Handlebar controls**: zoom, switch screen, music gestures (volume, next/previous, play/pause).
- **Backup and restore** of all settings, places, motorcycle data, maintenance, fuel and trips to a JSON file.
- **First-run setup**: welcome, language, motorcycle and permissions (location "Always", Bluetooth, music, notifications).
  Permissions can be checked and requested again in Settings > Permissions.
- **In-app updates** from GitHub Releases (opens SideStore, AltStore or LiveContainer with the latest IPA).

## Languages and themes

- **Language** (Settings > Appearance): English (default) and Bahasa Indonesia. The choice applies to the app UI,
  voice guidance (system voice for that language), navigation texts, texts drawn on the dash and the language code
  sent to the dash.
- **Color theme** (Settings > Appearance): Ocean, Forest, Sunset, Rose, Violet, Crimson, Teal, Graphite. Dark / light /
  follow phone is a separate setting.

### Translations

All texts live in `Sources/Resources/Translations.tsv` (tab separated):

| Column | Meaning |
| --- | --- |
| `key` | English text used in code as `tr("...")` |
| `en`, `id`, ... | one column per language; empty cell = English |

- `{0}`, `{1}` are placeholders for the values passed to `tr()`. In a cell `\n` is a new line.
- Rows starting with `@` are language data: `@name` (shown in the picker), `@locale`, `@voice` (speech voice),
  `@routing` (Valhalla language), `@decimal`, `@dashLang` (language code sent to the dash, empty = not sent).
- To add a language, add a column in the header and fill it in. No code change is needed.
- `@dashLang`: the language code sent to the dash: `0` = English, `11` = Indonesian (`15` = Vietnamese is also known).
  Settings > Experiments and log > Dash language lets you try another code manually.

## Install

1. Build the IPA (see below) or download `XConnect.ipa` from [Releases](../../releases).
2. First install with Sideloadly (or SideStore / AltStore / LiveContainer). Bundle ID: `id.xconnect.app`.
3. Later updates: Settings > About > Check for updates. Add the update source once (button "Add source to ...").

Requires iOS 15 or later (iPhone). Allow location "Always", Bluetooth and Media & Apple Music so the app can
connect when the motorcycle is switched on and show the playing song.

## Build without a Mac

1. Upload this whole folder (including `.github`) to a **public** GitHub repo.
2. Settings > Actions > General > Workflow permissions: **Read and write**.
3. Actions > **iOS IPA** > Run workflow (it also runs on every push to `main`).
4. The IPA and `source.json` appear under **Releases**.

The project is generated with XcodeGen from `project.yml`; MapLibre is the only dependency.

## Versioning

Versions are `x.y.z`. `MARKETING_VERSION` in `project.yml` is the base (`0.1.1`). Each build raises `z` automatically
(0.1.1, 0.1.2, ...). To start a new minor version, set it to e.g. `0.2.1` and push. Releases are tagged `v<version>`.

## Changelog

`CHANGELOG.md` (English) and `CHANGELOG.id.md` (Indonesian) list every version as a `## x.y.z` section. They are bundled
into the app, which shows only the section of the installed version (Settings > About > What's new in this version),
and the workflow uses the same section as the GitHub release notes. Add a section at the top for each release.

## Project layout

```
Sources/
  Bike/      dash session (iAP), button handling, wake monitor
  CCU/       Bluetooth LE link to the motorcycle CCU
  Map/       dash frame composer, vector tile renderer, offline maps
  Nav/       routing (Valhalla), Google Maps link parsing, voice guidance
  NaviLite/  NaviLite packet encoding/parsing
  Store/     settings, places, fuel, maintenance, music, updates, backup
  Util/      formatting, Loc (translations), AppTheme
  Views/     SwiftUI screens
  Resources/ Translations.tsv, InfoPlist.strings
CHANGELOG.md, CHANGELOG.id.md   release notes per version (bundled into the app)
```

## Known limitations

- Untested on a real motorcycle: press-and-hold of the handlebar buttons on the Music screen, the "Find byte from the
  dash figure" tool, and the route preview map.
- The byte holding average fuel consumption in the CCU data is not known; use Raw CCU data to find it.
- The dash does not send anything while a button is held, so hold is detected from repeated presses.
- iOS has no API for signal bars: the dash icon shows 4 bars when there is mobile data.
- Message icon on the dash comes from iOS (ANCS), not from the app.
- Traffic is not supported. The public Valhalla demo server is for reasonable use only; run your own for daily use.
- Only songs from the Apple Music app can be read (iOS does not share Spotify track info).
- A language's voice must be installed in iOS (Settings > Accessibility > Spoken Content > Voices).

## Data sources

Map data © OpenStreetMap contributors, tiles by OpenFreeMap (OpenMapTiles). Search: Photon. Gas stations: Overpass API.
Weather: Open-Meteo. Routing: Valhalla (FOSSGIS demo server by default).

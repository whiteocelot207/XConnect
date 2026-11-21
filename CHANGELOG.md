# Changelog

Add a new `## x.y.z` section at the top for each release. The app shows only the section of the installed version
(Settings > About > What's new in this version); if a version has no section of its own, the newest section that is not
newer than it is shown. The same section is used as the GitHub release notes.

## 0.1.3

### Fixed
- The app closed right after opening (the floating banners were missing their data).
- Setup: the Bluetooth permission no longer pops up by itself when the app is first opened; it is only requested when you tap Allow on the Permissions step.
- Dash: warning colors (fuel, 12V battery, engine temperature, phone battery) now follow your settings everywhere, including the Speedometer screen cards and the corner info.
- Backup: the automatic backup also leaves out the Recent places (Home, Office and favorites are kept).

### New
- Setup: a new step after the welcome screen asks for your nickname (optional).
- Navigate: "Find nearest gas station" button.
- Setup: the language is asked right on the first screen.
- Permissions: a Photos (gallery) permission was added. The Finish button stays disabled until every permission is allowed.
- Maintenance: each item can be based on kilometers or on time. Kilometer items have their own "remind before" distance; time items (for example STNK validity) have a due date and a reminder 1, 3 or 6 months before. The interval (1 month to 5 years) can only be chosen when "Repeat" is turned on.
- Maintenance: choose an icon for each item from many motorcycle-related symbols and emoji.

### Changed
- Motorcycle year removed (setup, Settings, backup).
- Settings > Map: Routes and search moved below Offline maps.
- Handlebar controls: "2 presses" is now "2 quick presses".
- Quick-click duration defaults to 300 ms; "Remind before service" defaults to 100 km.
- Clock format setting removed: always 24-hour.
- Maintenance: the five default items can no longer be deleted (only added items can), and their names follow the app language.
- Update source setting removed: the repository is fixed in the app (`AppConfig.updateRepo`).
- Experiments and log: CCU link and Dash language sections hidden.
- About: the note under "Version and updates" removed.
- Settings > Appearance: the nickname field moved below Language.
- Settings > Bike and fuel: the global "Remind before service" distance was removed (it is now set per item).

## 0.1.2

### New
- Floating banner when a new version is available, and a "What's new in this version" page in Settings > About.
- Maintenance: intervals and last replaced km are typed, the replacement date is recorded (default today), reminders
  as a system notification plus a floating banner. Items are included in the backup.
- Warning colors you can set (fuel range, 12V battery, engine temperature, phone battery) on the dash Data Cards and the Bike tab.
- Permissions: location "Always", Bluetooth, music and notifications are requested in the first-run setup and can be
  checked again in Settings > Permissions.
- Language code 11 is now sent to the dash for Indonesian.

### Changed
- ODO is read from the CCU only and can no longer be edited.
- Routes and search settings moved into Settings > Map. Backup and restore, and Experiments and log, moved into Settings > About.
- The sample street in the map preview and voice test is the nearest street around you.
- The greeting is fixed ("Hello" / "Halo"); only the nickname can be typed, and it is empty by default.
- The plate number was removed. The Bike tab shows live battery, temperature and ignition values.
- New motorcycle icon. "Open Google Maps" and "Paste link" are larger and bold.
- The backup file is named `XConnect_setting.json` by default.

## 0.1.1

Initial release.

- Dash screens: Map, Speedometer, Music and Photos, with Data Cards, a navigation panel and handlebar controls.
- Navigation: search, Google Maps links, saved places, alternative routes, simulation, voice guidance and offline maps.
- Motorcycle: ODO, battery and temperature from the CCU, fuel estimate, maintenance and trip history.
- English and Bahasa Indonesia (dictionary in `Translations.tsv`) and color themes plus dark, light or follow phone.
- First-run setup with welcome, language and motorcycle.
- Backup and restore, and in-app updates from GitHub Releases.

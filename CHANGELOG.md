# Changelog

Add a new `## x.y.z` section at the top for each release. The app shows only the section of the installed version
(Settings > About > What's new in this version); if a version has no section of its own, the newest section that is not
newer than it is shown. The same section is used as the GitHub release notes.

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

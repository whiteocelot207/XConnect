import SwiftUI
import UniformTypeIdentifiers

/// Dokumen JSON untuk cadangan pengaturan.
struct SettingsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension AppSettings {
    static let backupKeys: [String] = [
        "autoConnect",
        "nightMode",
        "costing",
        "routingBase",
        "keepScreenOn",
        "theme",
        "userName",
        "screenMask",
        "buttonScheme",
        "slideSeconds",
        "saveBattery",
        "showCards",
        "routeColor",
        "autoZoom",
        "defaultKmPerL",
        "updateRepo",
        "updater",
        "autoCheckUpdate",
        "ccuEnabled",
        "routeWidth",
        "routeBorder",
        "markerSize",
        "markerRing",
        "markerY",
        "navPanelScale",
        "musicBlurBG",
        "cardLayout",
        "cardBig",
        "cardS1",
        "cardS2",
        "cardS3",
        "cardS4",
        "etaScale",
        "infoDashL",
        "infoDashR",
        "infoMusicL",
        "infoMusicR",
        "infoPhotoL",
        "infoPhotoR",
        "photoShift",
        "greetingWord",
        "cardBgAlpha",
        "markerX",
        "navDX",
        "navDY",
        "etaDX",
        "etaDY",
        "startScreen",
        "doubleClickMs",
        "dashLang",
        "clock24",
        "ccuExtraIds",
        "showRoadName",
        "cardFontBig",
        "cardFontSmall",
        "dashQuality",
        "keepAliveAudio",
        "etaShowDistance",
        "etaShowDuration",
        "etaShowArrival",
        "guideVoice",
        "guideDuck",
        "guideDuckLevel",
        "guideVolume",
        "routePrimary",
        "routeTopSpeed",
        "routeHills",
        "routeLiving",
        "routeTrails",
        "routeFerry",
        "routeAvoidTolls",
        "routeHighways",
        "routeShortest"
    ]

    func exportBackup() -> Data {
        let d = UserDefaults.standard
        var out: [String: Any] = [:]
        for k in AppSettings.backupKeys {
            if let v = d.object(forKey: k) { out[k] = v }
        }
        let wrapper: [String: Any] = ["app": "XConnect", "format": 1, "settings": out]
        return (try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Mengembalikan jumlah item yang diterapkan, atau nil bila file bukan cadangan XConnect.
    func importBackup(_ data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["app"] as? String == "XConnect",
              let s = obj["settings"] as? [String: Any] else { return nil }
        let d = UserDefaults.standard
        var n = 0
        for k in AppSettings.backupKeys {
            if let v = s[k] { d.set(v, forKey: k); n += 1 }
        }
        reloadFromDefaults()
        return n
    }
}

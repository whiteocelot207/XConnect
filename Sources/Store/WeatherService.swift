import Foundation
import CoreLocation

final class WeatherService: ObservableObject {
    @Published var tempC: Int?
    /// kode cuaca WMO dari Open-Meteo (-1 = belum ada)
    @Published var code = -1

    /// Teks cuaca, diterjemahkan SAAT dibutuhkan (jadi mengikuti bahasa yang dipilih sekarang, bukan bahasa saat data diambil).
    var text: String { code < 0 ? "" : WeatherService.describe(code) }

    /// Nama simbol SF Symbols untuk ikon cuaca (malam hari: bulan untuk cerah/berawan sebagian).
    func symbol(night: Bool) -> String { WeatherService.symbol(code, night: night) }

    private var lastFetch = Date.distantPast

    func refresh(_ c: CLLocationCoordinate2D) {
        guard Date().timeIntervalSince(lastFetch) > 1200 else { return }
        lastFetch = Date()
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m,weather_code&timezone=auto"
        guard let url = URL(string: urlStr) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double else { return }
            let code = (cur["weather_code"] as? Int) ?? -1
            DispatchQueue.main.async {
                self?.tempC = Int(temp.rounded())
                self?.code = code
            }
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return tr("Clear")
        case 1, 2: return tr("Partly cloudy")
        case 3: return tr("Cloudy")
        case 45, 48: return tr("Foggy")
        case 51...55: return tr("Drizzle")
        case 56, 57, 66, 67: return tr("Freezing rain")
        case 61: return tr("Light rain")
        case 63: return tr("Rain")
        case 65, 82: return tr("Heavy rain")
        case 71...77, 85, 86: return tr("Snow")
        case 80, 81: return tr("Rain showers")
        case 95...99: return tr("Thunderstorm")
        default: return tr("Weather")
        }
    }

    static func symbol(_ code: Int, night: Bool) -> String {
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

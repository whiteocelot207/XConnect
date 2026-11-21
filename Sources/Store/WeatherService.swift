import Foundation
import CoreLocation

final class WeatherService: ObservableObject {
    @Published var tempC: Int?
    @Published var text = ""

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
                self?.text = WeatherService.describe(code)
            }
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return tr("Clear")
        case 1, 2: return tr("Partly cloudy")
        case 3: return tr("Cloudy")
        case 45, 48: return tr("Foggy")
        case 51...57: return tr("Drizzle")
        case 61...67: return tr("Rain")
        case 80...82: return tr("Heavy rain")
        case 95...99: return tr("Thunderstorm")
        default: return tr("Weather")
        }
    }
}

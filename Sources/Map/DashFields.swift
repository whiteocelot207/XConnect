import UIKit

/// Isi kotak data di dash. Urutan rawValue dipakai untuk menyimpan pilihan, jangan diubah.
enum DashField: Int, CaseIterable {
    case weather = 0, phoneBattery, fuel, range, batteryV, odo, coolant, airTemp, speed, rpm, clock, ignition, none

    var title: String {
        switch self {
        case .weather: return "Cuaca + sapaan"
        case .phoneBattery: return "Baterai HP"
        case .fuel: return "Sisa bensin"
        case .range: return "Jarak tempuh BBM"
        case .batteryV: return "Aki (V)"
        case .odo: return "ODO"
        case .coolant: return "Suhu mesin (CCU)"
        case .airTemp: return "Suhu udara (CCU)"
        case .speed: return "Kecepatan"
        case .rpm: return "RPM"
        case .clock: return "Jam"
        case .ignition: return "Kunci kontak"
        case .none: return "Kosong"
        }
    }

    /// (label, nilai, satuan, warna nilai)
    func resolve(_ c: DashContent) -> (String, String, String, UIColor) {
        let white = UIColor.white
        let green = UIColor(red: 0.38, green: 0.88, blue: 0.52, alpha: 1)
        let amber = UIColor(red: 1.0, green: 0.76, blue: 0.25, alpha: 1)
        let red = UIColor(red: 1.0, green: 0.38, blue: 0.36, alpha: 1)
        switch self {
        case .weather:
            return ("Cuaca", c.tempC.map { "\($0)°" } ?? "--°", "", white)
        case .phoneBattery:
            let v = c.phoneBattery
            return ("Baterai HP", v >= 0 ? "\(v)" : "—", v >= 0 ? "%" : "", v >= 0 && v <= 20 ? red : white)
        case .fuel:
            guard let f = c.fuelL else { return ("Sisa bensin", "—", "", white) }
            return ("Sisa bensin", Fmt.liters(f).replacingOccurrences(of: " L", with: ""), "L", f < 2.5 ? red : (f < 4 ? amber : white))
        case .range:
            guard let r = c.rangeKm else { return ("Jarak tempuh", "—", "", white) }
            return ("Jarak tempuh", "\(r)", "km", r < 35 ? red : (r < 60 ? amber : white))
        case .batteryV:
            guard let v = c.batteryV else { return ("Aki", "—", "", white) }
            return ("Aki", String(format: "%.1f", v), "V", v >= 12.6 ? green : (v >= 11.8 ? amber : red))
        case .odo:
            guard let o = c.odoKm else { return ("ODO", "—", "", white) }
            return ("ODO", "\(Int(o))", "km", white)
        case .coolant:
            guard let t = c.coolantC else { return ("Suhu mesin", "—", "", white) }
            return ("Suhu mesin", "\(t)", "°C", t >= 105 ? red : (t >= 95 ? amber : white))
        case .airTemp:
            guard let t = c.airC else { return ("Suhu udara", "—", "", white) }
            return ("Suhu udara", "\(t)", "°C", white)
        case .speed:
            return ("Kecepatan", "\(c.speedKmh)", "km/h", white)
        case .rpm:
            guard let r = c.rpm else { return ("RPM", "—", "", white) }
            return ("RPM", "\(r)", "", white)
        case .clock:
            return ("Jam", c.clock, "", white)
        case .ignition:
            guard let on = c.ignitionOn else { return ("Kunci kontak", "—", "", white) }
            return ("Kunci kontak", on ? "ON" : "OFF", "", on ? green : white)
        case .none:
            return ("", "", "", white)
        }
    }
}

struct CardConfig {
    var layout = 1                 // 0 = besar + 2 kecil, 1 = besar + 4 kecil, 2 = 4 kecil
    var big = 0
    var small = [1, 2, 3, 4]
}

import UIKit

/// Isi kotak data di dash. Urutan rawValue dipakai untuk menyimpan pilihan, jangan diubah.
enum DashField: Int, CaseIterable {
    case weather = 0, phoneBattery, fuel, range, batteryV, odo, coolant, airTemp, speed, rpm, clock, ignition, none, tempBat
    case dtc = 14, ccuSpeed, phoneVolume, audioOut, network, date, heading, altitude
    /// byte mentah dari paket data CCU (id 1). Untuk mencari tahu byte mana berarti apa.
    case ccuB0 = 100, ccuB1, ccuB2, ccuB3, ccuB4, ccuB5, ccuB6, ccuB7, ccuB8, ccuB9, ccuB10, ccuB11,
         ccuB12, ccuB13, ccuB14, ccuB15, ccuB16, ccuB17, ccuB18, ccuB19, ccuB20, ccuB21, ccuB22, ccuB23

    /// indeks byte untuk kotak "CCU byte n", nil bila bukan kotak byte
    var rawByteIndex: Int? {
        rawValue >= 100 && rawValue <= 123 ? rawValue - 100 : nil
    }

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
        case .tempBat: return "Suhu + baterai HP"
        case .dtc: return "Kode gangguan mesin (CCU)"
        case .ccuSpeed: return "Kecepatan dari CCU"
        case .phoneVolume: return "Volume HP"
        case .audioOut: return "Output audio"
        case .network: return "Jaringan seluler (4G/5G)"
        case .date: return "Tanggal"
        case .heading: return "Arah (kompas GPS)"
        case .altitude: return "Ketinggian (GPS)"
        default:
            if let i = rawByteIndex { return "CCU byte \(i) (data mentah)" }
            return "?"
        }
    }

    /// Kotak yang tampil di pilihan: yang bermakna dulu, byte mentah di akhir.
    static var selectable: [DashField] {
        let main = DashField.allCases.filter { $0.rawByteIndex == nil }
        let raw = DashField.allCases.filter { $0.rawByteIndex != nil }
        return main + raw
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
        case .tempBat:
            var parts = [String]()
            if let t = c.tempC { parts.append("\(t)°") }
            if c.phoneBattery >= 0 { parts.append("\(c.phoneBattery)%") }
            return ("Suhu + baterai", parts.isEmpty ? "—" : parts.joined(separator: " · "), "", white)
        case .dtc:
            guard let n = c.dtcCount else { return ("Gangguan", "—", "", white) }
            return ("Gangguan", n == 0 ? "OK" : "\(n)", n == 0 ? "" : "kode", n == 0 ? green : red)
        case .ccuSpeed:
            guard let v = c.ccuSpeedKmh else { return ("Kecepatan CCU", "—", "", white) }
            return ("Kecepatan CCU", "\(v)", "km/h", white)
        case .phoneVolume:
            let v = c.phoneVolume
            return ("Volume HP", v >= 0 ? "\(v)" : "—", v >= 0 ? "%" : "", white)
        case .audioOut:
            return ("Audio", c.audioOut.isEmpty ? "—" : c.audioOut, "", white)
        case .network:
            return ("Jaringan", c.network.isEmpty ? "—" : c.network, "", white)
        case .date:
            return ("Tanggal", c.dateText, "", white)
        case .heading:
            return ("Arah", c.headingText.isEmpty ? "—" : c.headingText, "", white)
        case .altitude:
            guard let a = c.altitudeM else { return ("Ketinggian", "—", "", white) }
            return ("Ketinggian", "\(a)", "m", white)
        default:
            if let i = rawByteIndex {
                guard i < c.ccuRaw.count else { return ("CCU byte \(i)", "—", "", white) }
                return ("CCU byte \(i)", "\(c.ccuRaw[i])", "", white)
            }
            return ("", "", "", white)
        }
    }
}

struct CardConfig {
    var layout = 1                 // 0 = besar + 2 kecil, 1 = besar + 4 kecil, 2 = 4 kecil
    var big = 0
    var small = [1, 2, 3, 4]
    var bigScale: CGFloat = 1      // skala huruf kotak besar (otomatis mengecil bila tidak muat)
    var smallScale: CGFloat = 1    // skala huruf kotak kecil
}

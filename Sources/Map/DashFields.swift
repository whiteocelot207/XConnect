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
        case .weather: return tr("Weather + greeting")
        case .phoneBattery: return tr("Phone battery")
        case .fuel: return tr("Fuel left")
        case .range: return tr("Fuel range")
        case .batteryV: return tr("12V battery (V)")
        case .odo: return "ODO"
        case .coolant: return tr("Engine temp (CCU)")
        case .airTemp: return tr("Air temp (CCU)")
        case .speed: return tr("Speed")
        case .rpm: return "RPM"
        case .clock: return tr("Clock")
        case .ignition: return tr("Ignition")
        case .none: return tr("Empty")
        case .tempBat: return tr("Temp + phone battery")
        case .dtc: return tr("Engine fault codes (CCU)")
        case .ccuSpeed: return tr("Speed from CCU")
        case .phoneVolume: return tr("Phone volume")
        case .audioOut: return tr("Audio output")
        case .network: return tr("Mobile network (4G/5G)")
        case .date: return tr("Date")
        case .heading: return tr("Heading (GPS compass)")
        case .altitude: return tr("Altitude (GPS)")
        default:
            if let i = rawByteIndex { return tr("CCU byte {0} (raw data)", i) }
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
            return (tr("Weather"), c.tempC.map { "\($0)°" } ?? "--°", "", white)
        case .phoneBattery:
            let v = c.phoneBattery
            return (tr("Phone battery"), v >= 0 ? "\(v)" : "—", v >= 0 ? "%" : "", v >= 0 && v <= c.warn.phoneRedPct ? red : white)
        case .fuel:
            guard let f = c.fuelL else { return (tr("Fuel left"), "—", "", white) }
            let col: UIColor = c.rangeKm.map { $0 < c.warn.fuelRedKm ? red : ($0 < c.warn.fuelAmberKm ? amber : white) }
                ?? (f < 2.5 ? red : (f < 4 ? amber : white))
            return (tr("Fuel left"), Fmt.liters(f).replacingOccurrences(of: " L", with: ""), "L", col)
        case .range:
            guard let r = c.rangeKm else { return (tr("Range"), "—", "", white) }
            return (tr("Range"), "\(r)", "km", r < c.warn.fuelRedKm ? red : (r < c.warn.fuelAmberKm ? amber : white))
        case .batteryV:
            guard let v = c.batteryV else { return (tr("12V battery"), "—", "", white) }
            return (tr("12V battery"), String(format: "%.1f", v), "V", v >= c.warn.battGreenV ? green : (v >= c.warn.battRedV ? amber : red))
        case .odo:
            guard let o = c.odoKm else { return ("ODO", "—", "", white) }
            return ("ODO", "\(Int(o))", "km", white)
        case .coolant:
            guard let t = c.coolantC else { return (tr("Engine temp"), "—", "", white) }
            return (tr("Engine temp"), "\(t)", "°C", t >= c.warn.tempRedC ? red : (t >= c.warn.tempAmberC ? amber : white))
        case .airTemp:
            guard let t = c.airC else { return (tr("Air temp"), "—", "", white) }
            return (tr("Air temp"), "\(t)", "°C", white)
        case .speed:
            return (tr("Speed"), "\(c.speedKmh)", "km/h", white)
        case .rpm:
            guard let r = c.rpm else { return ("RPM", "—", "", white) }
            return ("RPM", "\(r)", "", white)
        case .clock:
            return (tr("Clock"), c.clock, "", white)
        case .ignition:
            guard let on = c.ignitionOn else { return (tr("Ignition"), "—", "", white) }
            return (tr("Ignition"), on ? "ON" : "OFF", "", on ? green : white)
        case .none:
            return ("", "", "", white)
        case .tempBat:
            var parts = [String]()
            if let t = c.tempC { parts.append("\(t)°") }
            if c.phoneBattery >= 0 { parts.append("\(c.phoneBattery)%") }
            return (tr("Temp + battery"), parts.isEmpty ? "—" : parts.joined(separator: " · "), "", white)
        case .dtc:
            guard let n = c.dtcCount else { return (tr("Faults"), "—", "", white) }
            return (tr("Faults"), n == 0 ? "OK" : "\(n)", n == 0 ? "" : tr("codes"), n == 0 ? green : red)
        case .ccuSpeed:
            guard let v = c.ccuSpeedKmh else { return (tr("CCU speed"), "—", "", white) }
            return (tr("CCU speed"), "\(v)", "km/h", white)
        case .phoneVolume:
            let v = c.phoneVolume
            return (tr("Phone volume"), v >= 0 ? "\(v)" : "—", v >= 0 ? "%" : "", white)
        case .audioOut:
            return (tr("Audio"), c.audioOut.isEmpty ? "—" : c.audioOut, "", white)
        case .network:
            return (tr("Network"), c.network.isEmpty ? "—" : c.network, "", white)
        case .date:
            return (tr("Date"), c.dateText, "", white)
        case .heading:
            return (tr("Heading"), c.headingText.isEmpty ? "—" : c.headingText, "", white)
        case .altitude:
            guard let a = c.altitudeM else { return (tr("Altitude"), "—", "", white) }
            return (tr("Altitude"), "\(a)", "m", white)
        default:
            if let i = rawByteIndex {
                guard i < c.ccuRaw.count else { return (tr("CCU byte {0}", i), "—", "", white) }
                return (tr("CCU byte {0}", i), "\(c.ccuRaw[i])", "", white)
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

/// Batas warna peringatan (merah/kuning/hijau) untuk kartu data di dash dan tab Motor. Diatur di Pengaturan > Motor dan BBM.
struct WarnThresholds {
    var fuelRedKm = 40
    var fuelAmberKm = 60
    var battGreenV = 12.6
    var battRedV = 11.8
    var tempAmberC = 95
    var tempRedC = 105
    var phoneRedPct = 20
}

import Foundation
import CoreLocation

struct Trip: Codable, Identifiable {
    var id: String
    var start: Date
    var end: Date
    var distanceKm: Double
    var maxKmh: Double
    var movingSec: Double
}

struct ParkedInfo: Codable {
    var lat: Double
    var lon: Double
    var date: Date
    var place: String
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// Mencatat perjalanan selama dash tersambung dan menyimpan lokasi motor saat terakhir diparkir.
final class TripStore: ObservableObject {
    @Published var trips: [Trip] { didSet { saveTrips() } }
    @Published var parked: ParkedInfo? { didSet { saveParked() } }
    @Published var riding = false

    var onTripEnded: ((Trip) -> Void)?

    private var cur: Trip?
    private var last: CLLocation?

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "trips.v1"), let t = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = t
        } else {
            trips = []
        }
        if let data = d.data(forKey: "parked.v1"), let p = try? JSONDecoder().decode(ParkedInfo.self, from: data) {
            parked = p
        } else {
            parked = nil
        }
    }

    /// Muat ulang riwayat perjalanan dari UserDefaults (setelah memulihkan cadangan).
    func reload() {
        if let data = UserDefaults.standard.data(forKey: "trips.v1"),
           let t = try? JSONDecoder().decode([Trip].self, from: data) { trips = t } else { trips = [] }
    }

    private func saveTrips() {
        if let data = try? JSONEncoder().encode(trips) { UserDefaults.standard.set(data, forKey: "trips.v1") }
    }

    private func saveParked() {
        if let p = parked, let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: "parked.v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "parked.v1")
        }
    }

    func begin() {
        guard cur == nil else { return }
        parked = nil
        riding = true
        last = nil
        cur = Trip(id: UUID().uuidString, start: Date(), end: Date(), distanceKm: 0, maxKmh: 0, movingSec: 0)
    }

    func update(_ loc: CLLocation) {
        guard var t = cur else { return }
        if let l = last {
            let dt = loc.timestamp.timeIntervalSince(l.timestamp)
            let dist = loc.distance(from: l)
            if dt > 0, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 60, dist < 500, loc.speed > 0.8 {
                t.distanceKm += dist / 1000
                t.movingSec += dt
            }
        }
        let kmh = max(0, loc.speed) * 3.6
        if kmh > t.maxKmh && kmh < 220 { t.maxKmh = kmh }
        t.end = Date()
        cur = t
        last = loc
    }

    func finish(at loc: CLLocation?) {
        riding = false
        guard var t = cur else { return }
        cur = nil
        t.end = Date()
        if let l = loc ?? last {
            parked = ParkedInfo(lat: l.coordinate.latitude, lon: l.coordinate.longitude, date: Date(), place: "")
            CLGeocoder().reverseGeocodeLocation(l) { [weak self] marks, _ in
                guard let m = marks?.first else { return }
                let parts = [m.subLocality, m.locality].compactMap { $0 }
                DispatchQueue.main.async {
                    self?.parked?.place = parts.joined(separator: ", ")
                }
            }
        }
        if t.distanceKm >= 0.2 {
            trips.append(t)
            if trips.count > 1000 { trips = Array(trips.suffix(1000)) }
            onTripEnded?(t)
        }
    }

    func clearParked() { parked = nil }

    // MARK: - Ringkasan

    func list(from start: Date, to end: Date) -> [Trip] {
        trips.filter { $0.start >= start && $0.start < end }
    }
}

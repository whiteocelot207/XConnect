import Foundation
import CoreLocation

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var coordinate = CLLocationCoordinate2D(latitude: -6.1754, longitude: 106.8272) // Monas (cadangan)
    private(set) var bearing: Double = 0
    private(set) var bearingKnown = false
    private(set) var speedKmh: Double = 0
    private(set) var hasFix = false
    private(set) var lastLocation: CLLocation?

    var onUpdate: ((CLLocation) -> Void)?

    /// Mode simulasi navigasi: posisi dari GPS asli diabaikan dan diganti posisi buatan di sepanjang rute.
    private(set) var simulating = false
    private var realLocation: CLLocation?

    func beginSimulation() { simulating = true }

    func endSimulation() {
        guard simulating else { return }
        simulating = false
        if let l = realLocation { apply(l) }     // kembali ke posisi GPS asli
    }

    /// Posisi buatan (hanya dipakai saat simulasi); mengalir ke peta dash dan navigasi seperti GPS asli.
    func simulate(_ l: CLLocation) {
        guard simulating else { return }
        apply(l)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        // sebelum pengaturan awal selesai, izin diminta lewat layar pengaturan awal (PermissionCenter)
        if UserDefaults.standard.bool(forKey: "setupDone") { manager.requestAlwaysAuthorization() }
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }

    /// Akurasi tinggi hanya saat dash tersambung; saat motor diparkir dibuat hemat tetapi tetap hidup
    /// di latar belakang supaya app bisa menyambung otomatis tanpa dibuka.
    func setHighPower(_ on: Bool) {
        manager.desiredAccuracy = on ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = on ? kCLDistanceFilterNone : 100
    }

    /// Posisi perkiraan "sekarang": titik GPS terakhir digeser searah gerak sejauh kecepatan x (umur fix + latensi kirim).
    /// Dipakai untuk peta di dash supaya tidak tertinggal dari posisi sebenarnya (GPS hanya ~1x per detik).
    func predictedCoordinate(extraLatency: TimeInterval) -> CLLocationCoordinate2D {
        guard let l = lastLocation, l.speed > 2.0 else { return coordinate }
        let heading = l.course >= 0 ? l.course : (bearingKnown ? bearing : -1)
        guard heading >= 0 else { return coordinate }
        let age = max(0, min(2.5, -l.timestamp.timeIntervalSinceNow))
        return Geo.destination(from: l.coordinate, bearing: heading, meters: l.speed * (age + extraLatency))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        realLocation = l
        if simulating { return }
        apply(l)
    }

    private func apply(_ l: CLLocation) {
        coordinate = l.coordinate
        lastLocation = l
        hasFix = true
        speedKmh = max(0, l.speed) * 3.6
        if l.speed > 1.5, l.course >= 0 { bearing = l.course; bearingKnown = true }
        onUpdate?(l)
    }
}

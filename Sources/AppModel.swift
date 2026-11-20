import Foundation
import UIKit
import Combine

final class AppModel: ObservableObject {
    /// Dibuat saat app diluncurkan (termasuk peluncuran di latar belakang), bukan saat tampilan pertama muncul.
    static let shared = AppModel()

    let settings: AppSettings
    let location: LocationProvider
    let places: PlaceStore
    let maint: MaintenanceStore
    let fuel: FuelStore
    let vehicle: VehicleStore
    let trips: TripStore
    let weather: WeatherService
    let music: MusicService
    let slides: SlideshowStore
    let nav: NavigationController
    let bike: BikeController
    let updater = UpdateService()
    private var bag = Set<AnyCancellable>()

    /// Muat ulang semua store dari UserDefaults/file setelah memulihkan cadangan.
    func reloadStores() {
        places.reload()
        vehicle.reload()
        maint.reload()
        fuel.reload()
        trips.reload()
    }

    init() {
        let s = AppSettings()
        let loc = LocationProvider()
        let pl = PlaceStore()
        let n = NavigationController(location: loc, settings: s, places: pl)
        let b = BikeController(location: loc, settings: s, places: pl, nav: n)
        let tr = TripStore()
        let mt = MaintenanceStore()
        loc.onUpdate = { [weak n, weak b] l in
            n?.locationUpdated(l)
            b?.locationUpdated(l)
        }
        tr.onTripEnded = { [weak mt, weak b] t in
            if b?.vehicleLive.odoKm == nil { mt?.addKm(t.distanceKm) }   // bila CCU memberi ODO, jangan dihitung ganda
        }
        settings = s
        location = loc
        places = pl
        maint = mt
        fuel = FuelStore()
        vehicle = VehicleStore()
        trips = tr
        weather = WeatherService()
        music = MusicService()
        slides = SlideshowStore()
        nav = n
        bike = b
        b.model = self
        // konsumsi BBM dari CCU (bila diaktifkan di Pengaturan): dipakai FuelStore menghitung sisa bensin
        fuel.ccuKmPerL = { [weak s, weak b] in
            guard let s = s, let b = b, s.ccuFuelByte >= 0 else { return nil }
            return b.vehicleLive.fuelKmPerL(byte: s.ccuFuelByte, wide: s.ccuFuelWide,
                                            unit: s.ccuFuelUnit, divisor: s.ccuFuelDiv)
        }
        music.onLog = { [weak b] s in b?.log(s) }
        music.onSystemVolume = { [weak b] v in b?.systemVolumeChanged(v) }
        n.voice = VoiceGuide(settings: s, music: music)
        music.keepAliveEnabled = s.keepAliveAudio
        music.startMonitoring()
        s.$keepAliveAudio.dropFirst()
            .sink { [weak self] on in
                self?.music.keepAliveEnabled = on
                self?.music.updateKeepAlive()
            }
            .store(in: &bag)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = AppModel.shared
        return true
    }
}

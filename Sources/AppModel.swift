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
        // pulihkan data yang hilang dari UserDefaults (mis. app diluncurkan sebelum ponsel dibuka kuncinya) SEBELUM dibaca
        Vault.restore()
        let s = AppSettings()
        let loc = LocationProvider()
        let pl = PlaceStore()
        let n = NavigationController(location: loc, settings: s, places: pl)
        let b = BikeController(location: loc, settings: s, places: pl, nav: n)
        let tripStore = TripStore()
        let mt = MaintenanceStore()
        loc.onUpdate = { [weak n, weak b] l in
            n?.locationUpdated(l)
            b?.locationUpdated(l)
        }
        tripStore.onTripEnded = { [weak mt, weak b] t in
            if b?.vehicleLive.odoKm == nil { mt?.addKm(t.distanceKm) }   // bila CCU memberi ODO, jangan dihitung ganda
        }
        settings = s
        location = loc
        places = pl
        maint = mt
        fuel = FuelStore()
        vehicle = VehicleStore()
        trips = tripStore
        weather = WeatherService()
        music = MusicService()
        slides = SlideshowStore()
        nav = n
        bike = b
        b.model = self
        if Vault.restoredCount > 0 {
            b.log(tr("Data restored from automatic backup ({0} items): UserDefaults was unreadable (phone locked since restart?)", Vault.restoredCount))
        }
        Vault.start()
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
        let model = AppModel.shared
        let state = application.applicationState == .background ? tr("background") : tr("foreground")
        let reason = (launchOptions ?? [:]).keys.map { $0.rawValue.replacingOccurrences(of: "UIApplicationLaunchOptions", with: "") }
        model.bike.log(tr("App launch ({0}{1})", state, reason.isEmpty ? "" : ", pemicu: " + reason.joined(separator: ", ")))
        return true
    }
}

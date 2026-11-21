import Foundation
import CoreLocation
import CoreBluetooth
import MediaPlayer
import UserNotifications
import UIKit

/// Status dan permintaan izin iOS yang dipakai XConnect: lokasi (sampai "Selalu"), Bluetooth, musik, notifikasi.
/// Dipakai di pengaturan awal dan di Pengaturan > Perizinan.
final class PermissionCenter: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    enum Status { case notDetermined, granted, whenInUse, denied }

    @Published var location: Status = .notDetermined
    @Published var bluetooth: Status = .notDetermined
    @Published var music: Status = .notDetermined
    @Published var notifications: Status = .notDetermined

    private let lm = CLLocationManager()
    private var cb: CBCentralManager?
    private var wantAlways = false

    override init() {
        super.init()
        lm.delegate = self
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc func refresh() {
        switch lm.authorizationStatus {
        case .authorizedAlways: location = .granted
        case .authorizedWhenInUse: location = .whenInUse
        case .notDetermined: location = .notDetermined
        default: location = .denied
        }
        switch CBCentralManager.authorization {
        case .allowedAlways: bluetooth = .granted
        case .notDetermined: bluetooth = .notDetermined
        default: bluetooth = .denied
        }
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: music = .granted
        case .notDetermined: music = .notDetermined
        default: music = .denied
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                switch s.authorizationStatus {
                case .authorized, .provisional, .ephemeral: self?.notifications = .granted
                case .notDetermined: self?.notifications = .notDetermined
                default: self?.notifications = .denied
                }
            }
        }
    }

    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    // MARK: - Permintaan

    func requestLocation() {
        switch lm.authorizationStatus {
        case .notDetermined:
            wantAlways = true                       // setelah "Saat dipakai" dijawab, minta "Selalu"
            lm.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            lm.requestAlwaysAuthorization()
            // iOS hanya menampilkan permintaan "Selalu" sekali; bila tidak muncul, arahkan ke Pengaturan iOS
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self, self.lm.authorizationStatus == .authorizedWhenInUse,
                      UIApplication.shared.applicationState == .active else { return }
                self.openSettings()
            }
        default:
            openSettings()
        }
    }

    func requestBluetooth() {
        if CBCentralManager.authorization == .notDetermined {
            cb = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else {
            openSettings()
        }
    }

    func requestMusic() {
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async {
                    AppModel.shared.music.requestAccess()
                    self?.refresh()
                }
            }
        } else {
            openSettings()
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                if s.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                        DispatchQueue.main.async { self?.refresh() }
                    }
                } else {
                    self?.openSettings()
                }
            }
        }
    }

    // MARK: - Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
        if wantAlways, manager.authorizationStatus == .authorizedWhenInUse {
            wantAlways = false
            manager.requestAlwaysAuthorization()
        } else if manager.authorizationStatus != .notDetermined {
            wantAlways = false
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) { refresh() }
}

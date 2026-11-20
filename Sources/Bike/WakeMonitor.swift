import Foundation
import CoreLocation
import CoreBluetooth

/// Membangunkan app TANPA dibuka, supaya dash tersambung sendiri saat motor dinyalakan (padanan WakeMonitor di NConnect).
///
/// Dua pemicu, keduanya tetap bekerja walau app sudah dimatikan iOS:
///  1. Geofence di titik parkir (radius 150 m): saat Anda berangkat keluar dari titik itu, iOS meluncurkan app.
///     Wajib izin lokasi "Selalu".
///  2. Sambungan BLE tertunda ke CCU motor (dengan state restoration): saat motor dinyalakan dan CCU terjangkau, iOS
///     meluncurkan app. ID perangkat CCU dicatat otomatis saat dash tersambung untuk pertama kali.
/// Setelah bangun, BikeController yang menyambungkan dash (EAAccessory).
final class WakeMonitor: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    static let regionID = "id.xconnect.park"
    static let restoreID = "id.xconnect.ble-wake"
    static let peripheralKey = "ccu.peripheral"
    static let radius: CLLocationDistance = 150

    var onWake: (String) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }

    private let manager = CLLocationManager()
    private var central: CBCentralManager?
    private var blePeripheral: CBPeripheral?
    private var bleWanted = false
    private var lastWake = Date.distantPast
    private var lastArm = Date.distantPast
    private(set) var armed = false

    override init() {
        super.init()
        manager.delegate = self          // harus diset sejak peluncuran supaya event geofence yang membangunkan app diterima
    }

    /// Panggil saat peluncuran: membuat CBCentralManager dengan restore identifier supaya iOS bisa memulihkannya.
    func start() {
        ensureCentral()
        // geofence yang masih terpasang dari sesi sebelumnya dianggap aktif
        armed = manager.monitoredRegions.contains { $0.identifier == WakeMonitor.regionID }
    }

    // MARK: - Geofence titik parkir

    /// Pasang geofence di titik parkir (dan pasang sambungan BLE tertunda). Panggil saat dash terputus / motor diparkir.
    func arm(at loc: CLLocation) {
        // dipanggil dari tiap pembaruan lokasi bila belum terpasang: jangan mencoba (dan mencatat log) terlalu sering
        guard Date().timeIntervalSince(lastArm) > 20 else { return }
        lastArm = Date()
        armBle()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            onLog("Wake: geofence tidak tersedia di perangkat ini")
            return
        }
        guard manager.authorizationStatus == .authorizedAlways else {
            onLog("Wake: izin lokasi bukan \"Selalu\", geofence tidak dipasang (Pengaturan iOS > XConnect > Lokasi > Selalu)")
            return
        }
        removeRegions()
        let r = CLCircularRegion(center: loc.coordinate, radius: WakeMonitor.radius, identifier: WakeMonitor.regionID)
        r.notifyOnExit = true
        r.notifyOnEntry = false
        manager.startMonitoring(for: r)
        armed = true
        onLog(String(format: "Wake: geofence dipasang di titik parkir (%.5f, %.5f), radius %d m",
                     loc.coordinate.latitude, loc.coordinate.longitude, Int(WakeMonitor.radius)))
    }

    /// Lepas geofence dan sambungan BLE tertunda (dash sudah tersambung).
    func disarm() {
        guard armed || bleWanted else { return }
        removeRegions()
        armed = false
        disarmBle()
        onLog("Wake: dilepas (dash tersambung)")
    }

    private func removeRegions() {
        for r in manager.monitoredRegions where r.identifier == WakeMonitor.regionID {
            manager.stopMonitoring(for: r)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == WakeMonitor.regionID else { return }
        armed = false
        removeRegions()
        wake("keluar dari titik parkir")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        armed = false
        onLog("Wake: geofence gagal: \(error.localizedDescription)")
    }

    private func wake(_ reason: String) {
        // beberapa pemicu bisa datang berdekatan; cukup satu
        guard Date().timeIntervalSince(lastWake) > 5 else { return }
        lastWake = Date()
        onWake(reason)
    }

    // MARK: - BLE ke CCU (state restoration)

    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: WakeMonitor.restoreID,
                                             CBCentralManagerOptionShowPowerAlertKey: false])
    }

    /// Sambungan tertunda ke CCU: tidak punya batas waktu, dan iOS membangunkan/meluncurkan app saat CCU terjangkau.
    func armBle() {
        guard let s = UserDefaults.standard.string(forKey: WakeMonitor.peripheralKey), let id = UUID(uuidString: s) else {
            onLog("Wake: ID Bluetooth CCU belum diketahui (dicatat otomatis setelah dash tersambung sekali)")
            return
        }
        bleWanted = true
        ensureCentral()
        guard let c = central, c.state == .poweredOn else { return }   // dilanjutkan di centralManagerDidUpdateState
        guard let p = c.retrievePeripherals(withIdentifiers: [id]).first else {
            onLog("Wake: perangkat CCU tidak dikenal iOS (belum pernah tersambung lewat app ini)")
            return
        }
        blePeripheral = p
        if p.state == .disconnected {
            c.connect(p, options: nil)
            onLog("Wake: menunggu CCU motor terjangkau (sambungan BLE tertunda)")
        }
    }

    private func disarmBle() {
        bleWanted = false
        if let p = blePeripheral, p.state != .disconnected { central?.cancelPeripheralConnection(p) }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn, bleWanted { armBle() }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        let list = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        onLog("Wake: app dipulihkan iOS lewat Bluetooth (\(list.count) perangkat)")
        guard let p = list.first else { return }
        blePeripheral = p
        if p.state == .connected {
            connectedAndWake(p, c)
        } else {
            bleWanted = true
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connectedAndWake(p, c)
    }

    /// CCU terjangkau = motor menyala. Sambungan langsung dilepas lagi: sambungan data dipegang CcuLink, dan CCU hanya
    /// menerima satu sambungan.
    private func connectedAndWake(_ p: CBPeripheral, _ c: CBCentralManager) {
        bleWanted = false
        c.cancelPeripheralConnection(p)
        wake("CCU motor terdeteksi (Bluetooth)")
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard bleWanted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, self.bleWanted else { return }
            self.armBle()
        }
    }
}

import Foundation
import CoreLocation

struct DashNavState {
    var icon: UInt8
    var distanceM: Double
    var nextRoad: String
    var currentRoad: String
    var etaMinutes: Int
    /// judul panel: "Jalan Lingkar Luar Jakarta" / "Ambil jalan keluar ke 3"
    var title: String = ""
}

final class NavigationController: ObservableObject {
    enum Phase { case idle, previewing, navigating }

    @Published var phase: Phase = .idle
    @Published var query = ""
    @Published var searchResults: [Place] = []
    @Published var searching = false
    @Published var destination: Place?
    @Published var route: Route?
    /// semua pilihan rute (indeks 0 = tercepat) dan yang sedang dipilih
    @Published var routes: [Route] = []
    @Published var routeIndex = 0
    @Published var routeVersion = 0
    @Published var busy = false
    @Published var message = ""
    @Published var distToTurnM: Double = 0
    @Published var nextInstruction = ""
    @Published var nextSymbol = "arrow.up"
    @Published var remainingM: Double = 0
    @Published var etaDate: Date?
    @Published var remainingS: Double = 0
    @Published var currentRoad = ""
    @Published var nextTitle = ""

    // Simulasi navigasi (uji rute tanpa berkendara)
    @Published var simulating = false
    @Published var simSpeedKmh = 40.0
    @Published var simCoordinate: CLLocationCoordinate2D?
    private var simTimer: Timer?
    private var simDist = 0.0
    private var simSeg = 0

    /// Suara petunjuk arah; dipasang oleh AppModel.
    var voice: VoiceGuide?
    private var announcedKey = -1
    private var announcedTier = 0

    /// nil = navigasi berhenti.
    var onDashState: ((DashNavState?) -> Void)?

    private let location: LocationProvider
    private let settings: AppSettings
    private let places: PlaceStore

    private var searchTask: Task<Void, Never>?
    private var segIdx = 0
    private var offRouteSince: Date?
    private var lastReroute = Date.distantPast
    private var rerouting = false
    private var autoStart = false
    private(set) var lastDash: DashNavState?
    @Published var pendingSlot = 0          // 0 = tidak ada, 1 = Rumah, 2 = Kantor
    @Published var linkBusy = false

    init(location: LocationProvider, settings: AppSettings, places: PlaceStore) {
        self.location = location
        self.settings = settings
        self.places = places
    }

    // MARK: - Pencarian

    func queryChanged() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 3 {
            searchResults = []
            return
        }
        let near = location.coordinate
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            DispatchQueue.main.async { self?.searching = true }
            let res = (try? await PlaceSearch.search(q, near: near)) ?? []
            if Task.isCancelled { return }
            DispatchQueue.main.async {
                self?.searchResults = res
                self?.searching = false
                if res.isEmpty { self?.message = "Tempat tidak ditemukan" }
            }
        }
    }

    func showFuelStations() {
        let near = location.coordinate
        searching = true
        Task { [weak self] in
            let res = (try? await PlaceSearch.fuelStations(near: near, radius: 5000)) ?? []
            DispatchQueue.main.async {
                self?.searchResults = res
                self?.searching = false
                self?.message = res.isEmpty ? "SPBU tidak ditemukan atau server sibuk" : ""
            }
        }
    }

    // MARK: - Rute

    func select(_ p: Place) {
        searchResults = []
        query = ""
        if pendingSlot != 0 {
            if pendingSlot == 1 { places.home = p } else { places.work = p }
            pendingSlot = 0
            message = ""
            return
        }
        navigate(to: p, autoStart: false)
    }

    /// Menerima tautan Google Maps atau koordinat dan langsung memilihnya sebagai tujuan.
    func resolveLink(_ text: String) {
        guard !linkBusy else { return }
        linkBusy = true
        message = "Membaca tautan…"
        let near = location.coordinate
        Task { [weak self] in
            do {
                let p = try await MapsLink.resolve(text, near: near)
                DispatchQueue.main.async {
                    self?.linkBusy = false
                    self?.message = ""
                    self?.select(p)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.linkBusy = false
                    self?.message = error.localizedDescription
                }
            }
        }
    }

    func beginSlot(_ slot: Int) {
        pendingSlot = slot
        message = slot == 1 ? "Cari tempat untuk Rumah" : "Cari tempat untuk Kantor"
    }

    /// Ringkasan untuk banner di dash.
    var hud: NavHUD? {
        guard phase == .navigating, let d = lastDash else { return nil }
        var parts = [String]()
        if settings.etaShowDistance { parts.append(Fmt.distance(remainingM)) }
        if settings.etaShowDuration { parts.append(Fmt.duration(remainingS)) }
        if settings.etaShowArrival, let e = etaDate { parts.append(Fmt.clock(e)) }
        let summary = parts.joined(separator: " · ")
        return NavHUD(icon: d.icon, text: d.title.isEmpty ? DashIcon.shortText(d.icon) : d.title,
                      dist: Fmt.distance(d.distanceM), summary: summary)
    }

    func pin(_ c: CLLocationCoordinate2D) {
        let p = Place(name: "Titik dipilih",
                      subtitle: String(format: "%.5f, %.5f", c.latitude, c.longitude),
                      lat: c.latitude, lon: c.longitude)
        select(p)
    }

    func navigate(to p: Place, autoStart start: Bool) {
        destination = p
        autoStart = start
        places.addRecent(p)
        requestRoute(initial: true)
    }

    func goHome() {
        if let h = places.home { navigate(to: h, autoStart: true) } else { message = "Rumah belum diatur" }
    }

    func goWork() {
        if let w = places.work { navigate(to: w, autoStart: true) } else { message = "Kantor belum diatur" }
    }

    func requestRoute(initial: Bool) {
        guard let dest = destination else { return }
        guard location.hasFix else {
            message = "Menunggu sinyal GPS…"
            return
        }
        let from = location.coordinate
        let heading: Double? = (!initial && location.speedKmh > 5) ? location.bearing : nil
        let base = settings.routingBase
        let costing = settings.costing
        let profile = settings.routeProfile
        busy = true
        message = initial ? "Menghitung rute…" : "Menghitung ulang rute…"
        if !initial && phase == .navigating { voice?.speak("Menghitung ulang rute") }
        let alts = (initial && phase != .navigating) ? 2 : 0
        Task { [weak self] in
            do {
                let rs = try await ValhallaClient.routes(base: base, costing: costing, from: from,
                                                         to: dest.coordinate, heading: heading, alternatives: alts,
                                                         profile: profile)
                DispatchQueue.main.async {
                    self?.routes = rs
                    self?.routeIndex = 0
                    self?.applyRoute(rs[0], initial: initial)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.rerouting = false
                    self?.message = error.localizedDescription
                }
            }
        }
    }

    private func applyRoute(_ r: Route, initial: Bool) {
        busy = false
        rerouting = false
        message = ""
        route = r
        routeVersion += 1
        segIdx = 0
        offRouteSince = nil
        announcedKey = -1
        announcedTier = 0
        remainingM = r.totalM
        etaDate = Date().addingTimeInterval(r.totalS)
        remainingS = r.totalS
        if initial && phase != .navigating { phase = .previewing }
        if autoStart {
            autoStart = false
            startNavigation()
        } else if phase == .navigating, let l = location.lastLocation {
            locationUpdated(l)
        }
    }

    /// Pilih salah satu rute alternatif di layar pratinjau.
    func selectRoute(_ i: Int) {
        guard phase != .navigating, routes.indices.contains(i) else { return }
        routeIndex = i
        let r = routes[i]
        route = r
        routeVersion += 1
        segIdx = 0
        remainingM = r.totalM
        etaDate = Date().addingTimeInterval(r.totalS)
        remainingS = r.totalS
    }

    func startNavigation() {
        guard route != nil else { return }
        phase = .navigating
        segIdx = 0
        offRouteSince = nil
        announcedKey = -1
        announcedTier = 0
        voice?.setNavigating(true)
        voice?.speak("Navigasi dimulai")
        if let l = location.lastLocation { locationUpdated(l) }
    }

    // MARK: - Simulasi

    /// Menjalankan navigasi dengan posisi buatan di sepanjang rute yang sedang dipilih: dash, suara,
    /// dan peta bekerja seperti berkendara sungguhan. Bisa dimulai dari pratinjau maupun saat navigasi berjalan.
    func startSimulation() {
        guard let r = route, r.points.count >= 2 else { return }
        stopSimTimer()
        simulating = true
        simDist = 0
        simSeg = 0
        location.beginSimulation()
        simStep(dt: 0)                         // posisi awal di titik pertama rute
        startNavigation()
        simTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.simStep(dt: 0.5)
        }
        RunLoop.main.add(simTimer!, forMode: .common)
    }

    /// Berhenti simulasi dan kembali ke pratinjau rute (rute tetap ada, bisa diulang atau dimulai sungguhan).
    func stopSimulation() {
        guard simulating else { return }
        voice?.setNavigating(false)
        phase = .previewing                    // sebelum lokasi asli kembali, supaya tidak dianggap keluar jalur
        endSimulationState()
        lastDash = nil
        onDashState?(nil)
        voice?.cancel()
        routeVersion += 1
    }

    private func stopSimTimer() {
        simTimer?.invalidate()
        simTimer = nil
    }

    private func endSimulationState() {
        stopSimTimer()
        simulating = false
        simCoordinate = nil
        location.endSimulation()
    }

    private func simStep(dt: Double) {
        guard simulating, let r = route, r.points.count >= 2 else { return }
        let mps = simSpeedKmh / 3.6
        simDist = min(r.totalM, simDist + mps * dt)
        let n = r.points.count - 1
        while simSeg < n - 1 && r.cum[simSeg + 1] <= simDist { simSeg += 1 }
        let a = r.points[simSeg], b = r.points[simSeg + 1]
        let segLen = max(0.01, r.cum[simSeg + 1] - r.cum[simSeg])
        let t = min(1, max(0, (simDist - r.cum[simSeg]) / segLen))
        let c = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                       longitude: a.longitude + (b.longitude - a.longitude) * t)
        let course = Geo.bearing(from: a, to: b)
        simCoordinate = c
        location.simulate(CLLocation(coordinate: c, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                                     course: course, speed: mps, timestamp: Date()))
    }

    func stop() {
        voice?.cancel()
        voice?.setNavigating(false)
        phase = .idle
        if simulating { endSimulationState() }
        route = nil
        routes = []
        routeIndex = 0
        destination = nil
        routeVersion += 1
        message = ""
        busy = false
        autoStart = false
        lastDash = nil
        onDashState?(nil)
    }

    func republish() {
        onDashState?(lastDash)
    }

    var destinationCoordinate: CLLocationCoordinate2D? { destination?.coordinate }

    // MARK: - Progres di sepanjang rute

    func locationUpdated(_ loc: CLLocation) {
        guard phase == .navigating, let r = route, r.points.count >= 2 else { return }
        let p = loc.coordinate
        let n = r.points.count - 1

        var bestI = min(segIdx, n - 1)
        var bestT = 0.0
        var bestD = Double.infinity
        let lo = max(0, bestI - 2)
        let hi = min(n - 1, bestI + 80)
        if lo <= hi {
            for i in lo...hi {
                let pr = Geo.project(p, r.points[i], r.points[i + 1])
                if pr.dist < bestD { bestD = pr.dist; bestI = i; bestT = pr.t }
            }
        }
        if bestD > 80 {
            for i in 0..<n {
                let pr = Geo.project(p, r.points[i], r.points[i + 1])
                if pr.dist < bestD { bestD = pr.dist; bestI = i; bestT = pr.t }
            }
        }
        segIdx = bestI

        // keluar jalur -> hitung ulang
        if bestD > 45 {
            if let since = offRouteSince {
                if Date().timeIntervalSince(since) > 4 && !rerouting
                    && Date().timeIntervalSince(lastReroute) > 10 {
                    rerouting = true
                    lastReroute = Date()
                    requestRoute(initial: false)
                }
            } else {
                offRouteSince = Date()
            }
        } else {
            offRouteSince = nil
        }

        let progress = r.cum[bestI] + bestT * (r.cum[bestI + 1] - r.cum[bestI])
        let remaining = max(0, r.totalM - progress)

        if remaining < 25 {
            if simulating {
                stopSimulation()
            } else {
                stop()
            }
            message = "Anda sudah tiba di tujuan"
            voice?.speak("Anda telah tiba di tujuan")
            return
        }

        var nextIdx: Int?
        for (k, m) in r.maneuvers.enumerated() where k > 0 {
            if r.cum[m.beginIdx] > progress + 3 {
                nextIdx = k
                break
            }
        }
        var icon: UInt8 = 8
        var dist = remaining
        var nextRoad = ""
        var instr = ""
        var symbol = "arrow.up"
        var title = "Lurus"
        if let k = nextIdx {
            let m = r.maneuvers[k]
            icon = DashIcon.forValhalla(m.type)
            dist = max(0, r.cum[m.beginIdx] - progress)
            nextRoad = m.street
            instr = m.sentence(distanceM: dist)
            title = m.title
            symbol = DashIcon.symbol(m.type)
            announce(k, m, dist: dist)
        }
        var cur = ""
        for m in r.maneuvers {
            if r.cum[m.beginIdx] <= progress + 1 {
                if !m.street.isEmpty { cur = m.street }
            } else {
                break
            }
        }

        let avg = max(r.totalM / max(r.totalS, 1), 4.0)
        let eta = Date().addingTimeInterval(remaining / avg)

        distToTurnM = dist
        nextInstruction = instr
        nextTitle = title
        nextSymbol = symbol
        remainingM = remaining
        currentRoad = cur
        etaDate = eta
        remainingS = remaining / avg

        let comps = Calendar.current.dateComponents([.hour, .minute], from: eta)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let state = DashNavState(icon: icon, distanceM: dist, nextRoad: nextRoad,
                                 currentRoad: cur, etaMinutes: minutes, title: title)
        lastDash = state
        onDashState?(state)
    }

    /// Suara petunjuk: pertama "Dalam 300 meter, ..." (500 m bila cepat), lalu "Dalam 100 meter, ...".
    /// Jarak yang diucapkan adalah jarak sebenarnya saat itu, jadi tidak salah bila belokan berdekatan.
    private func announce(_ k: Int, _ m: Maneuver, dist: Double) {
        if announcedKey != k {
            announcedKey = k
            announcedTier = 0
        }
        switch m.type {
        case 0, 1, 2, 3, 8: return          // mulai / lurus: tidak diumumkan
        default: break
        }
        let far: Double = (simulating ? simSpeedKmh : location.speedKmh) >= 60 ? 500 : 300
        let mid: Double = 100
        if dist <= mid && announcedTier < 2 {
            announcedTier = 2
            voice?.speak(m.sentence(distanceM: dist))
        } else if dist <= far && dist > mid && announcedTier < 1 {
            announcedTier = 1
            voice?.speak(m.sentence(distanceM: dist))
        }
    }

    /// Titik rute di depan posisi saat ini (untuk digambar di peta dash).
    func upcomingPoints(maxMeters: Double = 4000) -> [CLLocationCoordinate2D] {
        guard phase == .navigating, let r = route, r.points.count >= 2 else { return [] }
        let start = min(segIdx, r.points.count - 1)
        let limit = r.cum[start] + maxMeters
        var out = [CLLocationCoordinate2D]()
        var i = start
        while i < r.points.count && r.cum[i] <= limit {
            out.append(r.points[i])
            i += 1
        }
        if i < r.points.count { out.append(r.points[i]) }
        if out.count > 150 {
            let step = out.count / 150 + 1
            let src = out
            var thin = [CLLocationCoordinate2D]()
            for (k, c) in src.enumerated() where k % step == 0 || k == src.count - 1 {
                thin.append(c)
            }
            out = thin
        }
        return out
    }
}

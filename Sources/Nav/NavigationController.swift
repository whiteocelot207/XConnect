import Foundation
import CoreLocation

struct DashNavState {
    var icon: UInt8
    var distanceM: Double
    var nextRoad: String
    var currentRoad: String
    var etaMinutes: Int
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
    @Published var currentRoad = ""

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
        var summary = Fmt.distance(remainingM)
        if let e = etaDate { summary += " · " + Fmt.clock(e) }
        return NavHUD(icon: d.icon, text: DashIcon.shortText(d.icon), dist: Fmt.distance(d.distanceM),
                      summary: summary, street: d.nextRoad)
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
        remainingM = r.totalM
        etaDate = Date().addingTimeInterval(r.totalS)
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
    }

    func startNavigation() {
        guard route != nil else { return }
        phase = .navigating
        segIdx = 0
        offRouteSince = nil
        if let l = location.lastLocation { locationUpdated(l) }
    }

    func stop() {
        phase = .idle
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
            message = "Anda sudah tiba di tujuan"
            stop()
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
        if let k = nextIdx {
            let m = r.maneuvers[k]
            icon = DashIcon.forValhalla(m.type)
            dist = max(0, r.cum[m.beginIdx] - progress)
            nextRoad = m.street
            instr = m.instruction
            symbol = DashIcon.symbol(m.type)
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
        nextSymbol = symbol
        remainingM = remaining
        currentRoad = cur
        etaDate = eta

        let comps = Calendar.current.dateComponents([.hour, .minute], from: eta)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let state = DashNavState(icon: icon, distanceM: dist, nextRoad: nextRoad,
                                 currentRoad: cur, etaMinutes: minutes)
        lastDash = state
        onDashState?(state)
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

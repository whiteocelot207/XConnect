import SwiftUI
import UniformTypeIdentifiers

/// Membuka halaman tertentu di tab Pengaturan dari tempat lain (mis. kotak di Home).
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    enum Target { case maps, screens }
    @Published var request: Target?
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var vehicle: VehicleStore
    @ObservedObject private var offline = OfflineMapStore.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var rootID = UUID()
    @State private var openMaps = false
    @State private var openScreens = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text(tr("General"))) {
                    row(tr("Appearance"), subtitle: Loc.shared.currentName + " · " + AppTheme.theme(settings.colorTheme).name + " · "
                            + [tr("Follow phone"), tr("Dark"), tr("Light")][min(2, settings.theme)],
                        icon: "paintpalette") {
                        AppearanceSettings()
                    }
                    row(tr("Connection"), subtitle: tr("Auto-connect {0} · battery saver · CCU", settings.autoConnect ? tr("on") : tr("off")),
                        icon: "antenna.radiowaves.left.and.right") {
                        ConnectionSettings()
                    }
                    row(tr("Motorcycle and fuel"), subtitle: tr("{0} · tank · fuel consumption", vehicle.model), icon: "motorcycle.custom") {
                        VehicleSettings()
                    }
                }
                Section(header: Text(tr("Dash on the motorcycle"))) {
                    row(tr("Dash screens"), subtitle: tr("{0} active screens · start screen · music · photos", bike.screens().count),
                        icon: "rectangle.on.rectangle", isActive: $openScreens) {
                        ScreensSettings()
                    }
                    row(tr("Data Cards"), subtitle: tr("Card contents, layout, font size"), icon: "square.grid.2x2") {
                        CardSettings()
                    }
                    row(tr("Map"), subtitle: offline.areas.isEmpty
                        ? tr("Offline maps · routes · voice · day/night · bike marker")
                        : tr("{0} offline areas · routes · voice · day/night · bike marker", offline.areas.count), icon: "map",
                        isActive: $openMaps) {
                        MapSettings()
                    }
                    row(tr("Motorcycle controls"), subtitle: tr("Up/down buttons on the handlebar"), icon: "hand.tap") {
                        ControlSettings()
                    }
                }
                Section(header: Text(tr("More"))) {
                    row(tr("Permissions"), subtitle: tr("Location, Bluetooth, music, notifications"), icon: "checkmark.shield") {
                        PermissionsSettings()
                    }
                    row(tr("About"), subtitle: tr("XConnect {0} · what's new · backup · log", UpdateService.currentVersion), icon: "info.circle") {
                        AboutSettings()
                    }
                }
            }
            .navigationTitle(tr("Settings"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .id(rootID)
        .onAppear { consumeRequest() }
        .onChange(of: router.request) { _ in consumeRequest() }
    }

    /// Permintaan dari luar (kotak Peta dasar / Layar aktif di Home): kembali ke daftar utama, lalu buka halamannya.
    private func consumeRequest() {
        guard let target = router.request else { return }
        router.request = nil
        openMaps = false
        openScreens = false
        rootID = UUID()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            switch target {
            case .maps: openMaps = true
            case .screens: openScreens = true
            }
        }
    }

    private func row<D: View>(_ title: String, subtitle: String, icon: String, isActive: Binding<Bool>,
                              @ViewBuilder destination: () -> D) -> some View {
        NavigationLink(destination: destination(), isActive: isActive) {
            HStack(spacing: 14) {
                RowIcon(name: icon).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func row<D: View>(_ title: String, subtitle: String, icon: String,
                              @ViewBuilder destination: () -> D) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                RowIcon(name: icon).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text(tr("Language")),
                    footer: Text(tr("The language applies to the whole app: menus, voice guidance, navigation texts, and the texts drawn on or sent to the dash."))) {
                Picker(tr("Language"), selection: $settings.language) {
                    ForEach(Loc.shared.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section(header: Text(tr("Greeting on the dash"))) {
                TextField(tr("Nickname (shown on the dash)"), text: $settings.userName)
            }
            Section(header: Text(tr("App appearance"))) {
                Picker(tr("App appearance"), selection: $settings.theme) {
                    Text(tr("Follow phone")).tag(0)
                    Text(tr("Dark")).tag(1)
                    Text(tr("Light")).tag(2)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section(header: Text(tr("Color theme")),
                    footer: Text(tr("Changes the accent color of the app. Dark, light, or follow phone is set under App appearance."))) {
                ForEach(AppTheme.all) { th in
                    Button {
                        settings.colorTheme = th.id
                    } label: {
                        HStack(spacing: 14) {
                            Circle().fill(th.color).frame(width: 26, height: 26)
                            Text(th.name).foregroundColor(.primary)
                            Spacer()
                            if settings.colorTheme == th.id {
                                Image(systemName: "checkmark").foregroundColor(th.color)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConnectionSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var live: VehicleLive

    var body: some View {
        Form {
            Section(footer: Text(tr("The app stays alive in the background (location 'Always') so it can connect when the motorcycle is switched on, even with the phone locked. Do not force-quit the app from the app switcher."))) {
                Toggle(tr("Auto-connect"), isOn: $settings.autoConnect)
                Button(tr("Pair dash (Bluetooth)")) { bike.showPairingPicker() }
            }
            Section(footer: Text(tr("Battery saver lowers the dash frame rate (max 4 fps)."))) {
                Toggle(tr("Battery saver"), isOn: $settings.saveBattery)
                Toggle(tr("Keep the screen on while connected"), isOn: $settings.keepScreenOn)
            }
            Section(header: Text(tr("Data speed to the dash")),
                    footer: Text(tr("Lighter frames reach the dash faster, so the map and numbers do not lag behind, but the picture is slightly coarser. \"Keep phone data alive\" plays silent audio (it does not interrupt music) so volume and other phone data keep updating while the app is in the background or the screen is locked."))) {
                sliderRow(tr("Dash image quality"), value: $settings.dashQuality, range: 0.4...0.95, step: 0.05, unit: "")
                Toggle(tr("Keep phone data alive in the background"), isOn: $settings.keepAliveAudio)
            }
            Section(header: Text(tr("CCU link")), footer: Text(tr("Motorcycle data is read over Bluetooth from the CCU. Status: {0}", live.state))) {
                Toggle(tr("Read CCU data"), isOn: $settings.ccuEnabled)
                if let v = live.batteryV { Text(tr("12V battery: ") + String(format: "%.1f V", v)) }
                if let o = live.odoKm { Text(tr("ODO: ") + String(format: "%.1f km", o)) }
                if let t = live.coolantC { Text(tr("Engine temp: {0} °C", t)) }
                if let t = live.airC { Text(tr("Air temp: {0} °C", t)) }
                if let r = live.rpm { Text(tr("RPM: {0}", r)) }
                if let v = live.speedKmh { Text(tr("CCU speed: {0} km/h", v)) }
                if let d = live.dtcCount { Text(tr("Fault codes: {0}", d)) }
                if let k = live.ignitionOn { Text(tr("Ignition: ") + (k ? "ON" : "OFF")) }
                NavigationLink(tr("Raw CCU data (all bytes)")) { CcuRawView() }
            }
        }
        .navigationTitle(tr("Connection"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VehicleSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vehicle: VehicleStore
    @EnvironmentObject var live: VehicleLive
    @State private var fuelTarget = ""
    @State private var fuelCands: [FuelByteCandidate] = []
    @State private var fuelSearched = false
    @State private var pickingPhoto = false

    private var isCustomModel: Bool {
        !VehicleStore.presets.contains { $0.model == vehicle.model }
    }

    /// Pilihan tipe: XMAX, NMAX, atau Lainnya (isi sendiri).
    private var modelChoice: Binding<String> {
        Binding(
            get: { isCustomModel ? tr("More") : vehicle.model },
            set: { v in
                if let p = VehicleStore.presets.first(where: { $0.model == v }) {
                    vehicle.model = p.model
                    vehicle.tankL = p.tankL
                } else if !isCustomModel {
                    vehicle.model = tr("Other motorcycle")
                }
            })
    }

    private var ccuFuelReading: String {
        guard settings.ccuFuelByte >= 0 else { return tr("off") }
        guard !live.rawRecord.isEmpty else { return tr("no CCU data yet") }
        let lo = settings.ccuFuelByte
        let raw: String = {
            guard live.rawRecord.count > lo + (settings.ccuFuelWide ? 1 : 0) else { return tr("byte outside the packet") }
            return settings.ccuFuelWide
                ? "\(Int(live.rawRecord[lo]) << 8 | Int(live.rawRecord[lo + 1]))"
                : "\(live.rawRecord[lo])"
        }()
        if let k = live.fuelKmPerL(byte: lo, wide: settings.ccuFuelWide, unit: settings.ccuFuelUnit, divisor: settings.ccuFuelDiv) {
            return tr("raw {0} → {1} km/L", raw, Fmt.km(k))
        }
        return tr("raw {0} → invalid (outside 3-120 km/L), history/default used", raw)
    }

    var body: some View {
        Form {
            Section(header: Text(tr("Motorcycle photo"))) {
                HStack(spacing: 14) {
                    Group {
                        if let img = vehicle.photo {
                            Image(uiImage: img).resizable().scaledToFill()
                        } else {
                            MotorcycleIcon().frame(width: 46, height: 28).foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 8) {
                        Button(vehicle.photo == nil ? tr("Choose photo") : tr("Change photo")) { pickingPhoto = true }
                        if vehicle.photo != nil {
                            Button(tr("Delete photo")) { vehicle.removePhoto() }.foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            Section(header: Text(tr("Motorcycle identity")),
                    footer: Text(tr("Choosing XMAX or NMAX fills in the tank capacity automatically; you can still change it below."))) {
                TextField(tr("Motorcycle name"), text: $vehicle.name)
                Picker(tr("Motorcycle type"), selection: modelChoice) {
                    ForEach(VehicleStore.presets, id: \.model) { Text($0.model).tag($0.model) }
                    Text(tr("More")).tag(tr("More"))
                }
                if isCustomModel {
                    TextField(tr("Motorcycle type/model"), text: $vehicle.model)
                }
            }
            Section(header: Text(tr("Tank and consumption"))) {
                Stepper(tr("Tank capacity {0}", Fmt.liters(vehicle.tankL)), value: $vehicle.tankL, in: 3...30, step: 0.1)
                Stepper(tr("Default consumption {0} km/L", Fmt.km(settings.defaultKmPerL)), value: $settings.defaultKmPerL,
                        in: 10...80, step: 0.5)
            }
            Section(header: Text(tr("Warning colors")),
                    footer: Text(tr("Colors on the dash Data Cards and the Bike tab. Fuel range turns amber, then red, below these distances. 12V battery is green at or above the first value, amber down to the second, red below it. Engine temperature turns amber, then red, at these temperatures."))) {
                Stepper(tr("Fuel range amber below {0} km", settings.fuelAmberKm), value: $settings.fuelAmberKm, in: 10...300, step: 5)
                Stepper(tr("Fuel range red below {0} km", settings.fuelRedKm), value: $settings.fuelRedKm, in: 5...300, step: 5)
                Stepper(tr("12V battery green from {0} V", String(format: "%.1f", settings.battGreenV).localizedDecimal), value: $settings.battGreenV, in: 11.0...14.0, step: 0.1)
                Stepper(tr("12V battery red below {0} V", String(format: "%.1f", settings.battRedV).localizedDecimal), value: $settings.battRedV, in: 10.0...13.5, step: 0.1)
                Stepper(tr("Engine temp amber from {0} °C", settings.tempAmberC), value: $settings.tempAmberC, in: 60...130, step: 1)
                Stepper(tr("Engine temp red from {0} °C", settings.tempRedC), value: $settings.tempRedC, in: 60...140, step: 1)
                Stepper(tr("Phone battery red at {0}% or less", settings.phoneRedPct), value: $settings.phoneRedPct, in: 5...50, step: 5)
            }
            Section(header: Text(tr("Maintenance reminders")),
                    footer: Text(tr("Turns maintenance notifications and the banner on or off. When to be reminded is set per item in the Bike tab > Maintenance (by kilometers or by time). Kilometer items need the ODO from the CCU, so they work while the app is connected to the motorcycle."))) {
                Toggle(tr("Notify me about maintenance"), isOn: $settings.maintNotify)
                    .onChange(of: settings.maintNotify) { on in
                        if on { MaintenanceStore.requestNotificationPermission() }
                        AppModel.shared.maint.scheduleTimeNotifications()
                    }
            }
            Section(header: Text(tr("Fuel consumption from CCU")),
                    footer: Text(tr("Fuel left is calculated from the average consumption reported by the motorcycle CCU (more accurate than the default value), and decreases gradually according to the consumption at that moment. Pick the byte in the CCU data packet (id 1) that holds the average consumption: see Raw CCU data below and compare it with the average fuel figure on the dash. Adjust the width, unit, and divisor until \"Reading now\" matches the dash. If the value is invalid, your own consumption over the last 30 days (from the dash average) is used, then the default value."))) {
                Stepper(settings.ccuFuelByte < 0 ? tr("Consumption byte: off") : tr("Consumption byte: {0}", settings.ccuFuelByte),
                        value: $settings.ccuFuelByte, in: -1...47)
                if settings.ccuFuelByte >= 0 {
                    Picker(tr("Value width"), selection: $settings.ccuFuelWide) {
                        Text(tr("1 byte")).tag(false)
                        Text(tr("2 bytes (n and n+1)")).tag(true)
                    }
                    Picker(tr("Unit"), selection: $settings.ccuFuelUnit) {
                        Text("km/L").tag(0)
                        Text("L/100 km").tag(1)
                        Text("L/km").tag(2)
                    }
                    Picker(tr("Raw value divisor"), selection: $settings.ccuFuelDiv) {
                        Text("1").tag(1.0)
                        Text("10").tag(10.0)
                        Text("100").tag(100.0)
                        Text("1000").tag(1000.0)
                    }
                    Text(tr("Reading now: {0}", ccuFuelReading)).font(.footnote).foregroundColor(.secondary)
                }
                NavigationLink(tr("Raw CCU data (all bytes)")) { CcuRawView() }
            }
            Section(header: Text(tr("Find byte from the dash figure")),
                    footer: Text(tr("With the motorcycle on and connected, type the average fuel figure shown on the dash (km/L), then Search. If there are several candidates, repeat once the dash figure has changed: the correct byte changes too. If nothing matches, the average fuel figure may be in another data packet (see Raw CCU data in Settings > Connection)."))) {
                TextField(tr("Average fuel on the dash (km/L)"), text: $fuelTarget)
                    .keyboardType(.decimalPad)
                Button(tr("Search byte")) {
                    let t = Double(fuelTarget.replacingOccurrences(of: ",", with: ".")) ?? 0
                    fuelCands = live.fuelByteCandidates(target: t)
                    fuelSearched = true
                }
                if fuelSearched && fuelCands.isEmpty {
                    Text(live.rawRecord.isEmpty ? tr("No CCU data yet.") : tr("No matching byte."))
                        .font(.footnote).foregroundColor(.secondary)
                }
                ForEach(fuelCands) { c in
                    Button(c.text) {
                        settings.ccuFuelByte = c.byte
                        settings.ccuFuelWide = c.wide
                        settings.ccuFuelUnit = c.unit
                        settings.ccuFuelDiv = c.div
                    }
                    .font(.footnote)
                }
            }
        }
        .navigationTitle(tr("Motorcycle and fuel"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingPhoto) {
            PhotoPicker(limit: 1) { imgs in
                if let i = imgs.first { vehicle.setPhoto(i) }
            }
        }
    }
}

struct ControlSettings: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text(tr("Up/down buttons on the handlebar")),
                    footer: Text(tr("Up (+) and down (−) buttons on the motorcycle handlebar. A single press runs immediately without waiting. Three quick presses on the same button = switch screen: up goes to the next screen, down to the previous one (the zoom from the first two clicks is undone automatically). The Music screen has its own rules (see the bottom section)."))) {
                HStack {
                    Text(tr("1 press"))
                    Spacer()
                    Text(tr("Map zoom")).foregroundColor(.secondary)
                }
                HStack {
                    Text(tr("2 quick presses"))
                    Spacer()
                    Text(tr("Zoom again")).foregroundColor(.secondary)
                }
                HStack {
                    Text(tr("3 quick presses"))
                    Spacer()
                    Text(tr("Switch screen")).foregroundColor(.secondary)
                }
            }
            Section(header: Text(tr("Quick-click duration")),
                    footer: Text(tr("The longest time between two presses to count as one quick-click sequence (2x/3x). Raise it if pressing that fast is hard, lower it if some normal presses are read as quick clicks. On the Music screen, a track only changes after a pause of this length, because a 3rd click means switch screen. Every press is logged with its time difference."))) {
                sliderRow(tr("Quick-click duration"), value: Binding(
                    get: { Double(settings.doubleClickMs) },
                    set: { settings.doubleClickMs = Int($0) }), range: 250...1500, step: 50, unit: "ms")
            }
            Section(header: Text(tr("Button gestures (Music screen)")),
                    footer: Text(tr("Music screen only: 1 press = volume (up raises, down lowers). 2 quick presses = next track (up) or previous (down). 3 quick presses = switch screen. Up then down quickly, or down then up, = play/pause. When turned off, the Music screen only has volume (1x, 2x) and switch screen (3x). Press-and-hold is not supported because the dash sends nothing while a button is held. Media & Apple Music permission must be granted."))) {
                Toggle(tr("Enable music gestures on the handlebar"), isOn: $settings.holdSkip)
            }
        }
        .navigationTitle(tr("Motorcycle controls"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pratinjau layar dash di halaman pengaturan (ikut tampil di dash asli bila terhubung).
/// Tanpa bar atas dan bar bawah; panah ganti layar hanya bila `arrows` true (halaman Layar dasbor).
struct DashPreviewBox: View {
    @EnvironmentObject var bike: BikeController
    var arrows = false

    var body: some View {
        VStack(spacing: 6) {
            DashScreenOnlyView()
                .cornerRadius(8)
            if arrows {
                HStack {
                    Button { bike.stepScreen(forward: false) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text(tr("{0} · {1} of {2}", bike.currentScreen.title, min(bike.screenIndex, bike.screens().count - 1) + 1, bike.screens().count))
                        .font(.footnote)
                    Spacer()
                    Button { bike.stepScreen(forward: true) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// Menyalakan pratinjau dash selama halaman pengaturan terbuka (gambar ikut berubah saat pengaturan digeser).
/// `demoNav`: tampilkan contoh panel navigasi. `focus`: pindah ke layar ini bila aktif.
struct DashPreviewLifecycle: ViewModifier {
    @EnvironmentObject var bike: BikeController
    var demoNav = false
    var focus: DashScreen? = nil
    /// true: pratinjau dikunci ke layar `focus` (tidak bisa diganti dari halaman ini)
    var lock = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                bike.previewLockScreen = lock ? focus : nil
                bike.demoNav = demoNav
                if let f = focus { bike.showScreen(f) }
                bike.setPreviewVisible(true, owner: "pengaturan")
            }
            .onDisappear {
                bike.previewLockScreen = nil
                bike.demoNav = false
                bike.previewSpeedOverride = nil
                bike.setPreviewVisible(false, owner: "pengaturan")
            }
    }
}

extension View {
    /// Pratinjau dash tetap di atas layar (tidak ikut tergulir); hanya isi di bawahnya yang tergulir.
    func dashPinnedPreview(hint: String? = nil, arrows: Bool = false) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 4) {
                DashPreviewBox(arrows: arrows).frame(maxWidth: 340)
                if let h = hint {
                    Text(h).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .overlay(Divider(), alignment: .bottom)
        }
    }

    func dashPreviewLifecycle(demoNav: Bool = false, focus: DashScreen? = nil, lock: Bool = false) -> some View {
        modifier(DashPreviewLifecycle(demoNav: demoNav, focus: focus, lock: lock))
    }
}

struct MapSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController
    @ObservedObject private var offline = OfflineMapStore.shared

    var body: some View {
        Form {
            Section(footer: Text(tr("Download the areas you pass often so the dash map still shows without a mobile network."))) {
                NavigationLink(destination: OfflineMapView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill").foregroundColor(.accentColor).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Offline maps"))
                            Text(offline.areas.isEmpty
                                 ? tr("No areas downloaded yet")
                                 : tr("{0} areas · {1}", offline.areas.count, OfflineMapStore.mbText(offline.totalBytes)))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section {
                NavigationLink(destination: RouteSettings()) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond").foregroundColor(.accentColor).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Routes and search")).font(.headline)
                            Text(tr("Route profile, voice guidance, routing server")).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section(header: Text(tr("Day/night")),
                    footer: Text(tr("Automatic: the map switches to the night theme at 18:00 and back to the day theme at 06:00."))) {
                Picker(tr("Day/night"), selection: $settings.nightMode) {
                    Text(tr("Automatic (night 18:00-06:00)")).tag(0)
                    Text(tr("Always day")).tag(1)
                    Text(tr("Always night")).tag(2)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section(header: Text(tr("Map zoom")),
                    footer: Text(tr("Zoom: the bigger the number, the closer the view. When auto zoom is on, zoom follows the GPS speed, whether navigating or not: the matching \"below X km/h\" rule is used, and speeds above all rules use the \"above the last limit\" zoom. The order of the rules does not matter. Zoom changes are smoothed over the time you set. The handlebar up/down buttons still add/subtract zoom on top of this result. The preview above changes as the settings are moved."))) {
                Toggle(tr("Auto zoom by speed"), isOn: $settings.autoZoom)
                if !settings.autoZoom {
                    sliderRow(tr("Map zoom"), value: $settings.baseZoom, range: 13...19.5, step: 0.1, unit: "")
                }
                if settings.autoZoom {
                    sliderRow(tr("Zoom transition smoothness"), value: $settings.zoomSmooth, range: 0...3, step: 0.1, unit: tr("s"))
                }
            }
            if settings.autoZoom {
                Section(header: Text(tr("Auto zoom rules"))) {
                    ForEach($settings.zoomRules) { $rule in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tr("Below {0} km/h → zoom {1}", Int(rule.below), String(format: "%.1f", rule.zoom)))
                                    .font(.subheadline).bold()
                                Spacer()
                                Button {
                                    let id = rule.id
                                    settings.zoomRules.removeAll { $0.id == id }
                                } label: { Image(systemName: "trash").foregroundColor(.red) }
                                    .buttonStyle(.borderless)
                            }
                            sliderRow(tr("Speed below"), value: $rule.below, range: 1...150, step: 1, unit: tr("km/h"))
                            sliderRow(tr("Zoom"), value: $rule.zoom, range: 13...19.5, step: 0.1, unit: "")
                        }
                        .padding(.vertical, 2)
                    }
                    sliderRow(tr("Above the last limit: zoom"), value: $settings.zoomAbove, range: 13...19.5, step: 0.1, unit: "")
                    Button {
                        let last = settings.zoomRules.max(by: { $0.below < $1.below })
                        let below = min(150, (last?.below ?? 0) + 20)
                        let zoom = max(13, min(19.5, (last?.zoom ?? 17.5) - 0.5))
                        settings.zoomRules.append(ZoomRule(below: below, zoom: zoom))
                    } label: { Label(tr("Add rule"), systemImage: "plus.circle.fill") }
                    .disabled(settings.zoomRules.count >= 10)
                    Button(tr("Restore default rules")) {
                        settings.zoomRules = ZoomRule.defaults
                        settings.zoomAbove = 15.6
                    }
                }
                Section(header: Text(tr("Test in the preview")),
                        footer: Text(tr("Use an artificial speed to see the zoom of each rule in the preview (and on the dash when connected). It goes away automatically when this page is closed."))) {
                    Toggle(tr("Artificial speed"), isOn: Binding(
                        get: { bike.previewSpeedOverride != nil },
                        set: { bike.previewSpeedOverride = $0 ? (bike.previewSpeedOverride ?? 0) : nil }))
                    if let v = bike.previewSpeedOverride {
                        sliderRow(tr("Speed"), value: Binding(get: { v }, set: { bike.previewSpeedOverride = $0 }),
                                  range: 0...120, step: 1, unit: tr("km/h"))
                    }
                }
            }
            Section(header: Text(tr("Route")),
                    footer: Text(bike.demoRouteStatus.isEmpty
                                 ? tr("The sample line in the preview follows real roads around your position, so you can try the width and border right away.")
                                 : bike.demoRouteStatus)) {
                Picker(tr("Route color"), selection: $settings.routeColor) {
                    Text(tr("Pink")).tag(0)
                    Text(tr("Blue")).tag(1)
                    Text(tr("Green")).tag(2)
                }
                sliderRow(tr("Route line width"), value: $settings.routeWidth, range: 2...10, step: 0.5, unit: "px")
                sliderRow(tr("Route white border thickness"), value: $settings.routeBorder, range: 0...4, step: 0.5, unit: "px")
            }
            Section(header: Text(tr("Bike marker"))) {
                sliderRow(tr("Size"), value: $settings.markerSize, range: 0.5...2, step: 0.1, unit: "x")
                Toggle(tr("Circle around the marker"), isOn: $settings.markerRing)
                sliderRow(tr("Position (up ↔ down)"), value: $settings.markerY, range: 0.35...0.9, step: 0.01, unit: "")
                sliderRow(tr("Position (left ↔ right)"), value: $settings.markerX, range: -120...120, step: 2, unit: "px")
            }
            Section(header: Text(tr("Direction box (green, turn icon)"))) {
                sliderRow(tr("Size"), value: $settings.navPanelScale, range: 0.6...1.4, step: 0.05, unit: "x")
                sliderRow(tr("Shift left ↔ right"), value: $settings.navDX, range: -8...280, step: 2, unit: "px")
                sliderRow(tr("Shift up ↔ down"), value: $settings.navDY, range: -4...110, step: 2, unit: "px")
            }
            Section(header: Text(tr("Estimate box (distance and time)")),
                    footer: Text(tr("Choose the data shown in the estimate box. If all are turned off, the box is hidden."))) {
                Toggle(tr("Distance estimate (remaining distance)"), isOn: $settings.etaShowDistance)
                Toggle(tr("Trip duration estimate (remaining time)"), isOn: $settings.etaShowDuration)
                Toggle(tr("Arrival time estimate (arrival clock)"), isOn: $settings.etaShowArrival)
                if settings.etaShowDistance || settings.etaShowDuration || settings.etaShowArrival {
                    sliderRow(tr("Size"), value: $settings.etaScale, range: 0.6...1.4, step: 0.05, unit: "x")
                    sliderRow(tr("Shift left ↔ right"), value: $settings.etaDX, range: -54...300, step: 2, unit: "px")
                    sliderRow(tr("Shift up ↔ down"), value: $settings.etaDY, range: -140...4, step: 2, unit: "px")
                }
            }
            Section(footer: Text(tr("The street name is shown in the bottom bar of the dash (from GPS when not navigating, from the route when navigating)."))) {
                Toggle(tr("Street name in the dash bottom bar"), isOn: $settings.showRoadName)
                Button(tr("Reset positions to default")) {
                    settings.markerY = 0.68
                    settings.markerX = 0
                    settings.navDX = 0
                    settings.navDY = 0
                    settings.etaDX = 0
                    settings.etaDY = 0
                    settings.navPanelScale = 1
                    settings.etaScale = 1
                }
            }
        }
        .navigationTitle(tr("Map"))
        .navigationBarTitleDisplayMode(.inline)
        .dashPinnedPreview(hint: tr("A sample navigation panel and route line (following the roads around you) show while this page is open."))
        .dashPreviewLifecycle(demoNav: true, focus: .mapData, lock: true)
    }
}

func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: "%g", (value.wrappedValue * 100).rounded() / 100) + (unit.isEmpty ? "" : " " + unit))
                .foregroundColor(.secondary)
        }
        Slider(value: value, in: range, step: step)
    }
}

struct CardSettings: View {
    @EnvironmentObject var settings: AppSettings

    private func fieldPicker(_ title: String, _ sel: Binding<Int>) -> some View {
        Picker(title, selection: sel) {
            ForEach(DashField.selectable, id: \.rawValue) { f in Text(f.title).tag(f.rawValue) }
        }
    }

    var body: some View {
        Form {
            Section(header: Text(tr("Layout"))) {
                Picker(tr("Layout"), selection: $settings.cardLayout) {
                    Text(tr("1 large + 2 small")).tag(0)
                    Text(tr("1 large + 4 small")).tag(1)
                    Text(tr("4 small")).tag(2)
                }
                sliderRow(tr("Column background darkness (0 = transparent)"), value: $settings.cardBgAlpha, range: 0...1, step: 0.05, unit: "")
            }
            Section(header: Text(tr("Card contents"))) {
                if settings.cardLayout != 2 { fieldPicker(tr("Large card"), $settings.cardBig) }
                fieldPicker(tr("Small 1"), $settings.cardS1)
                fieldPicker(tr("Small 2"), $settings.cardS2)
                if settings.cardLayout != 0 {
                    fieldPicker(tr("Small 3"), $settings.cardS3)
                    fieldPicker(tr("Small 4"), $settings.cardS4)
                }
            }
            Section(header: Text(tr("Font size")),
                    footer: Text(tr("1 = default size. Text shrinks automatically when the card content is too long, so it never spills out of the card."))) {
                sliderRow(tr("Large card"), value: $settings.cardFontBig, range: 0.5...1.5, step: 0.05, unit: "x")
                sliderRow(tr("Small cards"), value: $settings.cardFontSmall, range: 0.5...1.5, step: 0.05, unit: "x")
                Button(tr("Reset font size")) {
                    settings.cardFontBig = 1
                    settings.cardFontSmall = 1
                }
            }
        }
        .navigationTitle(tr("Data Cards"))
        .navigationBarTitleDisplayMode(.inline)
        .dashPinnedPreview(hint: settings.showCards
                           ? tr("Map screen preview; changes below show immediately.")
                           : tr("Data Cards are turned off. Turn them on in Settings > Dash screens > Data Cards."))
        .dashPreviewLifecycle(focus: .mapData, lock: true)
    }
}

struct ScreensSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var slides: SlideshowStore
    @EnvironmentObject var music: MusicService
    @EnvironmentObject var bike: BikeController
    @State private var picking = false

    private func infoPicker(_ title: String, _ sel: Binding<Int>) -> some View {
        Picker(title, selection: sel) {
            ForEach(DashField.selectable, id: \.rawValue) { f in Text(f.title).tag(f.rawValue) }
        }
    }

    /// Layar selain Peta menurut urutan sekarang (Peta selalu pertama dan tidak ikut diurutkan).
    private var otherScreens: [DashScreen] {
        settings.orderedScreens.filter { $0 != .mapData }
    }

    private func binding(_ s: DashScreen) -> Binding<Bool> {
        Binding(
            get: { settings.screenMask & (1 << s.rawValue) != 0 },
            set: { on in
                if on { settings.screenMask |= (1 << s.rawValue) } else { settings.screenMask &= ~(1 << s.rawValue) }
                if on { bike.showScreen(s) }
                // layar awal yang baru dimatikan kembali ke Peta
                if !on && settings.startScreen == s.rawValue { settings.startScreen = 0 }
            })
    }

    /// Foto hanya bisa aktif bila ada foto: bila foto habis, saklarnya otomatis mati (dan layar awal kembali ke Peta).
    private func syncSlideshowToggle() {
        guard slides.files.isEmpty else { return }
        let bit = 1 << DashScreen.slideshow.rawValue
        if settings.screenMask & bit != 0 { settings.screenMask &= ~bit }
        if settings.startScreen == DashScreen.slideshow.rawValue { settings.startScreen = 0 }
    }

    /// Pilihan layar awal hanya Peta dan layar lain yang aktif.
    private var startBinding: Binding<Int> {
        Binding(
            get: { settings.enabledScreens.contains { $0.rawValue == settings.startScreen } ? settings.startScreen : 0 },
            set: { settings.startScreen = $0 })
    }

    var body: some View {
        Form {
            Section(header: Text(tr("Screens selectable with the handlebar buttons")),
                    footer: Text(tr("Map is always on and always first. Tap Edit at the top right, then drag to reorder the other screens; this order is used by the handlebar buttons. The Photos screen can only be turned on once there are photos. The preview jumps to the screen you turn on or drag."))) {
                Toggle(tr("Map"), isOn: .constant(true)).disabled(true)
                ForEach(otherScreens, id: \.rawValue) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(s.title, isOn: binding(s))
                            .disabled(s == .slideshow && slides.files.isEmpty)
                        if s == .slideshow && slides.files.isEmpty {
                            Text(tr("No photos yet, so it cannot be turned on. Add photos in the Photos section below."))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .onMove { from, to in
                    var list = otherScreens
                    let moved = from.first.map { list[$0] }
                    list.move(fromOffsets: from, toOffset: to)
                    settings.setScreenOrder(list)
                    if let m = moved { bike.showScreen(m) }      // pratinjau ikut ke layar yang digeser
                }
            }
            Section(header: Text(tr("When the motorcycle is switched on")),
                    footer: Text(tr("The screen shown first on the dash after connecting, without opening the app. The choices are Map and the other active screens."))) {
                Picker(tr("Start screen"), selection: startBinding) {
                    ForEach(settings.enabledScreens, id: \.rawValue) { sc in Text(sc.title).tag(sc.rawValue) }
                }
            }
            Section(header: Text(tr("Data Cards")),
                    footer: Text(tr("Weather, fuel, and motorcycle data cards on the right side of the Map screen. Their contents and layout are set in Settings > Data Cards."))) {
                Toggle(tr("Show Data Cards"), isOn: $settings.showCards)
            }
            Section(header: Text(tr("Speedometer")),
                    footer: Text(tr("Data in the top left/right corners of the Speedometer screen, or Empty to hide it."))) {
                infoPicker(tr("Left corner"), $settings.infoDashL)
                infoPicker(tr("Right corner"), $settings.infoDashR)
            }
            Section(header: Text(tr("Music")),
                    footer: Text(tr("Only songs from the Music app (Apple Music) can be read. Spotify and other apps do not share their track info on iOS."))) {
                if music.authorized {
                    Label(tr("Music access allowed"), systemImage: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Button(tr("Allow music access")) { music.requestAccess() }
                }
                Toggle(tr("Blurred cover background"), isOn: $settings.musicBlurBG)
                infoPicker(tr("Left corner"), $settings.infoMusicL)
                infoPicker(tr("Right corner"), $settings.infoMusicR)
            }
            Section(header: Text(tr("Photos")),
                    footer: Text(tr("Data in the left/right corners of the Photos screen, or Empty to hide it."))) {
                infoPicker(tr("Left corner"), $settings.infoPhotoL)
                infoPicker(tr("Right corner"), $settings.infoPhotoR)
                sliderRow(tr("Shift photo (up ↔ down)"), value: $settings.photoShift, range: -40...40, step: 1, unit: "px")
                Stepper(tr("Change photo every {0} seconds", settings.slideSeconds), value: $settings.slideSeconds, in: 2...60)
                Button(tr("Add photos")) { picking = true }
                if slides.files.isEmpty {
                    Text(tr("No photos yet")).foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(slides.files, id: \.self) { name in
                                ZStack(alignment: .topTrailing) {
                                    if let img = slides.image(for: name) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 96, height: 64).clipped().cornerRadius(8)
                                    }
                                    Button { slides.remove(name) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).background(Color.white.clipShape(Circle()))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("Dash screens"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { EditButton() } }
        .dashPinnedPreview(arrows: true)
        .dashPreviewLifecycle()
        .onAppear { syncSlideshowToggle() }
        .onChange(of: slides.files) { _ in syncSlideshowToggle() }
        .sheet(isPresented: $picking) {
            PhotoPicker(limit: 20) { imgs in slides.add(imgs) }
        }
    }
}

struct RouteSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nav: NavigationController
    @EnvironmentObject var bike: BikeController

    var body: some View {
        Form {
            Section(header: Text(tr("Route profile")),
                    footer: Text(tr("Read every time a route is calculated or recalculated. Valhalla's default for scooters avoids main roads and limits speed to 45 km/h, so routes detour and take long. The speed limit affects the time estimate, not how fast you ride."))) {
                sliderRow(tr("Main roads"), value: $settings.routePrimary, range: 0...1, step: 0.1, unit: "")
                Text(tr("0 = avoid main roads, 1 = prefer main roads")).font(.caption).foregroundColor(.secondary)
                Stepper(tr("Maximum speed limit {0} km/h", settings.routeTopSpeed), value: $settings.routeTopSpeed, in: 20...120, step: 5)
                sliderRow(tr("Hills"), value: $settings.routeHills, range: 0...1, step: 0.1, unit: "")
                Text(tr("0 = avoid hills, 1 = no problem")).font(.caption).foregroundColor(.secondary)
                sliderRow(tr("Alleys and residential streets"), value: $settings.routeLiving, range: 0...1, step: 0.1, unit: "")
                sliderRow(tr("Footpaths / unpaved roads"), value: $settings.routeTrails, range: 0...1, step: 0.1, unit: "")
                sliderRow(tr("Ferries"), value: $settings.routeFerry, range: 0...1, step: 0.1, unit: "")
                Toggle(tr("Shortest route (distance), not the fastest"), isOn: $settings.routeShortest)
                Button(tr("Use XConnect default (main roads, 80 km/h)")) { settings.applyRouteProfile(.appDefault) }
                Button(tr("Use Valhalla default (45 km/h)")) { settings.applyRouteProfile(.valhallaScooter) }
            }
            Section(header: Text(tr("Voice guidance")),
                    footer: Text(tr("Example: \"In 100 meters, turn right onto Main Street\". While the voice plays, music from other apps is lowered automatically by iOS and then returns to normal. The iPhone master volume is not changed, and the amount of lowering is decided by iOS (it cannot be set as a percentage). The voice comes out of the active audio output (speaker, headset, or the motorcycle Bluetooth)."))) {
                Toggle(tr("Voice prompts"), isOn: $settings.guideVoice)
                if settings.guideVoice {
                    Toggle(tr("Lower the music volume while speaking"), isOn: $settings.guideDuck)
                    sliderRow(tr("Voice volume"), value: $settings.guideVolume, range: 0.2...1, step: 0.1, unit: "")
                    sliderRow(tr("Voice booster"), value: $settings.guideBoostDb, range: 0...18, step: 3, unit: "dB")
                    Text(tr("The booster makes the guidance voice louder than full volume (+6 dB is roughly twice as loud, +12 dB four times). Start at +6 dB, then raise it if it is still too quiet. If it sounds distorted, lower it. Use Try voice to test."))
                        .font(.caption).foregroundColor(.secondary)
                    Button(tr("Try voice")) { bike.nearestStreet { nav.voice?.test(street: $0) } }
                }
            }
            Section(header: Text(tr("Routing server")),
                    footer: Text(tr("The Valhalla demo server (FOSSGIS) is free but only for reasonable use. For regular use, run your own Valhalla server and enter its address here."))) {
                TextField("https://…", text: $settings.routingBase)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
        }
        .navigationTitle(tr("Routes and search"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CcuRawView: View {
    @EnvironmentObject var live: VehicleLive
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text(tr("Data packet id 1 (byte by byte)")),
                    footer: Text(tr("Each byte value updates live. Change the motorcycle state (throttle, lights, side stand) and see which byte changes. Known bytes: 0-1 RPM, 2 speed, 6 12V battery, 14 engine temp, 15 air temp, 23 fault codes. Each byte can be chosen as a data card (\"CCU byte n\")."))) {
                if live.rawRecord.isEmpty {
                    Text(tr("No data yet. Connect to the motorcycle with CCU enabled.")).foregroundColor(.secondary)
                } else {
                    ForEach(0..<live.rawRecord.count, id: \.self) { i in
                        HStack {
                            Text(tr("Byte {0}", i))
                            Spacer()
                            Text("\(live.rawRecord[i])  (0x" + String(format: "%02X", live.rawRecord[i]) + ")")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section(header: Text(tr("Other data IDs")), footer: Text(tr("Extra IDs subscribed to and received from the CCU."))) {
                if live.rawById.isEmpty {
                    Text(tr("None yet")).foregroundColor(.secondary)
                }
                ForEach(live.rawById.keys.sorted(), id: \.self) { id in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ID \(id)").font(.footnote)
                        Text((live.rawById[id] ?? []).prefix(40).map { String(format: "%02x", $0) }.joined(separator: " "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section(header: Text(tr("Experiment: extra ID subscriptions")),
                    footer: Text(tr("Separate with commas, e.g. 2, 3. Applies when the CCU session restarts (switch the motorcycle off and on). IDs unknown to the CCU may cause the subscription to be rejected: clear it again if data stops."))) {
                TextField(tr("e.g. 2, 3"), text: $settings.ccuExtraIds)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle(tr("Raw CCU data"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DebugSettings: View {
    /// true = tampilkan bagian eksperimen Link CCU dan Bahasa dash
    private static let showHiddenExperiments = false
    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            // Disembunyikan (bukan dihapus): ubah ke true bila eksperimen ini diperlukan lagi.
            if Self.showHiddenExperiments {
                Section(header: Text(tr("CCU link (experiment)")),
                        footer: Text(tr("Opens the com.yconnect.data session and logs all incoming bytes, to learn how to read the odometer and motorcycle data on the iPhone."))) {
                    Button(tr("Run CCU probe")) { bike.runCcuProbe() }
                    Button(tr("Stop CCU probe")) { bike.stopCcuProbe() }
                    Text(bike.vehicleLive.state).font(.footnote).foregroundColor(.secondary)
                }
                Section(header: Text(tr("Dash language (experiment)")),
                        footer: Text(tr("The dash asks the app for its language through the CCU. The code sent follows the language chosen in Settings > Appearance (see Translations.tsv, row @dashLang); enter a code here to override it, or -1 to follow the app language. Known codes: 0 = English, 11 = Indonesian, 15 = Vietnamese. Try a code, switch the ignition off and on, and watch the dash clock and default texts. Codes rejected by the CCU are logged as CCU: error. Return to -1 if the dash looks odd."))) {
                    Toggle(tr("Send the app language to the dash"), isOn: $settings.dashLangSync)
                    Stepper(settings.dashLang < 0 ? tr("Language code: from app language") : tr("Language code: {0}", settings.dashLang),
                            value: $settings.dashLang, in: -1...63)
                }
            }
            Section(header: Text(tr("Log"))) {
                Button(tr("Copy log")) { UIPasteboard.general.string = bike.logLines.joined(separator: "\n") }
                NavigationLink(tr("View log")) { LogView() }
            }
        }
        .navigationTitle(tr("Experiments and log"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var updater: UpdateService

    var body: some View {
        Form {
            Section(footer: Text(tr("Map © OpenStreetMap contributors, OpenFreeMap (OpenMapTiles). Search: Photon. Gas stations: Overpass API. Weather: Open-Meteo. Routing: Valhalla."))) {
                HStack(spacing: 14) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("XConnect").font(.headline)
                        Text(tr("Version {0}", UpdateService.currentVersion)).font(.footnote).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                NavigationLink(destination: WhatsNewView()) {
                    Label(tr("What's new in this version"), systemImage: "sparkles")
                }
                NavigationLink(destination: BackupSettings()) {
                    Label(tr("Backup and restore"), systemImage: "externaldrive")
                }
                NavigationLink(destination: DebugSettings()) {
                    Label(tr("Experiments and log"), systemImage: "ladybug")
                }
            }
            Section(header: Text(tr("Version and updates"))) {
                HStack { Text(tr("Installed")); Spacer(); Text("\(UpdateService.currentVersion)").foregroundColor(.secondary) }
                if let l = updater.latest {
                    HStack { Text(tr("Latest")); Spacer(); Text(l.name).foregroundColor(.secondary) }
                }
                if !updater.message.isEmpty { Text(updater.message).font(.footnote).foregroundColor(.secondary) }
            }
            Section {
                Toggle(tr("Check automatically when the app opens"), isOn: $settings.autoCheckUpdate)
                Button(updater.checking ? tr("Checking…") : tr("Check for updates now")) {
                    updater.check(repo: settings.updateRepo)
                }.disabled(updater.checking)
            }
            if updater.updateAvailable {
                Section(header: Text(tr("Update available"))) {
                    if let n = updater.latest?.notes, !n.isEmpty { Text(n).font(.footnote) }
                    Picker(tr("Install with"), selection: $settings.updater) {
                        Text("SideStore").tag(0)
                        Text("AltStore").tag(1)
                        Text("LiveContainer").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Button(tr("Install update")) { updater.install(using: settings.updater) }
                    Button(tr("Add source to {0} (recommended)", UpdateService.storeName(settings.updater))) {
                        updater.addSource(repo: settings.updateRepo, using: settings.updater)
                    }
                    Button(tr("Open download page")) { updater.openDownloadPage() }
                }
            }
        }
        .navigationTitle(tr("About"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LogView: View {
    @EnvironmentObject var bike: BikeController

    var body: some View {
        List {
            ForEach(bike.logLines.indices.reversed(), id: \.self) { i in
                Text(bike.logLines[i]).font(.system(size: 11, design: .monospaced))
            }
        }
        .listStyle(.plain)
        .navigationTitle(tr("Log"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BackupSettings: View {
    @EnvironmentObject var settings: AppSettings
    @State private var exporting = false
    @State private var importing = false
    @State private var doc = SettingsBackupDocument()
    @State private var message = ""

    var body: some View {
        Form {
            Section(footer: Text(tr("The backup contains all app settings (appearance, connection, dash screens, Data Cards, map, buttons, routes, updates), saved places (Home, Office and favorites are saved too; only the Recent places are not saved), motorcycle data (name, type, photo, tank), maintenance and its history, fuel records, and trip history. Slideshow photos and offline maps are not included because of their size."))) {
                Button(tr("Save backup to a file")) {
                    doc = SettingsBackupDocument(data: settings.exportBackup())
                    exporting = true
                }
                .fileExporter(isPresented: $exporting, document: doc, contentType: .json,
                              defaultFilename: "XConnect_setting") { result in
                    switch result {
                    case .success: message = tr("Backup saved.")
                    case .failure(let e): message = tr("Failed to save: {0}", e.localizedDescription)
                    }
                }
                Button(tr("Restore from a backup file")) { importing = true }
                    .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text, .data]) { result in
                        switch result {
                        case .success(let url):
                            let ok = url.startAccessingSecurityScopedResource()
                            defer { if ok { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url), let n = settings.importBackup(data) {
                                message = tr("Settings restored ({0} items).", n)
                            } else {
                                message = tr("This file is not a valid XConnect backup.")
                            }
                        case .failure(let e):
                            message = tr("Failed to open file: {0}", e.localizedDescription)
                        }
                    }
                if !message.isEmpty { Text(message).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle(tr("Backup and restore"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

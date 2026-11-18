import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var vehicle: VehicleStore

    var body: some View {
        NavigationView {
            List {
                row("Tampilan", subtitle: ["Ikuti ponsel", "Gelap", "Terang"][min(2, settings.theme)], icon: "paintpalette") {
                    AppearanceSettings()
                }
                row("Motor dan koneksi", subtitle: "\(vehicle.model) · sambung otomatis \(settings.autoConnect ? "nyala" : "mati")",
                    icon: "bicycle") {
                    ConnectionSettings()
                }
                row("Kontrol pada motor", subtitle: settings.buttonScheme == 1
                    ? "Tekan 2x tombol atas/bawah: ganti tampilan"
                    : "Tombol atas/bawah: ganti tampilan, 2x untuk zoom", icon: "hand.tap") {
                    ControlSettings()
                }
                row("Peta di dasbor", subtitle: "Siang/malam, zoom otomatis, warna rute", icon: "map") {
                    MapSettings()
                }
                row("Layar dasbor", subtitle: "\(bike.screens().count) layar aktif · kartu info · foto · musik",
                    icon: "rectangle.on.rectangle") {
                    ScreensSettings()
                }
                row("Kotak data", subtitle: "Isi kotak di dash: CCU, HP, tata letak", icon: "square.grid.2x2") {
                    CardSettings()
                }
                row("Rute dan pencarian", subtitle: "Jenis kendaraan, server routing", icon: "arrow.triangle.turn.up.right.diamond") {
                    RouteSettings()
                }
                row("Eksperimen dan log", subtitle: "Probe link CCU, log sambungan", icon: "ladybug") {
                    DebugSettings()
                }
                row("Cadangkan dan pulihkan", subtitle: "Simpan/pulihkan semua pengaturan ke file", icon: "externaldrive") {
                    BackupSettings()
                }
                row("Update aplikasi", subtitle: "Cek versi terbaru di GitHub", icon: "arrow.down.circle") {
                    UpdateSettings()
                }
                row("Tentang", subtitle: "XConnect \(UpdateService.currentVersion) (build \(UpdateService.currentBuild))", icon: "info.circle") {
                    AboutSettings()
                }
            }
            .navigationTitle("Pengaturan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private func row<D: View>(_ title: String, subtitle: String, icon: String,
                              @ViewBuilder destination: () -> D) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundColor(.blue).frame(width: 28)
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
            Picker("Tema aplikasi", selection: $settings.theme) {
                Text("Ikuti ponsel").tag(0)
                Text("Gelap").tag(1)
                Text("Terang").tag(2)
            }
            .pickerStyle(.inline)
            TextField("Nama panggilan (tampil di dash)", text: $settings.userName)
        }
        .navigationTitle("Tampilan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConnectionSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var vehicle: VehicleStore

    var body: some View {
        Form {
            Section(footer: Text("Aplikasi tetap hidup di latar belakang (lokasi 'Selalu') supaya bisa menyambung saat motor dinyalakan, bahkan saat ponsel terkunci. Jangan tutup paksa aplikasi dari daftar app.")) {
                Toggle("Sambung otomatis", isOn: $settings.autoConnect)
                Button("Pasangkan dash (Bluetooth)") { bike.showPairingPicker() }
            }
            Section(footer: Text("Hemat baterai menurunkan frame rate dash (maks 4 fps).")) {
                Toggle("Hemat baterai", isOn: $settings.saveBattery)
                Toggle("Jaga layar tetap menyala saat terhubung", isOn: $settings.keepScreenOn)
            }
            Section(header: Text("Motor")) {
                TextField("Nama motor", text: $vehicle.name)
                TextField("Model", text: $vehicle.model)
                Stepper("Kapasitas tangki \(Fmt.liters(vehicle.tankL))", value: $vehicle.tankL, in: 3...30, step: 0.1)
                Stepper("Konsumsi bawaan \(Fmt.km(settings.defaultKmPerL)) km/L", value: $settings.defaultKmPerL,
                        in: 10...80, step: 0.5)
            }
        }
        .navigationTitle("Motor dan koneksi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ControlSettings: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text("Tombol atas/bawah di stang"),
                    footer: Text("Tombol atas (+) = tampilan berikutnya, tombol bawah (−) = tampilan sebelumnya. Pengaturan ini menentukan mana yang dipakai untuk satu tekan dan mana untuk dua tekan cepat.")) {
                Picker("Skema", selection: $settings.buttonScheme) {
                    Text("Tekan 2x: ganti tampilan · 1x: zoom").tag(1)
                    Text("Tekan 1x: ganti tampilan · 2x: zoom").tag(0)
                }
                .pickerStyle(.inline)
            }
            Section(footer: Text("Aksi tekan 1x selalu menunggu sekitar setengah detik untuk memastikan tidak ada tekan kedua.")) {
                EmptyView()
            }
        }
        .navigationTitle("Kontrol pada motor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MapSettings: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text("Tema peta")) {
                Picker("Siang/malam", selection: $settings.nightMode) {
                    Text("Otomatis (malam 18.00-05.00)").tag(0)
                    Text("Selalu siang").tag(1)
                    Text("Selalu malam").tag(2)
                }
                .pickerStyle(.inline)
            }
            Section(header: Text("Rute")) {
                Picker("Warna rute", selection: $settings.routeColor) {
                    Text("Merah muda").tag(0)
                    Text("Biru").tag(1)
                    Text("Hijau").tag(2)
                }
                Toggle("Zoom otomatis menurut kecepatan", isOn: $settings.autoZoom)
                sliderRow("Lebar garis rute", value: $settings.routeWidth, range: 2...10, step: 0.5, unit: "px")
                sliderRow("Tebal tepi putih rute", value: $settings.routeBorder, range: 0...4, step: 0.5, unit: "px")
            }
            Section(header: Text("Titik motor")) {
                sliderRow("Ukuran", value: $settings.markerSize, range: 0.5...2, step: 0.1, unit: "x")
                Toggle("Lingkaran di sekitar titik", isOn: $settings.markerRing)
                sliderRow("Posisi (atas ↔ bawah)", value: $settings.markerY, range: 0.35...0.9, step: 0.01, unit: "")
            }
            Section(header: Text("Panel belokan, jarak dan ETA")) {
                sliderRow("Ukuran panel belokan", value: $settings.navPanelScale, range: 0.6...1.4, step: 0.05, unit: "x")
                sliderRow("Ukuran pil jarak + ETA", value: $settings.etaScale, range: 0.6...1.4, step: 0.05, unit: "x")
            }
        }
        .navigationTitle("Peta di dasbor")
        .navigationBarTitleDisplayMode(.inline)
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
    @EnvironmentObject var live: VehicleLive

    private func fieldPicker(_ title: String, _ sel: Binding<Int>) -> some View {
        Picker(title, selection: sel) {
            ForEach(DashField.allCases, id: \.rawValue) { f in Text(f.title).tag(f.rawValue) }
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Tata letak (layar Peta + data)")) {
                Picker("Tata letak", selection: $settings.cardLayout) {
                    Text("1 besar + 2 kecil").tag(0)
                    Text("1 besar + 4 kecil").tag(1)
                    Text("4 kecil").tag(2)
                }
                Toggle("Tampilkan kotak data", isOn: $settings.showCards)
            }
            Section(header: Text("Isi kotak")) {
                if settings.cardLayout != 2 { fieldPicker("Kotak besar", $settings.cardBig) }
                fieldPicker("Kecil 1", $settings.cardS1)
                fieldPicker("Kecil 2", $settings.cardS2)
                if settings.cardLayout != 0 {
                    fieldPicker("Kecil 3", $settings.cardS3)
                    fieldPicker("Kecil 4", $settings.cardS4)
                }
            }
            Section(header: Text("Musik")) {
                Toggle("Latar sampul blur", isOn: $settings.musicBlurBG)
            }
            Section(header: Text("Link CCU"), footer: Text("Data aki, ODO, suhu, RPM dibaca lewat Bluetooth ke CCU motor. Status: \(live.state)")) {
                Toggle("Baca data CCU", isOn: $settings.ccuEnabled)
                if let v = live.batteryV { Text("Aki: " + String(format: "%.1f V", v)) }
                if let o = live.odoKm { Text("ODO: " + String(format: "%.1f km", o)) }
                if let t = live.coolantC { Text("Suhu mesin: \(t) °C") }
            }
        }
        .navigationTitle("Kotak data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UpdateSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var updater: UpdateService

    var body: some View {
        Form {
            Section(header: Text("Versi"),
                    footer: Text("Update diambil dari GitHub Releases (workflow Actions menerbitkannya otomatis setiap build). iOS tidak mengizinkan app memasang IPA sendiri, jadi tombol Pasang membuka SideStore/AltStore dengan IPA terbaru: tinggal satu ketukan konfirmasi di sana.")) {
                HStack { Text("Terpasang"); Spacer(); Text("\(UpdateService.currentVersion) (build \(UpdateService.currentBuild))").foregroundColor(.secondary) }
                if let l = updater.latest {
                    HStack { Text("Terbaru"); Spacer(); Text(l.name).foregroundColor(.secondary) }
                }
                if !updater.message.isEmpty { Text(updater.message).font(.footnote).foregroundColor(.secondary) }
            }
            Section(header: Text("Sumber update")) {
                TextField("pemilik/nama-repo", text: $settings.updateRepo)
                    .autocapitalization(.none).disableAutocorrection(true)
                Toggle("Cek otomatis saat app dibuka", isOn: $settings.autoCheckUpdate)
                Button(updater.checking ? "Memeriksa…" : "Cek update sekarang") {
                    updater.check(repo: settings.updateRepo)
                }.disabled(updater.checking)
            }
            if updater.updateAvailable {
                Section(header: Text("Update tersedia")) {
                    if let n = updater.latest?.notes, !n.isEmpty { Text(n).font(.footnote) }
                    Picker("Pasang lewat", selection: $settings.updater) {
                        Text("SideStore").tag(0)
                        Text("AltStore").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Button("Pasang update") { updater.install(using: settings.updater) }
                    Button("Tambah sumber ke SideStore/AltStore (cara yang disarankan)") {
                        updater.addSource(repo: settings.updateRepo, using: settings.updater)
                    }
                    Button("Buka halaman unduhan") { updater.openDownloadPage() }
                }
            }
        }
        .navigationTitle("Update aplikasi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ScreensSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var slides: SlideshowStore
    @EnvironmentObject var music: MusicService
    @State private var picking = false

    private func infoPicker(_ title: String, _ sel: Binding<Int>) -> some View {
        Picker(title, selection: sel) {
            ForEach(DashField.allCases, id: \.rawValue) { f in Text(f.title).tag(f.rawValue) }
        }
    }

    private func binding(_ s: DashScreen) -> Binding<Bool> {
        Binding(
            get: { settings.screenMask & (1 << s.rawValue) != 0 },
            set: { on in
                if on { settings.screenMask |= (1 << s.rawValue) } else { settings.screenMask &= ~(1 << s.rawValue) }
            })
    }

    var body: some View {
        Form {
            Section(header: Text("Layar yang bisa dipilih dengan tombol stang"),
                    footer: Text("Slideshow foto hanya muncul bila ada foto.")) {
                ForEach(DashScreen.allCases, id: \.rawValue) { s in
                    Toggle(s.title, isOn: binding(s))
                }
                Toggle("Kartu cuaca/bensin di layar Peta + data", isOn: $settings.showCards)
            }
            Section(header: Text("Musik"),
                    footer: Text("Hanya lagu dari app Musik (Apple Music) yang bisa dibaca. Spotify dan app lain tidak membagikan info lagunya di iOS.")) {
                if music.authorized {
                    Label("Akses musik diizinkan", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Button("Izinkan akses musik") { music.requestAccess() }
                }
            }
            Section(header: Text("Info di pojok layar"),
                    footer: Text("Pilih data yang tampil di pojok kiri/kanan atas tiap layar, atau Kosong untuk menyembunyikannya.")) {
                infoPicker("Speedometer: kiri", $settings.infoDashL)
                infoPicker("Speedometer: kanan", $settings.infoDashR)
                infoPicker("Musik: kiri", $settings.infoMusicL)
                infoPicker("Musik: kanan", $settings.infoMusicR)
                infoPicker("Foto: kiri", $settings.infoPhotoL)
                infoPicker("Foto: kanan", $settings.infoPhotoR)
            }
            Section(header: Text("Foto slideshow")) {
                sliderRow("Geser foto (atas ↔ bawah)", value: $settings.photoShift, range: -40...40, step: 1, unit: "px")
                Stepper("Ganti foto tiap \(settings.slideSeconds) detik", value: $settings.slideSeconds, in: 2...60)
                Button("Tambah foto") { picking = true }
                if slides.files.isEmpty {
                    Text("Belum ada foto").foregroundColor(.secondary)
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
        .navigationTitle("Layar dasbor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            PhotoPicker(limit: 20) { imgs in slides.add(imgs) }
        }
    }
}

struct RouteSettings: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text("Kendaraan")) {
                Picker("Jenis rute", selection: $settings.costing) {
                    Text("Skuter (NMAX/XMAX)").tag("motor_scooter")
                    Text("Motor").tag("motorcycle")
                    Text("Mobil").tag("auto")
                }
            }
            Section(header: Text("Server routing"),
                    footer: Text("Server demo Valhalla (FOSSGIS) gratis tetapi hanya untuk pemakaian wajar. Untuk pemakaian rutin, jalankan server Valhalla sendiri dan isi alamatnya di sini.")) {
                TextField("https://…", text: $settings.routingBase)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
        }
        .navigationTitle("Rute dan pencarian")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DebugSettings: View {
    @EnvironmentObject var bike: BikeController

    var body: some View {
        Form {
            Section(header: Text("Link CCU (eksperimen)"),
                    footer: Text("Membuka sesi com.yconnect.data dan mencatat semua byte yang masuk ke log, untuk mempelajari cara membaca odometer dan data motor di iPhone.")) {
                Button("Jalankan probe CCU") { bike.runCcuProbe() }
                Button("Hentikan probe CCU") { bike.stopCcuProbe() }
                Text(bike.vehicleLive.state).font(.footnote).foregroundColor(.secondary)
            }
            Section(header: Text("Log")) {
                Button("Salin log") { UIPasteboard.general.string = bike.logLines.joined(separator: "\n") }
                NavigationLink("Lihat log") { LogView() }
            }
        }
        .navigationTitle("Eksperimen dan log")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutSettings: View {
    var body: some View {
        Form {
            Section(footer: Text("Peta © OpenStreetMap contributors, OpenFreeMap (OpenMapTiles). Pencarian: Photon. SPBU: Overpass API. Cuaca: Open-Meteo. Routing: Valhalla.")) {
                Text("XConnect 0.5.0")
            }
        }
        .navigationTitle("Tentang")
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
        .navigationTitle("Log")
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
            Section(footer: Text("Cadangan berisi semua pengaturan app (layar dash, kotak data, peta, tombol, update). Foto slideshow, favorit, dan riwayat perjalanan tidak ikut.")) {
                Button("Simpan cadangan ke file") {
                    doc = SettingsBackupDocument(data: settings.exportBackup())
                    exporting = true
                }
                .fileExporter(isPresented: $exporting, document: doc, contentType: .json,
                              defaultFilename: "XConnect-pengaturan") { result in
                    switch result {
                    case .success: message = "Cadangan tersimpan."
                    case .failure(let e): message = "Gagal menyimpan: \(e.localizedDescription)"
                    }
                }
                Button("Pulihkan dari file cadangan") { importing = true }
                    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                        switch result {
                        case .success(let url):
                            let ok = url.startAccessingSecurityScopedResource()
                            defer { if ok { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url), let n = settings.importBackup(data) {
                                message = "Pengaturan dipulihkan (\(n) item)."
                            } else {
                                message = "File bukan cadangan XConnect yang valid."
                            }
                        case .failure(let e):
                            message = "Gagal membuka file: \(e.localizedDescription)"
                        }
                    }
                if !message.isEmpty { Text(message).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Cadangkan dan pulihkan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
                row("Tentang", subtitle: "XConnect \(UpdateService.currentVersion)", icon: "info.circle") {
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
            Section(header: Text("Sapaan di dash")) {
                TextField("Sapaan (mis. Halo)", text: $settings.greetingWord)
                TextField("Nama panggilan (tampil di dash)", text: $settings.userName)
            }
            Section(header: Text("Format jam"),
                    footer: Text("Berlaku untuk jam dan perkiraan tiba (ETA) yang digambar XConnect. Jam di bilah paling atas dash digambar oleh dash sendiri dan tidak bisa diubah dari app.")) {
                Picker("Format jam", selection: $settings.clock24) {
                    Text("24 jam (13:45)").tag(true)
                    Text("12 jam (1:45 PM)").tag(false)
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Tampilan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConnectionSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var vehicle: VehicleStore
    @EnvironmentObject var live: VehicleLive
    @State private var fuelTarget = ""
    @State private var fuelCands: [FuelByteCandidate] = []
    @State private var fuelSearched = false

    private var ccuFuelReading: String {
        guard settings.ccuFuelByte >= 0 else { return "mati" }
        guard !live.rawRecord.isEmpty else { return "belum ada data CCU" }
        let lo = settings.ccuFuelByte
        let raw: String = {
            guard live.rawRecord.count > lo + (settings.ccuFuelWide ? 1 : 0) else { return "byte di luar paket" }
            return settings.ccuFuelWide
                ? "\(Int(live.rawRecord[lo]) << 8 | Int(live.rawRecord[lo + 1]))"
                : "\(live.rawRecord[lo])"
        }()
        if let k = live.fuelKmPerL(byte: lo, wide: settings.ccuFuelWide, unit: settings.ccuFuelUnit, divisor: settings.ccuFuelDiv) {
            return "mentah \(raw) → \(Fmt.km(k)) km/L"
        }
        return "mentah \(raw) → tidak valid (di luar 3-120 km/L), dipakai riwayat/bawaan"
    }

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
            Section(header: Text("Kecepatan data di dash"),
                    footer: Text("Frame lebih ringan sampai lebih cepat ke dash, jadi peta dan angka tidak terasa tertinggal, tetapi gambarnya sedikit lebih kasar. \"Jaga data HP\" memutar audio senyap (tidak mengganggu musik) supaya volume dan data HP lain tetap berubah saat app di latar belakang atau layar terkunci.")) {
                sliderRow("Kualitas gambar dash", value: $settings.dashQuality, range: 0.4...0.95, step: 0.05, unit: "")
                Toggle("Jaga data HP tetap hidup di latar belakang", isOn: $settings.keepAliveAudio)
            }
            Section(header: Text("Motor")) {
                TextField("Nama motor", text: $vehicle.name)
                TextField("Model", text: $vehicle.model)
                Stepper("Kapasitas tangki \(Fmt.liters(vehicle.tankL))", value: $vehicle.tankL, in: 3...30, step: 0.1)
                Stepper("Konsumsi bawaan \(Fmt.km(settings.defaultKmPerL)) km/L", value: $settings.defaultKmPerL,
                        in: 10...80, step: 0.5)
            }
            Section(header: Text("Konsumsi BBM dari CCU"),
                    footer: Text("Sisa bensin dihitung dari konsumsi rata-rata yang dilaporkan CCU motor (lebih akurat daripada nilai bawaan), dan berkurang bertahap menurut konsumsi saat itu. Pilih byte di paket data CCU (id 1) yang berisi rata-rata konsumsi: lihat Pengaturan > Kotak data > Data mentah CCU, bandingkan dengan angka rata-rata BBM di dash. Atur lebar, satuan, dan pembagi sampai \"Terbaca sekarang\" sama dengan dash. Bila nilai tidak valid, dipakai konsumsi Anda sendiri 30 hari terakhir (dari rata-rata dash), lalu nilai bawaan.")) {
                Stepper(settings.ccuFuelByte < 0 ? "Byte konsumsi: mati" : "Byte konsumsi: \(settings.ccuFuelByte)",
                        value: $settings.ccuFuelByte, in: -1...47)
                if settings.ccuFuelByte >= 0 {
                    Picker("Lebar nilai", selection: $settings.ccuFuelWide) {
                        Text("1 byte").tag(false)
                        Text("2 byte (n dan n+1)").tag(true)
                    }
                    Picker("Satuan", selection: $settings.ccuFuelUnit) {
                        Text("km/L").tag(0)
                        Text("L/100 km").tag(1)
                        Text("L/km").tag(2)
                    }
                    Picker("Pembagi nilai mentah", selection: $settings.ccuFuelDiv) {
                        Text("1").tag(1.0)
                        Text("10").tag(10.0)
                        Text("100").tag(100.0)
                        Text("1000").tag(1000.0)
                    }
                    Text("Terbaca sekarang: \(ccuFuelReading)").font(.footnote).foregroundColor(.secondary)
                }
            }
            Section(header: Text("Cari byte dari angka di dash"),
                    footer: Text("Saat motor menyala dan terhubung, ketik rata-rata BBM yang tampil di dash (km/L), lalu Cari. Bila ada beberapa kandidat, ulangi saat angka di dash sudah berubah: byte yang benar ikut berubah. Bila tidak ada yang cocok, rata-rata BBM mungkin ada di paket data lain (lihat Data mentah CCU).")) {
                TextField("Rata-rata BBM di dash (km/L)", text: $fuelTarget)
                    .keyboardType(.decimalPad)
                Button("Cari byte") {
                    let t = Double(fuelTarget.replacingOccurrences(of: ",", with: ".")) ?? 0
                    fuelCands = live.fuelByteCandidates(target: t)
                    fuelSearched = true
                }
                if fuelSearched && fuelCands.isEmpty {
                    Text(live.rawRecord.isEmpty ? "Belum ada data CCU." : "Tidak ada byte yang cocok.")
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
            Section(header: Text("Klik cepat 2x"),
                    footer: Text("Dua tekan pada tombol yang sama dalam waktu ini dihitung sebagai klik 2x. Tekan 1x tetap langsung dijalankan tanpa menunggu. Tiap tekan dicatat di Log beserta selisih waktunya.")) {
                sliderRow("Jendela klik 2x", value: Binding(
                    get: { Double(settings.doubleClickMs) },
                    set: { settings.doubleClickMs = Int($0) }), range: 300...2000, step: 50, unit: "ms")
            }
            Section(header: Text("Tekan tahan (layar Musik)"),
                    footer: Text("Di layar Musik: tahan tombol atas = lagu berikutnya, tahan tombol bawah = lagu sebelumnya (sekali per tahan). Tahan dikenali dari tekan berulang arah sama yang berlangsung selama durasi ini (dash mengulang tekan saat tombol ditahan). Tekan 1x tetap volume, 2x cepat tetap ganti tampilan; bila tahan aktif, ganti tampilan menunggu sekitar 0,4 dtk untuk memastikan itu bukan tahan. Bila tahan tidak bereaksi, ketuk Log setelah menahan tombol dan kirim barisnya: tiap tekan dicatat beserta jarak waktunya. Izin Media & Apple Music harus diberikan.")) {
                Toggle("Tahan = lagu berikutnya/sebelumnya", isOn: $settings.holdSkip)
                sliderRow("Durasi tekan tahan", value: Binding(
                    get: { Double(settings.holdMs) },
                    set: { settings.holdMs = Int($0) }), range: 300...2000, step: 50, unit: "ms")
            }
            Section(header: Text("Bahasa dash (eksperimen)"),
                    footer: Text("Dash menanyakan bahasa ke app lewat CCU. Bawaan: tidak dikirim. Dugaan (belum terbukti): format jam di bar atas dash mengikuti bahasa ini, bukan pengaturan jam 24 jam app. Kode yang dikenal: 0 = Inggris, 15 = Vietnam. Coba satu kode, matikan lalu nyalakan kontak, dan lihat jam dan teks bawaan dash. Kode yang ditolak CCU tercatat di Log sebagai CCU: error. Kembalikan ke -1 bila tampilan dash menjadi aneh.")) {
                Stepper(settings.dashLang < 0 ? "Kode bahasa: tidak dikirim" : "Kode bahasa: \(settings.dashLang)",
                        value: $settings.dashLang, in: -1...63)
            }
            Section(footer: Text("Layar Tes tombol (Pengaturan > Layar dasbor) menampilkan tiap tekan tombol di dash dan mencatatnya di Log.")) {
                EmptyView()
            }
        }
        .navigationTitle("Kontrol pada motor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pratinjau layar dash di halaman pengaturan (ikut tampil di dash asli bila terhubung).
struct DashPreviewBox: View {
    @EnvironmentObject var bike: BikeController

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Rectangle().fill(Color.black)
                if let img = bike.preview {
                    Image(uiImage: img).resizable().interpolation(.medium)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(480.0 / 234.0, contentMode: .fit)
            .cornerRadius(8)
            HStack {
                Button { bike.stepScreen(forward: false) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                Spacer()
                Text(bike.currentScreen.title).font(.footnote)
                Spacer()
                Button { bike.stepScreen(forward: true) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct MapSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bike: BikeController

    var body: some View {
        Form {
            Section(header: Text("Pratinjau"),
                    footer: Text("Pilih layar Peta + data atau Peta saja. Contoh panel navigasi tampil selama halaman ini terbuka.")) {
                DashPreviewBox()
            }
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
                sliderRow("Posisi (kiri ↔ kanan)", value: $settings.markerX, range: -120...120, step: 2, unit: "px")
            }
            Section(header: Text("Kotak petunjuk arah (hijau, ikon belok)")) {
                sliderRow("Ukuran", value: $settings.navPanelScale, range: 0.6...1.4, step: 0.05, unit: "x")
                sliderRow("Geser kiri ↔ kanan", value: $settings.navDX, range: -8...280, step: 2, unit: "px")
                sliderRow("Geser atas ↔ bawah", value: $settings.navDY, range: -4...110, step: 2, unit: "px")
            }
            Section(header: Text("Kotak estimasi (jarak dan waktu)"),
                    footer: Text("Pilih data yang tampil di kotak estimasi. Bila semua dimatikan, kotak disembunyikan.")) {
                Toggle("Estimasi jarak (sisa jarak)", isOn: $settings.etaShowDistance)
                Toggle("Estimasi durasi perjalanan (sisa waktu)", isOn: $settings.etaShowDuration)
                Toggle("Estimasi waktu sampai (jam tiba)", isOn: $settings.etaShowArrival)
                sliderRow("Ukuran", value: $settings.etaScale, range: 0.6...1.4, step: 0.05, unit: "x")
                sliderRow("Geser kiri ↔ kanan", value: $settings.etaDX, range: -54...300, step: 2, unit: "px")
                sliderRow("Geser atas ↔ bawah", value: $settings.etaDY, range: -140...4, step: 2, unit: "px")
            }
            Section(footer: Text("Nama jalan tampil di bilah bawah dash (dari GPS saat tidak navigasi, dari rute saat navigasi).")) {
                Toggle("Nama jalan di bilah bawah dash", isOn: $settings.showRoadName)
                Button("Atur ulang posisi ke bawaan") {
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
        .navigationTitle("Peta di dasbor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bike.demoNav = true
            bike.setPreviewVisible(true)
        }
        .onDisappear {
            bike.demoNav = false
            bike.setPreviewVisible(false)
        }
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
            ForEach(DashField.selectable, id: \.rawValue) { f in Text(f.title).tag(f.rawValue) }
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
                sliderRow("Kegelapan latar kolom (0 = transparan)", value: $settings.cardBgAlpha, range: 0...1, step: 0.05, unit: "")
            }
            Section(header: Text("Ukuran huruf"),
                    footer: Text("1 = ukuran bawaan. Huruf otomatis dikecilkan bila isi kotak terlalu panjang, jadi tidak pernah keluar dari kotak.")) {
                sliderRow("Kotak besar", value: $settings.cardFontBig, range: 0.5...1.5, step: 0.05, unit: "x")
                sliderRow("Kotak kecil", value: $settings.cardFontSmall, range: 0.5...1.5, step: 0.05, unit: "x")
                Button("Atur ulang ukuran huruf") {
                    settings.cardFontBig = 1
                    settings.cardFontSmall = 1
                }
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
            Section(header: Text("Link CCU"), footer: Text("Data motor dibaca lewat Bluetooth ke CCU. Status: \(live.state)")) {
                Toggle("Baca data CCU", isOn: $settings.ccuEnabled)
                if let v = live.batteryV { Text("Aki: " + String(format: "%.1f V", v)) }
                if let o = live.odoKm { Text("ODO: " + String(format: "%.1f km", o)) }
                if let t = live.coolantC { Text("Suhu mesin: \(t) °C") }
                if let t = live.airC { Text("Suhu udara: \(t) °C") }
                if let r = live.rpm { Text("RPM: \(r)") }
                if let v = live.speedKmh { Text("Kecepatan CCU: \(v) km/j") }
                if let d = live.dtcCount { Text("Kode gangguan: \(d)") }
                if let k = live.ignitionOn { Text("Kunci kontak: " + (k ? "ON" : "OFF")) }
                NavigationLink("Data mentah CCU (semua byte)") { CcuRawView() }
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
                    footer: Text("Update diambil dari GitHub Releases (workflow Actions menerbitkannya otomatis setiap build). iOS tidak mengizinkan app memasang IPA sendiri, jadi tombol Pasang membuka SideStore, AltStore, atau LiveContainer dengan IPA terbaru: tinggal satu ketukan konfirmasi di sana. Di LiveContainer, bila bundle ID sudah ada pilih Ganti agar data app tetap. Bila XConnect sendiri dijalankan di dalam LiveContainer, jalankan dalam mode multitasking atau di LiveContainer kedua supaya LiveContainer utama bebas memproses pemasangan.")) {
                HStack { Text("Terpasang"); Spacer(); Text("\(UpdateService.currentVersion)").foregroundColor(.secondary) }
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
                        Text("LiveContainer").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Button("Pasang update") { updater.install(using: settings.updater) }
                    Button("Tambah sumber ke \(UpdateService.storeName(settings.updater)) (cara yang disarankan)") {
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
            ForEach(DashField.selectable, id: \.rawValue) { f in Text(f.title).tag(f.rawValue) }
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
            Section(header: Text("Saat motor dinyalakan"),
                    footer: Text("Layar yang tampil pertama di dash setelah terhubung, tanpa perlu membuka app. Hanya layar yang aktif di atas yang dipakai.")) {
                Picker("Layar awal", selection: $settings.startScreen) {
                    Text("Layar pertama yang aktif").tag(-1)
                    ForEach(DashScreen.allCases, id: \.rawValue) { sc in Text(sc.title).tag(sc.rawValue) }
                }
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
    @EnvironmentObject var nav: NavigationController

    var body: some View {
        Form {
            Section(header: Text("Kendaraan")) {
                Picker("Jenis rute", selection: $settings.costing) {
                    Text("Skuter (NMAX/XMAX)").tag("motor_scooter")
                    Text("Motor").tag("motorcycle")
                    Text("Mobil").tag("auto")
                }
            }
            Section(header: Text("Profil rute"),
                    footer: Text("Dibaca setiap kali rute dihitung atau dihitung ulang. Bawaan Valhalla untuk skuter menghindari jalan utama dan membatasi 45 km/j sehingga rute memutar dan waktunya lama. Batas kecepatan memengaruhi estimasi waktu, bukan kecepatan Anda berkendara.")) {
                if settings.costing != "auto" {
                    sliderRow("Jalan utama", value: $settings.routePrimary, range: 0...1, step: 0.1, unit: "")
                    Text("0 = hindari jalan utama, 1 = utamakan jalan utama").font(.caption).foregroundColor(.secondary)
                }
                Stepper("Batas kecepatan maksimal \(settings.routeTopSpeed) km/j", value: $settings.routeTopSpeed, in: 20...120, step: 5)
                if settings.costing != "auto" {
                    sliderRow("Tanjakan", value: $settings.routeHills, range: 0...1, step: 0.1, unit: "")
                    Text("0 = hindari tanjakan, 1 = tidak masalah").font(.caption).foregroundColor(.secondary)
                    sliderRow("Gang dan jalan permukiman", value: $settings.routeLiving, range: 0...1, step: 0.1, unit: "")
                    sliderRow("Jalan setapak / tak beraspal", value: $settings.routeTrails, range: 0...1, step: 0.1, unit: "")
                }
                if settings.costing != "motor_scooter" {
                    Toggle("Hindari jalan tol", isOn: $settings.routeAvoidTolls)
                    sliderRow("Jalan bebas hambatan", value: $settings.routeHighways, range: 0...1, step: 0.1, unit: "")
                }
                sliderRow("Feri", value: $settings.routeFerry, range: 0...1, step: 0.1, unit: "")
                Toggle("Rute terpendek (jarak), bukan tercepat", isOn: $settings.routeShortest)
                Button("Pakai bawaan XConnect (jalan utama, 80 km/j)") { settings.applyRouteProfile(.appDefault) }
                Button("Pakai bawaan Valhalla (45 km/j)") { settings.applyRouteProfile(.valhallaScooter) }
            }
            Section(header: Text("Suara petunjuk arah"),
                    footer: Text("Contoh: \"Dalam 100 meter, belok kanan ke Jalan Contoh\". Saat suara berbunyi, musik dari app lain dikecilkan otomatis oleh iOS lalu kembali normal. Volume utama iPhone tidak diubah, dan besar pengecilannya diatur iOS (tidak bisa diatur persen). Suara keluar lewat output audio yang aktif (speaker, headset, atau Bluetooth motor).")) {
                Toggle("Suara pemberitahuan", isOn: $settings.guideVoice)
                if settings.guideVoice {
                    Toggle("Kecilkan volume musik saat berbunyi", isOn: $settings.guideDuck)
                    sliderRow("Volume suara", value: $settings.guideVolume, range: 0.2...1, step: 0.1, unit: "")
                    Button("Coba suara") { nav.voice?.test() }
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

struct CcuRawView: View {
    @EnvironmentObject var live: VehicleLive
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text("Paket data id 1 (byte demi byte)"),
                    footer: Text("Nilai tiap byte diperbarui langsung. Ubah kondisi motor (gas, lampu, lipat standar) lalu lihat byte mana yang berubah. Byte yang sudah dikenal: 0-1 RPM, 2 kecepatan, 6 aki, 14 suhu mesin, 15 suhu udara, 23 kode gangguan. Tiap byte bisa dipilih jadi kotak data (\"CCU byte n\").")) {
                if live.rawRecord.isEmpty {
                    Text("Belum ada data. Hubungkan ke motor dengan CCU aktif.").foregroundColor(.secondary)
                } else {
                    ForEach(0..<live.rawRecord.count, id: \.self) { i in
                        HStack {
                            Text("Byte \(i)")
                            Spacer()
                            Text("\(live.rawRecord[i])  (0x" + String(format: "%02X", live.rawRecord[i]) + ")")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section(header: Text("ID data lain"), footer: Text("ID tambahan yang dilanggan dan masuk dari CCU.")) {
                if live.rawById.isEmpty {
                    Text("Belum ada").foregroundColor(.secondary)
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
            Section(header: Text("Eksperimen: langganan ID tambahan"),
                    footer: Text("Pisahkan dengan koma, mis. 2, 3. Berlaku saat sesi CCU dimulai ulang (matikan lalu nyalakan motor). ID yang tidak dikenal CCU bisa membuat langganan ditolak: kosongkan kembali bila data berhenti.")) {
                TextField("mis. 2, 3", text: $settings.ccuExtraIds)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle("Data mentah CCU")
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
                Text("XConnect \(UpdateService.currentVersion)")
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

import SwiftUI
import CoreLocation

struct HomeView: View {
    var openSettings: () -> Void

    @EnvironmentObject var bike: BikeController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nav: NavigationController
    @EnvironmentObject var trips: TripStore
    @State private var sharing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    greetingHeader
                    statusCard
                    previewCard
                    if nav.phase == .navigating { navCard }
                    if let p = trips.parked, !bike.isConnected { parkedCard(p) }
                    tiles
                    if settings.autoConnect {
                        Text("Fitur koneksi otomatis aktif: aplikasi akan terhubung saat motor dinyalakan, bahkan saat ponsel terkunci.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
            .onAppear { bike.setPreviewVisible(true) }
            .onDisappear { bike.setPreviewVisible(false) }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sapaan

    private var greetingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if !settings.greetingWord.isEmpty {
                    Text(settings.greetingWord).font(.title2).foregroundColor(.primary)
                }
                if !settings.userName.isEmpty {
                    Text(settings.userName).font(.system(size: 34, weight: .bold))
                }
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").font(.caption2).foregroundColor(.blue)
                    Text("Hati-hati di jalan!").font(.footnote).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image("AppLogo")
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(.top, 4)
    }

    // MARK: - Status koneksi

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.18)).frame(width: 58, height: 58)
                    Image(systemName: bike.isConnected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.title2)
                        .foregroundColor(statusColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(bike.isConnected ? "Terhubung" : (bike.accessoryPresent ? "Dash terdeteksi" : "Tidak terhubung"))
                        .font(.title3).bold()
                    Text(bike.isConnected ? "\(bike.status)" : bike.status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if let v = bike.bikeSpeedKmh, bike.isConnected {
                        Text("Kecepatan motor \(v) km/j").font(.footnote)
                    }
                }
                Spacer()
            }
            HStack {
                if bike.isConnected {
                    Button { bike.disconnect() } label: {
                        Label("Putus", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { bike.connect() } label: {
                        Label("Hubungkan ke motor", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button { bike.showPairingPicker() } label: { Image(systemName: "link") }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    private var statusColor: Color {
        bike.isConnected ? .green : (bike.accessoryPresent ? .orange : .gray)
    }

    // MARK: - Preview dasbor

    /// Dash menutup bagian atas dan bar hitam nama jalan di bawah bingkai; preview hanya menampilkan area yang terlihat.
    static func visibleArea(_ img: UIImage) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let k = CGFloat(cg.width) / 480
        let r = CGRect(x: 0, y: DashComposer.visTop * k, width: CGFloat(cg.width), height: DashComposer.visHeight * k)
        guard r.maxY <= CGFloat(cg.height), let out = cg.cropping(to: r) else { return img }
        return UIImage(cgImage: out, scale: img.scale, orientation: img.imageOrientation)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tampilan dasbor").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                if bike.isConnected && bike.fps > 0 {
                    Text(String(format: "%.1f fps", bike.fps)).font(.caption).foregroundColor(.secondary)
                }
            }
            ZStack {
                Rectangle().fill(Color.black)
                if let img = bike.preview {
                    Image(uiImage: Self.visibleArea(img)).resizable().interpolation(.medium)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(480.0 / DashComposer.visHeight, contentMode: .fit)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.4), lineWidth: 1))

            HStack {
                Button { bike.stepScreen(forward: false) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                Spacer()
                VStack(spacing: 1) {
                    Text(bike.currentScreen.title).font(.headline)
                    Text("\(min(bike.screenIndex, bike.screens().count - 1) + 1) dari \(bike.screens().count) tampilan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { bike.stepScreen(forward: true) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    // MARK: - Navigasi aktif

    private var navCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: nav.nextSymbol).font(.title)
                Text(Fmt.distance(nav.distToTurnM)).font(.title2).bold()
                Spacer()
                Button("Berhenti") { nav.stop() }.buttonStyle(.bordered)
            }
            if !nav.nextInstruction.isEmpty { Text(nav.nextInstruction).font(.subheadline) }
            if let eta = nav.etaDate {
                Text("Sisa \(Fmt.distance(nav.remainingM)) • \(Fmt.duration(nav.remainingS)) • tiba \(Fmt.clock(eta))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    // MARK: - Motor diparkir

    private func parkedCard(_ p: ParkedInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blue).frame(width: 34, height: 34)
                Text("P").font(.headline).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Motor diparkir").font(.headline)
                Text(Fmt.ago(p.date) + (p.place.isEmpty ? "" : " · " + p.place))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                let place = Place(name: "Motor saya", subtitle: p.place, lat: p.lat, lon: p.lon)
                nav.navigate(to: place, autoStart: false)
            } label: { Image(systemName: "arrow.triangle.turn.up.right.diamond.fill") }
                .buttonStyle(.borderedProminent)
            Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.bordered)
                .sheet(isPresented: $sharing) {
                    ShareSheet(items: ["Motor saya diparkir di sini: https://maps.google.com/?q=\(p.lat),\(p.lon)"])
                }
            Button { trips.clearParked() } label: { Image(systemName: "checkmark") }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }

    // MARK: - Ubin pengaturan cepat

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Tampilan dasbor", bike.currentScreen.title, "rectangle.split.2x1.fill") {
                bike.stepScreen(forward: true)
            }
            tile("Hemat baterai", settings.saveBattery ? "Nyala" : "Mati", "battery.100") {
                settings.saveBattery.toggle()
            }
            tile("Peta dasar", "OpenFreeMap", "map.fill") { openSettings() }
            tile("Layar aktif", "\(bike.screens().count) layar", "square.stack.fill") { openSettings() }
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundColor(.secondary)
                    Text(value).font(.subheadline).bold().foregroundColor(.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

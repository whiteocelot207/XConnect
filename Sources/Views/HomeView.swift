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
            // seluruh isi Home bisa digulir; pratinjau dasbor ada tepat di bawah kartu "Hubungkan ke motor"
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    greetingHeader
                    statusCard
                    previewCard
                    if nav.phase == .navigating { navCard }
                    if let p = trips.parked, !bike.isConnected { parkedCard(p) }
                    tiles
                    if settings.autoConnect {
                        Text(tr("Auto-connect is on: the app connects when the motorcycle is switched on, even when the phone is locked."))
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
                Text(settings.greeting).font(.title2).foregroundColor(.primary)
                if !settings.userName.isEmpty {
                    Text(settings.userName).font(.system(size: 34, weight: .bold))
                }
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").font(.caption2).foregroundColor(.accentColor)
                    Text(tr("Ride safe!")).font(.footnote).foregroundColor(.secondary)
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
                    Text(bike.isConnected ? tr("Connected") : (bike.accessoryPresent ? tr("Dash detected") : tr("Not connected")))
                        .font(.title3).bold()
                    Text(bike.isConnected ? "\(bike.status)" : bike.status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if let v = bike.bikeSpeedKmh, bike.isConnected {
                        Text(tr("Bike speed {0} km/h", v)).font(.footnote)
                    }
                }
                Spacer()
            }
            HStack {
                if bike.isConnected {
                    Button { bike.disconnect() } label: {
                        Label(tr("Disconnect"), systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { bike.connect() } label: {
                        Label(tr("Connect to the motorcycle"), systemImage: "play.fill").frame(maxWidth: .infinity)
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
                Text(tr("Dash display")).font(.subheadline).foregroundColor(.secondary)
                Spacer()
                if bike.isConnected && bike.fps > 0 {
                    Text(String(format: "%.1f fps", bike.fps)).font(.caption).foregroundColor(.secondary)
                }
            }
            DashFrameView()
                .frame(maxWidth: 340)
                .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.4), lineWidth: 1))

            HStack {
                Button { bike.stepScreen(forward: false) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                Spacer()
                VStack(spacing: 1) {
                    Text(bike.currentScreen.title).font(.headline)
                    Text(tr("{0} of {1} screens", min(bike.screenIndex, bike.screens().count - 1) + 1, bike.screens().count))
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
                Button(tr("Stop")) { nav.stop() }.buttonStyle(.bordered)
            }
            if !nav.nextInstruction.isEmpty { Text(nav.nextInstruction).font(.subheadline) }
            if let eta = nav.etaDate {
                Text(tr("{0} left • {1} • arrive {2}", Fmt.distance(nav.remainingM), Fmt.duration(nav.remainingS), Fmt.clock(eta)))
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
                Circle().fill(Color.accentColor).frame(width: 34, height: 34)
                Text("P").font(.headline).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Motorcycle parked")).font(.headline)
                Text(Fmt.ago(p.date) + (p.place.isEmpty ? "" : " · " + p.place))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                let place = Place(name: tr("My motorcycle"), subtitle: p.place, lat: p.lat, lon: p.lon)
                nav.navigate(to: place, autoStart: false)
            } label: { Image(systemName: "arrow.triangle.turn.up.right.diamond.fill") }
                .buttonStyle(.borderedProminent)
            Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.bordered)
                .sheet(isPresented: $sharing) {
                    ShareSheet(items: [tr("My motorcycle is parked here: https://maps.google.com/?q={0},{1}", p.lat, p.lon)])
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
            tile(tr("Dash display"), bike.currentScreen.title, "rectangle.split.2x1.fill") {
                bike.stepScreen(forward: true)
            }
            tile(tr("Battery saver"), settings.saveBattery ? tr("On") : tr("Off"), "battery.100") {
                settings.saveBattery.toggle()
            }
            tile(tr("Base map"), "OpenFreeMap", "map.fill") {
                SettingsRouter.shared.request = .maps
                openSettings()
            }
            tile(tr("Active screens"), tr("{0} screens", bike.screens().count), "square.stack.fill") {
                SettingsRouter.shared.request = .screens
                openSettings()
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.15))
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

import SwiftUI
import CoreLocation

struct NavigateView: View {
    @EnvironmentObject var nav: NavigationController
    @EnvironmentObject var places: PlaceStore
    @EnvironmentObject var settings: AppSettings

    @State private var lastLen = 0
    @State private var renameTarget: Place?
    @State private var renameText = ""
    @State private var showMap = false

    var body: some View {
        listScreen
    }

    // MARK: - Daftar: pencarian, tempat tersimpan, favorit

    private var listScreen: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Cari tempat, alamat, atau tempel tautan", text: $nav.query)
                            .disableAutocorrection(true)
                            .onChange(of: nav.query) { q in queryEdited(q) }
                        if nav.searching || nav.linkBusy { ProgressView() }
                        if !nav.query.isEmpty {
                            Button { nav.query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if MapsLink.isLikely(nav.query) {
                        Button { nav.resolveLink(nav.query) } label: {
                            Label("Buka tautan / koordinat ini", systemImage: "link")
                        }
                    }
                }

                if !nav.message.isEmpty {
                    Section { Text(nav.message).font(.footnote) }
                }

                if !nav.searchResults.isEmpty {
                    Section(header: Text("Hasil")) {
                        ForEach(nav.searchResults) { p in placeRow(p, icon: "mappin.circle.fill") }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pencarian lebih cepat dengan Google Maps").font(.headline)
                        Text("Temukan tempat di Google Maps, salin tautannya, lalu tempelkan di sini. Tautan seperti maps.app.goo.gl/… langsung dikenali.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        VStack(spacing: 8) {
                            Button {
                                if let u = URL(string: "https://www.google.com/maps") { UIApplication.shared.open(u) }
                            } label: { leftLabel("Buka Google Maps", icon: "map") }
                                .buttonStyle(.bordered)
                            Button { pasteLink() } label: { leftLabel("Tempel tautan", icon: "doc.on.clipboard") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if nav.destination != nil || nav.phase != .idle {
                    Section { routeBox }
                }

                Section(header: Text("Tempat tersimpan")) {
                    savedRow("Rumah", icon: "house.fill", place: places.home, slot: 1)
                    savedRow("Kantor", icon: "briefcase.fill", place: places.work, slot: 2)
                }

                Section(header: Text("Favorit")) {
                    if places.favorites.isEmpty {
                        Text("Belum ada favorit. Pilih tempat lalu ketuk bintang.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(places.favorites) { p in
                        placeRow(p, icon: "star.fill")
                            .contextMenu {
                                Button { renameTarget = p; renameText = p.name } label: { Label("Ganti nama", systemImage: "pencil") }
                                Button { places.toggleFavorite(p) } label: { Label("Hapus dari favorit", systemImage: "star.slash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { renameTarget = p; renameText = p.name } label: { Label("Ganti nama", systemImage: "pencil") }.tint(.blue)
                            }
                    }
                    .onDelete { places.favorites.remove(atOffsets: $0) }
                }

                if !places.recents.isEmpty {
                    Section(header: Text("Terakhir")) {
                        ForEach(places.recents) { p in placeRow(p, icon: "clock") }
                    }
                }
            }
            .navigationTitle("Navigasi")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $renameTarget) { p in
            RenameSheet(title: "Ganti nama favorit", initial: renameText) { places.renameFavorite(p, to: $0) }
        }
        .sheet(isPresented: $showMap) {
            ZStack(alignment: .topTrailing) {
                NavMapView(nav: nav, onLongPress: { c in nav.pin(c) })
                    .edgesIgnoringSafeArea(.all)
                Button { showMap = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                        .foregroundColor(.white).shadow(radius: 3)
                }
                .padding(16)
            }
        }
    }

    private func queryEdited(_ q: String) {
        let jump = q.count - lastLen
        lastLen = q.count
        if MapsLink.isLikely(q) {
            nav.searchResults = []
            if jump > 8 { nav.resolveLink(q) }       // tempelan sekaligus = langsung diproses
        } else {
            nav.queryChanged()
        }
    }

    private func pasteLink() {
        if let s = UIPasteboard.general.string, !s.isEmpty {
            nav.resolveLink(s)
        } else {
            nav.message = "Clipboard kosong. Salin tautan dari Google Maps dulu."
        }
    }

    private func placeRow(_ p: Place, icon: String) -> some View {
        Button { nav.select(p) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(.blue).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundColor(.primary)
                    if !p.subtitle.isEmpty {
                        Text(p.subtitle).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func savedRow(_ title: String, icon: String, place: Place?, slot: Int) -> some View {
        Button {
            if let p = place { nav.select(p) } else { nav.beginSlot(slot) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(.blue).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    Text(place?.name ?? "Belum diatur · ketuk untuk memilih")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
            }
        }
        .swipeActions {
            Button("Ubah") { nav.beginSlot(slot) }.tint(.blue)
        }
    }

    // MARK: - Kotak rute (muncul di atas daftar saat ada tujuan)

    private func leftLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func centerLabel(_ title: String, icon: String?) -> some View {
        HStack(spacing: 6) {
            if let icon = icon { Image(systemName: icon) }
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var voiceButton: some View {
        Button { settings.guideVoice.toggle() } label: {
            Image(systemName: settings.guideVoice ? "speaker.wave.2.fill" : "speaker.slash.fill")
        }
        .buttonStyle(.bordered)
    }

    private func routeTitle(_ i: Int) -> String { i == 0 ? "Tercepat" : "Alternatif \(i)" }

    private var routeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = nav.destination {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.headline)
                        if !d.subtitle.isEmpty { Text(d.subtitle).font(.footnote).foregroundColor(.secondary) }
                    }
                    Spacer()
                    Button { places.toggleFavorite(d) } label: {
                        Image(systemName: places.isFavorite(d) ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if nav.phase == .navigating {
                HStack(spacing: 12) {
                    Image(systemName: nav.nextSymbol).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nav.nextTitle).font(.headline)
                        Text(Fmt.distance(nav.distToTurnM)).font(.title2).bold()
                        if !nav.nextInstruction.isEmpty {
                            Text(nav.nextInstruction).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
                if let eta = nav.etaDate {
                    Text("Sisa \(Fmt.distance(nav.remainingM)) • tiba \(Fmt.clock(eta))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if nav.simulating {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Mode simulasi: posisi buatan di sepanjang rute", systemImage: "play.circle.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                        Picker("Kecepatan simulasi", selection: $nav.simSpeedKmh) {
                            Text("20 km/j").tag(20.0)
                            Text("40 km/j").tag(40.0)
                            Text("80 km/j").tag(80.0)
                            Text("150 km/j").tag(150.0)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            } else if nav.busy && nav.routes.isEmpty {
                HStack { ProgressView(); Text("Menghitung rute…") }
            } else if !nav.routes.isEmpty {
                // preview kecil semua rute; ketuk garis rute lain untuk memilih, ketuk di tempat lain untuk peta penuh
                ZStack(alignment: .bottomTrailing) {
                    RoutePreviewMap(routes: nav.routes, selected: nav.routeIndex, destination: nav.destination,
                                    onSelect: { nav.selectRoute($0) }, onOpen: { showMap = true })
                    Label("Ketuk untuk memperbesar", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .foregroundColor(.white)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ForEach(nav.routes.indices, id: \.self) { i in
                    let r = nav.routes[i]
                    let picked = i == nav.routeIndex
                    Button { nav.selectRoute(i) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(Fmt.duration(r.totalS)).font(.title3.weight(.bold)).foregroundColor(.primary)
                                Text(Fmt.distance(r.totalM)).font(.subheadline).foregroundColor(.secondary)
                                if i > 0, let first = nav.routes.first, r.totalS > first.totalS + 30 {
                                    Text("+" + Fmt.duration(r.totalS - first.totalS)).font(.footnote).foregroundColor(.secondary)
                                }
                                Spacer()
                                if i == 0 {
                                    Text("Tercepat")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.blue.opacity(0.18)))
                                        .foregroundColor(.blue)
                                } else {
                                    Text("Alternatif \(i)").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            if !r.via.isEmpty {
                                Text("lewat \(r.via)").font(.footnote).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(picked ? Color.blue.opacity(0.10) : Color.gray.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(picked ? Color.blue : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.borderless)
                }
            }

            if nav.phase == .navigating {
                HStack(spacing: 8) {
                    Button { nav.stop() } label: {
                        centerLabel("Hentikan navigasi", icon: "xmark.octagon.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    voiceButton
                }
                if nav.simulating {
                    Button { nav.stopSimulation() } label: {
                        centerLabel("Hentikan simulasi", icon: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            } else {
                HStack(spacing: 8) {
                    Button { nav.startSimulation() } label: {
                        centerLabel("Simulasi", icon: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(nav.route == nil)
                    Button { nav.stop() } label: { centerLabel("Batal", icon: nil) }
                        .buttonStyle(.bordered)
                    voiceButton
                }
                Button { nav.startNavigation() } label: {
                    centerLabel("Mulai Navigasi", icon: "play.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(nav.route == nil)
            }
            if nav.phase != .navigating, let d = nav.destination {
                Menu("Simpan sebagai") {
                    Button("Rumah") { places.home = d }
                    Button("Kantor") { places.work = d }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}


struct RenameSheet: View {
    let title: String
    let initial: String
    let onSave: (String) -> Void
    @Environment(\.presentationMode) private var presentation
    @State private var text = ""

    var body: some View {
        NavigationView {
            Form { TextField("Nama", text: $text) }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Batal") { presentation.wrappedValue.dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Simpan") { onSave(text); presentation.wrappedValue.dismiss() }
                    }
                }
                .onAppear { text = initial }
        }
    }
}

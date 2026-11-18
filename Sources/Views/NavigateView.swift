import SwiftUI
import CoreLocation

struct NavigateView: View {
    @EnvironmentObject var nav: NavigationController
    @EnvironmentObject var places: PlaceStore

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
                if nav.destination != nil || nav.phase != .idle {
                    Section { routeBox }
                }

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
                        HStack {
                            Button {
                                if let u = URL(string: "https://www.google.com/maps") { UIApplication.shared.open(u) }
                            } label: { Label("Buka Google Maps", systemImage: "map") }
                                .buttonStyle(.bordered)
                            Button { pasteLink() } label: { Label("Tempel tautan", systemImage: "doc.on.clipboard") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
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
                    VStack(alignment: .leading) {
                        Text(Fmt.distance(nav.distToTurnM)).font(.title2).bold()
                        if !nav.nextInstruction.isEmpty { Text(nav.nextInstruction).font(.subheadline) }
                    }
                }
                if let eta = nav.etaDate {
                    Text("Sisa \(Fmt.distance(nav.remainingM)) • tiba \(Fmt.clock(eta))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if nav.busy && nav.routes.isEmpty {
                HStack { ProgressView(); Text("Menghitung rute…") }
            } else if !nav.routes.isEmpty {
                ForEach(nav.routes.indices, id: \.self) { i in
                    let r = nav.routes[i]
                    Button { nav.selectRoute(i) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: i == nav.routeIndex ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routeTitle(i)).foregroundColor(.primary)
                                Text("\(Fmt.distance(r.totalM)) • \(Fmt.duration(r.totalS))" + (r.via.isEmpty ? "" : " • via \(r.via)"))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                if nav.phase == .navigating {
                    Button { nav.stop() } label: {
                        Label("Hentikan navigasi", systemImage: "xmark.octagon.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button { nav.startNavigation() } label: {
                        Label("Mulai", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nav.route == nil)
                    Button("Batal") { nav.stop() }
                        .buttonStyle(.bordered)
                }
                Button { showMap = true } label: { Image(systemName: "map") }
                    .buttonStyle(.bordered)
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

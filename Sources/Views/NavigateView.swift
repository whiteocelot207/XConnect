import SwiftUI
import CoreLocation

struct NavigateView: View {
    @EnvironmentObject var nav: NavigationController
    @EnvironmentObject var places: PlaceStore

    @State private var lastLen = 0
    @State private var renameTarget: Place?
    @State private var renameText = ""

    var body: some View {
        if nav.destination == nil && nav.phase == .idle {
            listScreen
        } else {
            mapScreen
        }
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

    // MARK: - Peta: pratinjau rute dan navigasi

    private var mapScreen: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // peta hanya ~45% layar; sisanya untuk kartu rute dan pilihan
                NavMapView(nav: nav, onLongPress: { c in nav.pin(c) })
                    .frame(height: max(220, geo.size.height * 0.45))
                ScrollView {
                    VStack(spacing: 8) {
                        if !nav.message.isEmpty {
                            Text(nav.message)
                                .font(.footnote)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                        bottomCard
                    }
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private var bottomCard: some View {
        if nav.phase == .navigating {
            navigatingCard
        } else if let d = nav.destination {
            previewCard(d)
        }
    }

    private func previewCard(_ d: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(d.name).font(.headline)
                    if !d.subtitle.isEmpty { Text(d.subtitle).font(.footnote).foregroundColor(.secondary) }
                }
                Spacer()
                Button { places.toggleFavorite(d) } label: {
                    Image(systemName: places.isFavorite(d) ? "star.fill" : "star")
                }
            }
            if let r = nav.route {
                Text("\(Fmt.distance(r.totalM)) • \(Fmt.duration(r.totalS))").font(.subheadline)
            } else if nav.busy {
                HStack { ProgressView(); Text("Menghitung rute…") }
            }
            HStack {
                Button("Mulai") { nav.startNavigation() }
                    .buttonStyle(.borderedProminent)
                    .disabled(nav.route == nil)
                Button("Batal") { nav.stop() }
                    .buttonStyle(.bordered)
                Menu("Simpan sebagai") {
                    Button("Rumah") { places.home = d }
                    Button("Kantor") { places.work = d }
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var navigatingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: nav.nextSymbol).font(.system(size: 34))
                VStack(alignment: .leading) {
                    Text(Fmt.distance(nav.distToTurnM)).font(.title).bold()
                    if !nav.nextInstruction.isEmpty { Text(nav.nextInstruction).font(.subheadline) }
                }
            }
            if let eta = nav.etaDate {
                Text("Sisa \(Fmt.distance(nav.remainingM)) • tiba \(Fmt.clock(eta))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Button("Berhenti") { nav.stop() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
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

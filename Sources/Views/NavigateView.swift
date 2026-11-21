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
    @State private var showRoute = false

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
                        TextField(tr("Search a place, address, or paste a link"), text: $nav.query)
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
                            Label(tr("Open this link / coordinates"), systemImage: "link")
                        }
                    }
                    Button {
                        nav.query = ""
                        nav.showFuelStations()
                    } label: {
                        HStack {
                            Label(tr("Find nearest gas station"), systemImage: "fuelpump.fill")
                            Spacer()
                        }
                    }
                    if !nav.fuelMessage.isEmpty {
                        Text(nav.fuelMessage).font(.footnote).foregroundColor(.orange)
                    }
                }

                if !nav.searchResults.isEmpty {
                    Section(header: Text(tr("Results"))) {
                        ForEach(nav.searchResults) { p in placeRow(p, icon: "mappin.circle.fill") }
                    }
                }

                if nav.phase == .navigating {
                    Section { activeBox }
                }

                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            if let u = URL(string: "https://www.google.com/maps") { UIApplication.shared.open(u) }
                        } label: { leftLabel(tr("Open Google Maps"), icon: "map").padding(.vertical, 10) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        pasteLinkButton
                        if !nav.message.isEmpty {
                            Text(nav.message).font(.footnote).foregroundColor(.orange)
                        }
                        Text(tr("Find a place in Google Maps, copy its link, then paste it here. Links such as maps.app.goo.gl/… are recognized right away."))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section(header: Text(tr("Saved places"))) {
                    savedRow(tr("place_home"), icon: "house.fill", place: places.home, slot: 1)
                    savedRow(tr("Office"), icon: "briefcase.fill", place: places.work, slot: 2)
                }

                Section(header: Text(tr("Favorites"))) {
                    if places.favorites.isEmpty {
                        Text(tr("No favorites yet. Pick a place, then tap the star."))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(places.favorites) { p in
                        placeRow(p, icon: "star.fill")
                            .contextMenu {
                                Button { renameTarget = p; renameText = p.name } label: { Label(tr("Rename"), systemImage: "pencil") }
                                Button { places.toggleFavorite(p) } label: { Label(tr("Remove from favorites"), systemImage: "star.slash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { renameTarget = p; renameText = p.name } label: { Label(tr("Rename"), systemImage: "pencil") }.tint(.accentColor)
                            }
                    }
                    .onDelete { places.favorites.remove(atOffsets: $0) }
                }

                if !places.recents.isEmpty {
                    Section(header: Text(tr("Recent"))) {
                        ForEach(places.recents) { p in placeRow(p, icon: "clock") }
                    }
                }
            }
            .navigationTitle(tr("Navigate"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $renameTarget) { p in
            RenameSheet(title: tr("Rename favorite"), initial: renameText) { places.renameFavorite(p, to: $0) }
        }
        .sheet(isPresented: $showRoute, onDismiss: {
            if nav.phase != .navigating { nav.stop() }
        }) { routeSheet }
        .onChange(of: nav.destination?.id) { id in
            if id != nil && nav.phase != .navigating { showRoute = true }
            else if id == nil { showRoute = false }
        }
        .onChange(of: nav.phase) { ph in
            if ph == .previewing { if nav.destination != nil { showRoute = true } }
            else { showRoute = false }
        }
    }

    // MARK: - Form pilih rute (pop up)

    private var routeSheet: some View {
        NavigationView {
            List {
                Section { routeBox }
            }
            .navigationTitle(tr("Choose route"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close")) { showRoute = false }
                }
            }
        }
        .navigationViewStyle(.stack)
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

    /// iOS 16+: tombol tempel resmi dari sistem, tidak memunculkan izin "Tempel dari app lain" (izin tidak bisa
    /// diatur otomatis oleh app). iOS 15: tombol biasa yang membaca clipboard.
    @ViewBuilder private var pasteLinkButton: some View {
        if #available(iOS 16.0, *) {
            // Teks tampil "Tempel tautan"; tombol tempel sistem diletakkan transparan di atasnya (blendMode)
            // sehingga tetap menerima ketukan tanpa memunculkan pertanyaan izin.
            leftLabel(tr("Paste link"), icon: "doc.on.clipboard")
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor))
                .overlay(
                    PasteButton(payloadType: String.self) { strings in
                        DispatchQueue.main.async {
                            if let s = strings.first, !s.isEmpty { nav.resolveLink(s) }
                            else { nav.message = tr("The clipboard is empty. Copy a link from Google Maps first.") }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.roundedRectangle(radius: 10))
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blendMode(.destinationOver)
                )
        } else {
            Button { pasteLink() } label: { leftLabel(tr("Paste link"), icon: "doc.on.clipboard").padding(.vertical, 10) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func pasteLink() {
        if let s = UIPasteboard.general.string, !s.isEmpty {
            nav.resolveLink(s)
        } else {
            nav.message = tr("The clipboard is empty. Copy a link from Google Maps first.")
        }
    }

    private func placeRow(_ p: Place, icon: String) -> some View {
        Button {
            nav.select(p)
            // selalu tampilkan pilihan rute dulu (bukan langsung navigasi)
            if nav.destination != nil && nav.phase != .navigating { showRoute = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundColor(.primary)
                    if !p.subtitle.isEmpty {
                        Text(p.subtitle).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let d = nav.distanceText(to: p) {
                    Text(d).font(.footnote.weight(.semibold)).foregroundColor(.accentColor)
                }
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func savedRow(_ title: String, icon: String, place: Place?, slot: Int) -> some View {
        Button {
            if let p = place { nav.select(p) } else { nav.beginSlot(slot) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    Text(place?.name ?? tr("Not set · tap to choose"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
            }
        }
        .swipeActions {
            Button(tr("Change")) { nav.beginSlot(slot) }.tint(.accentColor)
        }
    }

    // MARK: - Kotak rute (muncul di atas daftar saat ada tujuan)

    // MARK: - Kotak Navigasi aktif (paling atas)

    private var activeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text(tr("Navigation active")).font(.caption.weight(.semibold)).foregroundColor(.green)
            }
            if let d = nav.destination {
                Text(d.name).font(.headline)
                if !d.subtitle.isEmpty { Text(d.subtitle).font(.footnote).foregroundColor(.secondary).lineLimit(2) }
            }
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
                    Text(tr("{0} left • {1} • arrive {2}", Fmt.distance(nav.remainingM), Fmt.duration(nav.remainingS), Fmt.clock(eta)))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if nav.simulating {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(tr("Simulation mode: artificial position along the route"), systemImage: "play.circle.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                        Picker(tr("Simulation speed"), selection: $nav.simSpeedKmh) {
                            Text("20 " + tr("km/h")).tag(20.0)
                            Text("40 " + tr("km/h")).tag(40.0)
                            Text("80 " + tr("km/h")).tag(80.0)
                            Text("150 " + tr("km/h")).tag(150.0)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                HStack(spacing: 8) {
                    Button { nav.stop() } label: {
                        centerLabel(tr("Stop navigation"), icon: "xmark.octagon.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    voiceButton
                }
                if nav.simulating {
                    Button { nav.stopSimulation() } label: {
                        centerLabel(tr("Stop simulation"), icon: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
        }
        .padding(.vertical, 4)
    }

    private func leftLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22)
            Text(title).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
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

    private func routeTitle(_ i: Int) -> String { i == 0 ? tr("Fastest") : tr("Alternative {0}", i) }

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

            if nav.busy && nav.routes.isEmpty {
                HStack { ProgressView(); Text(tr("Calculating route…")) }
            } else if !nav.routes.isEmpty {
                // preview kecil semua rute; ketuk garis rute lain untuk memilih, ketuk di tempat lain untuk peta penuh
                ZStack(alignment: .bottomTrailing) {
                    RoutePreviewMap(routes: nav.routes, selected: nav.routeIndex, destination: nav.destination,
                                    onSelect: { nav.selectRoute($0) }, onOpen: { showMap = true })
                    Label(tr("Tap to enlarge"), systemImage: "arrow.up.left.and.arrow.down.right")
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
                                    Text(tr("Fastest"))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                                        .foregroundColor(.accentColor)
                                } else {
                                    Text(tr("Alternative {0}", i)).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            if !r.via.isEmpty {
                                Text(tr("via {0}", r.via)).font(.footnote).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(picked ? Color.accentColor.opacity(0.10) : Color.gray.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(picked ? Color.accentColor : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                Button { nav.startSimulation() } label: {
                    centerLabel(tr("Simulate"), icon: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(nav.route == nil)
                Button { nav.stop() } label: { centerLabel(tr("Cancel"), icon: nil) }
                    .buttonStyle(.bordered)
                voiceButton
            }
            Button { nav.startNavigation() } label: {
                centerLabel(tr("Start navigation"), icon: "play.fill")
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(nav.route == nil)
            if nav.phase != .navigating, let d = nav.destination {
                Menu {
                    Button(tr("place_home")) { places.home = d }
                    Button(tr("Office")) { places.work = d }
                } label: {
                    centerLabel(tr("Save as"), icon: "mappin.and.ellipse")
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
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
            Form { TextField(tr("Name"), text: $text) }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel")) { presentation.wrappedValue.dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Save")) { onSave(text); presentation.wrappedValue.dismiss() }
                    }
                }
                .onAppear { text = initial }
        }
    }
}

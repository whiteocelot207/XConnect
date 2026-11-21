import SwiftUI
import CoreLocation

/// Pengaturan peta offline: unduh area di sekitar suatu titik, lihat dan hapus area yang sudah tersimpan.
struct OfflineMapView: View {
    @ObservedObject private var store = OfflineMapStore.shared

    @State private var query = ""
    @State private var results = [Place]()
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var areaName: String?
    @State private var center: CLLocationCoordinate2D?
    @State private var radius = 50
    @State private var estimate = 0
    @State private var info = ""
    @State private var toDelete: OfflineArea?

    private let radii = [20, 50, 100]

    var body: some View {
        List {
            Section {
                Text(tr("Save the areas you pass most often so the dash still shows the map without a network."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            Section(header: Text(tr("Add area")).font(.headline).textCase(nil)) {
                areaPicker
                Picker(tr("Radius"), selection: $radius) {
                    ForEach(radii, id: \.self) { Text("\($0) km").tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(store.downloading)
                .onChange(of: radius) { _ in updateEstimate() }

                if center != nil {
                    Text(tr("About {0} MB. Wi-Fi is better, with the app kept open until it finishes.", estimate))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if store.downloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: store.progress)
                        HStack {
                            Text(tr("Downloading {0}… {1}%", store.downloadName, Int(store.progress * 100)))
                                .font(.footnote)
                            Spacer()
                            Button(tr("Cancel")) { store.cancel() }
                                .buttonStyle(.bordered)
                                .tint(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button { save() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle")
                            Text(tr("Save this area"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(center == nil)
                }

                if !store.message.isEmpty {
                    Text(store.message).font(.footnote).foregroundColor(.orange)
                } else if !info.isEmpty {
                    Text(info).font(.footnote).foregroundColor(.orange)
                }
            }

            Section(header: Text(tr("Saved maps")).font(.headline).textCase(nil),
                    footer: Text(store.areas.isEmpty ? "" : tr("Total {0} on the phone.", OfflineMapStore.mbText(store.totalBytes)))) {
                if store.areas.isEmpty {
                    Text(tr("No areas downloaded yet.")).font(.footnote).foregroundColor(.secondary)
                }
                ForEach(store.areas) { a in
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill").foregroundColor(.accentColor).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.headline).lineLimit(2)
                            Text(tr("Radius {0} km · {1} · {2}", a.radiusKm, OfflineMapStore.mbText(a.bytes), Self.dateText(a.date)))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            if a.failed > 0 {
                                Text(tr("{0} tiles not downloaded yet", a.failed)).font(.caption).foregroundColor(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        Button { toDelete = a } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                    }
                    .swipeActions {
                        Button(role: .destructive) { toDelete = a } label: { Label(tr("Delete"), systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(tr("Offline maps"))
        .navigationBarTitleDisplayMode(.large)
        .alert(item: $toDelete) { a in
            Alert(title: Text(tr("Delete area \"{0}\"?", a.name)),
                  message: Text(tr("About {0} of offline map will be removed from the phone.", OfflineMapStore.mbText(a.bytes))),
                  primaryButton: .destructive(Text(tr("Delete"))) { store.delete(a) },
                  secondaryButton: .cancel(Text(tr("Cancel"))))
        }
    }

    // MARK: - Pemilih area

    @ViewBuilder private var areaPicker: some View {
        if let name = areaName {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Area")).font(.caption).foregroundColor(.secondary)
                    Text(name).font(.title3).lineLimit(2)
                }
                Spacer()
                Button(tr("Change")) {
                    guard !store.downloading else { return }
                    areaName = nil
                    center = nil
                    info = ""
                }
                .foregroundColor(.accentColor)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(tr("Place search"), text: $query)
                        .disableAutocorrection(true)
                        .onChange(of: query) { q in search(q) }
                    if searching { ProgressView() }
                    else { Image(systemName: "magnifyingglass").foregroundColor(.accentColor) }
                }
                Button { useCurrentLocation() } label: {
                    Label(tr("Use current location"), systemImage: "location.fill")
                }
                .buttonStyle(.borderless)
            }
            ForEach(results) { p in
                Button { choose(p.name, p.coordinate) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).foregroundColor(.primary)
                        if !p.subtitle.isEmpty {
                            Text(p.subtitle).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Aksi

    private func choose(_ name: String, _ c: CLLocationCoordinate2D) {
        areaName = name
        center = c
        results = []
        query = ""
        info = ""
        updateEstimate()
    }

    private func useCurrentLocation() {
        let loc = AppModel.shared.location
        guard loc.hasFix else {
            info = tr("Location not available yet. Make sure location permission is on, or search a place.")
            return
        }
        let c = loc.coordinate
        choose(tr("My location"), c)
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)) { marks, _ in
            guard let m = marks?.first else { return }
            let part = m.subLocality ?? m.locality ?? m.subAdministrativeArea
            DispatchQueue.main.async {
                if let part = part, areaName == tr("My location") { areaName = tr("My location · {0}", part) }
            }
        }
    }

    private func search(_ q: String) {
        searchTask?.cancel()
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { results = []; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            let found = (try? await PlaceSearch.search(t, near: AppModel.shared.location.coordinate)) ?? []
            if Task.isCancelled { return }
            await MainActor.run { results = found; searching = false }
        }
    }

    private func updateEstimate() {
        guard let c = center else { return }
        estimate = OfflineMapStore.estimateMB(center: c, radiusKm: radius)
    }

    private func save() {
        guard let c = center, let n = areaName else { return }
        store.start(name: n, center: c, radiusKm: radius)
    }

    private static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Loc.shared.locale
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

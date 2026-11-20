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
                Text("Simpan area yang paling sering Anda lewati agar dasbor tetap menampilkan peta meskipun tanpa jaringan.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            Section(header: Text("Tambah area").font(.headline).textCase(nil)) {
                areaPicker
                Picker("Radius", selection: $radius) {
                    ForEach(radii, id: \.self) { Text("\($0) km").tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(store.downloading)
                .onChange(of: radius) { _ in updateEstimate() }

                if center != nil {
                    Text("Sekitar \(estimate) MB. Lebih baik menggunakan Wi-Fi, dengan aplikasi tetap terbuka hingga selesai.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if store.downloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: store.progress)
                        HStack {
                            Text("Mengunduh \(store.downloadName)… \(Int(store.progress * 100))%")
                                .font(.footnote)
                            Spacer()
                            Button("Batal") { store.cancel() }
                                .buttonStyle(.bordered)
                                .tint(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button { save() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle")
                            Text("Simpan area ini")
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

            Section(header: Text("Peta tersimpan").font(.headline).textCase(nil),
                    footer: Text(store.areas.isEmpty ? "" : "Total \(OfflineMapStore.mbText(store.totalBytes)) di ponsel.")) {
                if store.areas.isEmpty {
                    Text("Belum ada area yang diunduh.").font(.footnote).foregroundColor(.secondary)
                }
                ForEach(store.areas) { a in
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill").foregroundColor(.blue).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.headline).lineLimit(2)
                            Text("Radius \(a.radiusKm) km · \(OfflineMapStore.mbText(a.bytes)) · \(Self.dateText(a.date))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            if a.failed > 0 {
                                Text("\(a.failed) tile belum terunduh").font(.caption).foregroundColor(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        Button { toDelete = a } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                    }
                    .swipeActions {
                        Button(role: .destructive) { toDelete = a } label: { Label("Hapus", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("Peta offline")
        .navigationBarTitleDisplayMode(.large)
        .alert(item: $toDelete) { a in
            Alert(title: Text("Hapus area \"\(a.name)\"?"),
                  message: Text("Peta offline sekitar \(OfflineMapStore.mbText(a.bytes)) akan dihapus dari ponsel."),
                  primaryButton: .destructive(Text("Hapus")) { store.delete(a) },
                  secondaryButton: .cancel(Text("Batal")))
        }
    }

    // MARK: - Pemilih area

    @ViewBuilder private var areaPicker: some View {
        if let name = areaName {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Area").font(.caption).foregroundColor(.secondary)
                    Text(name).font(.title3).lineLimit(2)
                }
                Spacer()
                Button("Ubah") {
                    guard !store.downloading else { return }
                    areaName = nil
                    center = nil
                    info = ""
                }
                .foregroundColor(.blue)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Pencarian tempat", text: $query)
                        .disableAutocorrection(true)
                        .onChange(of: query) { q in search(q) }
                    if searching { ProgressView() }
                    else { Image(systemName: "magnifyingglass").foregroundColor(.blue) }
                }
                Button { useCurrentLocation() } label: {
                    Label("Gunakan lokasi saat ini", systemImage: "location.fill")
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
            info = "Lokasi belum tersedia. Pastikan izin lokasi aktif, atau cari tempat."
            return
        }
        let c = loc.coordinate
        choose("Lokasi saya", c)
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)) { marks, _ in
            guard let m = marks?.first else { return }
            let part = m.subLocality ?? m.locality ?? m.subAdministrativeArea
            DispatchQueue.main.async {
                if let part = part, areaName == "Lokasi saya" { areaName = "Lokasi saya · \(part)" }
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
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

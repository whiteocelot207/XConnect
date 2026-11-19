import SwiftUI

enum MotorSheet: Identifiable {
    case editVehicle
    case odometer
    case addLiters
    case setLevel
    case addMaint
    case history(String)
    case editMaint(String)

    var id: String {
        switch self {
        case .editVehicle: return "editVehicle"
        case .odometer: return "odometer"
        case .addLiters: return "addLiters"
        case .setLevel: return "setLevel"
        case .addMaint: return "addMaint"
        case .history(let s): return "history-" + s
        case .editMaint(let s): return "edit-" + s
        }
    }
}

struct MotorView: View {
    @EnvironmentObject var maint: MaintenanceStore
    @EnvironmentObject var fuel: FuelStore
    @EnvironmentObject var vehicle: VehicleStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var trips: TripStore

    @State private var tab = 0
    @State private var range = 0
    @State private var sheet: MotorSheet?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $tab) {
                        Text("Ringkasan").tag(0)
                        Text("Perawatan").tag(1)
                        Text("Riwayat perjalanan").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if tab == 0 { summary }
                    else if tab == 1 { maintenance }
                    else { history }
                }
                .padding()
            }
            .navigationTitle("Motor")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $sheet) { s in sheetView(s) }
        }
        .navigationViewStyle(.stack)
    }

    private var cardBG: Color { Color(UIColor.secondarySystemBackground) }

    // MARK: - Ringkasan

    private var summary: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if let img = vehicle.photo {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Image(systemName: "bicycle").font(.largeTitle).foregroundColor(.blue)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.name).font(.title2).bold()
                    Text(vehicle.model).foregroundColor(.secondary)
                }
                Spacer()
                Button { sheet = .editVehicle } label: { Image(systemName: "pencil") }
            }
            .padding()
            .background(cardBG)
            .cornerRadius(14)

            HStack {
                stat(Fmt.km(maint.odometerKm, decimals: 0), "ODO (km)")
                Divider().frame(height: 36)
                stat(fuel.levelL > 0 ? "\(rangeKm)" : "—", "Jarak tempuh BBM (km)")
                Divider().frame(height: 36)
                stat(maint.nearestRemainingKm.map { "\($0)" } ?? "—", "Perawatan (km)")
            }
            .padding()
            .background(cardBG)
            .cornerRadius(14)

            fuelCard

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { sheet = .odometer } label: { infoTile("ODO", Fmt.km(maint.odometerKm) + " km", "road.lanes") }
                infoTile("Aki", "— V", "bolt.fill")
                infoTile("Cairan pendingin", "— °C", "thermometer")
                infoTile("Kunci kontak", "—", "key.fill")
            }
            Text("ODO dihitung dari GPS selama perjalanan dan bisa Anda koreksi. Aki, suhu, dan kunci kontak terisi otomatis setelah link CCU selesai.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var rangeKm: Int {
        fuel.rangeKm(odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).bold()
            Text(label).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(.blue)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Text(value).font(.title3).bold().foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG)
        .cornerRadius(14)
    }

    private var fuelCard: some View {
        let remaining = fuel.remainingL(odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)
        let frac = vehicle.tankL > 0 ? min(1, max(0, remaining / vehicle.tankL)) : 0
        let kmplInfo = fuel.kmPerLSource(default: settings.defaultKmPerL)
        let kmpl = kmplInfo.value
        return VStack(alignment: .leading, spacing: 10) {
            Text("Sisa bahan bakar (perkiraan)").font(.headline)
            HStack {
                ForEach([("XMAX", 13.0), ("NMAX", 7.1)], id: \.0) { m in
                    Button {
                        vehicle.model = m.0
                        vehicle.tankL = m.1
                    } label: {
                        Text("\(m.0) · \(Fmt.liters(m.1))")
                            .font(.footnote).bold()
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(vehicle.model == m.0 ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(vehicle.model == m.0 ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(fuel.levelL > 0 ? "≈ \(rangeKm) km" : "— km").font(.largeTitle).bold()
                Spacer()
                Text(fuel.levelL > 0 ? "≈ \(Fmt.km(remaining)) / \(Fmt.km(vehicle.tankL)) L" : "Belum ada data")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: fuel.levelL > 0 ? frac : 0).tint(frac < 0.2 ? .red : .green)
            Text("Konsumsi dihitung ≈ \(Fmt.km(kmpl)) km/L (\(kmplInfo.source))." + (kmplInfo.source == "nilai bawaan" ? " Makin akurat setelah 3 kali isi, atau aktifkan konsumsi dari CCU di Pengaturan > Motor dan koneksi." : " Sisa bensin berkurang menurut konsumsi saat itu tiap motor berjalan."))
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack {
                Button {
                    fuel.markFull(odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)
                } label: { Label("Baru diisi", systemImage: "fuelpump.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button { sheet = .addLiters } label: { Label("Masukkan liter", systemImage: "drop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            Button { sheet = .setLevel } label: { Label("Atur sisa bensin manual", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Text("Ini hanya perkiraan: motor tidak melaporkan level bahan bakar. Pengisian sebagian akan membuat angka yang ditampilkan tidak akurat kecuali Anda memasukkan liternya.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(cardBG)
        .cornerRadius(14)
    }

    // MARK: - Perawatan

    private var maintenance: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(maint.items) { item in maintCard(item) }
            Button { sheet = .addMaint } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus").font(.title)
                    Text("Tambah item").bold()
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(cardBG)
                .cornerRadius(14)
            }
        }
    }

    private func maintCard(_ item: MaintItem) -> some View {
        let remaining = maint.remainingKm(item)
        let used = max(0, maint.odometerKm - item.lastServiceKm)
        let frac = min(1, used / Double(max(1, item.intervalKm)))
        let color: Color = remaining < 0 ? .red : (remaining < 500 ? .orange : .blue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.25), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(frac))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: item.icon).font(.footnote).foregroundColor(color)
                }
                .frame(width: 40, height: 40)
                Text(item.name).font(.headline).lineLimit(2)
            }
            Text(remaining < 0 ? "Terlambat \(-remaining) km" : "Sisa \(remaining) km")
                .font(.footnote).bold().foregroundColor(color)
            Text("Setiap \(item.intervalKm) km").font(.footnote).foregroundColor(.secondary)
            Button { sheet = .history(item.id) } label: { Text("Riwayat ›").font(.footnote) }
            Spacer(minLength: 0)
            HStack {
                Button { maint.markServiced(item.id) } label: {
                    Label("Diganti", systemImage: "checkmark").font(.footnote).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { sheet = .editMaint(item.id) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(cardBG)
        .cornerRadius(14)
    }

    // MARK: - Riwayat perjalanan

    private var history: some View {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let start: Date
        switch range {
        case 0: start = today
        case 1: start = cal.date(byAdding: .day, value: -6, to: today) ?? today
        default: start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? today
        }
        let list = trips.list(from: start, to: now.addingTimeInterval(1))
        let km = list.reduce(0.0) { $0 + $1.distanceKm }
        let sec = list.reduce(0.0) { $0 + $1.movingSec }
        let maxKmh = list.map { $0.maxKmh }.max() ?? 0
        let avg = sec > 0 ? km / (sec / 3600) : 0
        let kmpl = fuel.kmPerL(default: settings.defaultKmPerL)

        var days = [(String, Double, Bool)]()
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "E"
        for i in stride(from: 6, through: 0, by: -1) {
            let d0 = cal.date(byAdding: .day, value: -i, to: today) ?? today
            let d1 = cal.date(byAdding: .day, value: 1, to: d0) ?? d0
            let v = trips.list(from: d0, to: d1).reduce(0.0) { $0 + $1.distanceKm }
            days.append((f.string(from: d0), v, i == 0))
        }
        let peak = max(1, days.map { $0.1 }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $range) {
                Text("Hari ini").tag(0)
                Text("7 hari").tag(1)
                Text("Bulan ini").tag(2)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Jarak").font(.subheadline).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.km(km)).font(.system(size: 44, weight: .bold))
                    Text("km").font(.title3).foregroundColor(.secondary)
                }
                Text("\(Int((sec / 60).rounded())) menit berkendara").font(.footnote).foregroundColor(.secondary)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<days.count, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(days[i].1 > 0 ? "\(Int(days[i].1.rounded()))" : "").font(.caption2)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(days[i].2 ? Color.blue : Color.blue.opacity(0.35))
                            .frame(height: max(4, CGFloat(days[i].1 / peak) * 110))
                        Text(days[i].0).font(.caption2).foregroundColor(days[i].2 ? .blue : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                infoTile("Kecepatan tertinggi", "\(Int(maxKmh.rounded())) km/j", "speedometer")
                infoTile("Kecepatan rata-rata", "\(Int(avg.rounded())) km/j", "chart.line.uptrend.xyaxis")
                infoTile("Waktu berkendara", "\(Int((sec / 60).rounded())) menit", "clock.fill")
                infoTile("Rata-rata BBM", Fmt.km(100 / kmpl, decimals: 2) + " L/100km", "fuelpump.fill")
            }
            Text("Perjalanan dicatat otomatis selama dash tersambung (jarak dari GPS). Perjalanan di bawah 200 m diabaikan.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetView(_ s: MotorSheet) -> some View {
        switch s {
        case .editVehicle:
            VehicleEditSheet()
        case .odometer:
            NumberSheet(title: "ODO (km)", initial: maint.odometerKm) { maint.odometerKm = $0 }
        case .setLevel:
            NumberSheet(title: "Sisa bensin sekarang (L)", initial: fuel.remainingL(odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)) {
                fuel.setLevel($0, odo: maint.odometerKm, tank: vehicle.tankL)
            }
        case .addLiters:
            NumberSheet(title: "Liter yang diisi", initial: 0) {
                fuel.addLiters($0, odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)
            }
        case .addMaint:
            AddMaintSheet()
        case .history(let id):
            MaintHistorySheet(itemID: id)
        case .editMaint(let id):
            MaintEditSheet(itemID: id)
        }
    }
}

struct NumberSheet: View {
    let title: String
    let initial: Double
    let onSave: (Double) -> Void

    @Environment(\.presentationMode) private var presentation
    @State private var text = ""

    var body: some View {
        NavigationView {
            Form {
                TextField(title, text: $text).keyboardType(.decimalPad)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        let v = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
                        onSave(v)
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear { text = initial > 0 ? String(format: "%g", initial) : "" }
        }
    }
}

struct VehicleEditSheet: View {
    @EnvironmentObject var vehicle: VehicleStore
    @Environment(\.presentationMode) private var presentation
    @State private var picking = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Identitas")) {
                    TextField("Nama motor", text: $vehicle.name)
                    TextField("Model", text: $vehicle.model)
                    Stepper("Kapasitas tangki \(Fmt.liters(vehicle.tankL))", value: $vehicle.tankL, in: 3...30, step: 0.1)
                }
                Section {
                    Button("Pilih foto motor") { picking = true }
                }
            }
            .navigationTitle("Motor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { presentation.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $picking) {
                PhotoPicker(limit: 1) { imgs in
                    if let i = imgs.first { vehicle.setPhoto(i) }
                }
            }
        }
    }
}

struct AddMaintSheet: View {
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation
    @State private var name = ""
    @State private var interval = 5000

    var body: some View {
        NavigationView {
            Form {
                TextField("Nama item (mis. Ban depan)", text: $name)
                Stepper("Setiap \(interval) km", value: $interval, in: 500...60000, step: 500)
            }
            .navigationTitle("Tambah item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tambah") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { maint.addItem(name: n, intervalKm: interval) }
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct MaintHistorySheet: View {
    let itemID: String
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation

    var body: some View {
        NavigationView {
            List {
                let item = maint.items.first(where: { $0.id == itemID })
                if let item = item, !item.history.isEmpty {
                    ForEach(item.history) { log in
                        HStack {
                            Text(MaintHistorySheet.dateString(log.date))
                            Spacer()
                            Text("\(Int(log.odoKm)) km").foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Belum ada catatan penggantian.").foregroundColor(.secondary)
                }
            }
            .navigationTitle(maint.items.first(where: { $0.id == itemID })?.name ?? "Riwayat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }

    static func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

struct MaintEditSheet: View {
    let itemID: String
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation

    var body: some View {
        NavigationView {
            Form {
                if let i = maint.items.firstIndex(where: { $0.id == itemID }) {
                    Section {
                        TextField("Nama", text: $maint.items[i].name)
                        Stepper("Setiap \(maint.items[i].intervalKm) km", value: $maint.items[i].intervalKm,
                                in: 500...60000, step: 500)
                        Stepper("Diganti terakhir di \(Int(maint.items[i].lastServiceKm)) km",
                                value: $maint.items[i].lastServiceKm, in: 0...999999, step: 100)
                    }
                    Section {
                        Button("Hapus item", role: .destructive) {
                            maint.remove(itemID)
                            presentation.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Atur item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

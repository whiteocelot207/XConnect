import SwiftUI

enum MotorSheet: Identifiable {
    case addLiters
    case setLevel
    case addMaint
    case history(String)
    case replace(String)
    case editMaint(String)

    var id: String {
        switch self {
        case .addLiters: return "addLiters"
        case .setLevel: return "setLevel"
        case .addMaint: return "addMaint"
        case .history(let s): return "history-" + s
        case .replace(let s): return "replace-" + s
        case .editMaint(let s): return "edit-" + s
        }
    }
}

struct MotorView: View {
    @EnvironmentObject var maint: MaintenanceStore
    @EnvironmentObject var fuel: FuelStore
    @EnvironmentObject var vehicle: VehicleStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var live: VehicleLive
    @EnvironmentObject var trips: TripStore

    @State private var tab = 0
    @State private var range = 0
    @State private var sheet: MotorSheet?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $tab) {
                        Text(tr("Summary")).tag(0)
                        Text(tr("Maintenance")).tag(1)
                        Text(tr("Trip history")).tag(2)
                    }
                    .pickerStyle(.segmented)

                    if tab == 0 { summary }
                    else if tab == 1 { maintenance }
                    else { history }
                }
                .padding()
            }
            .navigationTitle(tr("Bike"))
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
                        MotorcycleIcon().frame(width: 46, height: 28).foregroundColor(.accentColor)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.name).font(.title2).bold()
                    if !vehicle.model.isEmpty { Text(vehicle.model).foregroundColor(.secondary) }
                }
                Spacer()
            }
            .padding()
            .background(cardBG)
            .cornerRadius(14)

            HStack {
                stat(Fmt.km(maint.odometerKm, decimals: 0), tr("ODO (km)"))
                Divider().frame(height: 36)
                stat(fuel.levelL > 0 ? "\(rangeKm)" : "—", tr("Fuel range (km)"))
                Divider().frame(height: 36)
                stat(maint.nearestRemainingKm.map { "\($0)" } ?? "—", tr("Maintenance (km)"))
            }
            .padding()
            .background(cardBG)
            .cornerRadius(14)

            fuelCard

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                infoTile("ODO", maint.odometerKm > 0 ? Fmt.km(maint.odometerKm) + " km" : "— km", "road.lanes")
                infoTile(tr("12V battery"), live.batteryV.map { String(format: "%.1f V", $0).localizedDecimal } ?? "— V", "bolt.fill",
                         color: live.batteryV.map { $0 >= settings.battGreenV ? .green : ($0 >= settings.battRedV ? .orange : .red) })
                infoTile(tr("Coolant"), live.coolantC.map { "\($0) °C" } ?? "— °C", "thermometer",
                         color: live.coolantC.map { $0 >= settings.tempRedC ? .red : ($0 >= settings.tempAmberC ? .orange : .primary) })
                infoTile(tr("Ignition"), live.ignitionOn.map { $0 ? "ON" : "OFF" } ?? "—", "key.fill",
                         color: live.ignitionOn.map { $0 ? .green : .primary })
            }
            Text(tr("ODO is read from the motorcycle CCU and cannot be edited. Battery, temperature, and ignition fill in automatically once the CCU link is up."))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    /// merah di bawah batas merah, kuning di bawah batas kuning (Pengaturan > Motor dan BBM)
    private var fuelColor: Color {
        rangeKm < settings.fuelRedKm ? .red : (rangeKm < settings.fuelAmberKm ? .orange : .green)
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

    private func infoTile(_ title: String, _ value: String, _ icon: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(.accentColor)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Text(value).font(.title3).bold().foregroundColor(color ?? .primary)
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
            Text(tr("Fuel left (estimate)")).font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(fuel.levelL > 0 ? "≈ \(rangeKm) km" : "— km").font(.largeTitle).bold().foregroundColor(fuel.levelL > 0 ? fuelColor : .primary)
                Spacer()
                Text(fuel.levelL > 0 ? "≈ \(Fmt.km(remaining)) / \(Fmt.km(vehicle.tankL)) L" : tr("No data yet"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: fuel.levelL > 0 ? frac : 0).tint(fuelColor)
            Text(tr("Consumption calculated ≈ {0} km/L ({1}).{2}", Fmt.km(kmpl), kmplInfo.source, kmplInfo.measured || kmplInfo.source != tr("default value") ? " " + tr("Fuel left decreases with the consumption at that moment each time the motorcycle runs.") : " " + tr("Enter the average fuel byte from the dash in Settings > Motorcycle and fuel so consumption follows your riding style.")))
                .font(.footnote)
                .foregroundColor(.secondary)
            if fuel.mayBeOff {
                Text(tr("The motorcycle has covered more than one tank without the app connected, so this figure may be wrong. At your next full fill-up, tap \"Just filled\" to start again."))
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
            HStack {
                Button {
                    fuel.markFull(odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)
                } label: { Label(tr("Just filled"), systemImage: "fuelpump.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button { sheet = .addLiters } label: { Label(tr("Enter liters"), systemImage: "drop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            Button { sheet = .setLevel } label: { Label(tr("Set fuel left manually"), systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Text(tr("This is only an estimate: the motorcycle does not report the tank level. Every time the tank is full, tap \"Just filled\". Partial fill-ups throw the figure off unless you enter the liters."))
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
                    Text(tr("Add item")).bold()
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(cardBG)
                .cornerRadius(14)
            }
        }
    }

    private func maintCard(_ item: MaintItem) -> some View {
        let st = maint.status(item)
        let color: Color = st.level == .over ? .red : (st.level == .warn ? .orange : .accentColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.25), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(st.fraction))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    MaintIconView(icon: item.icon, color: color, size: 15)
                }
                .frame(width: 40, height: 40)
                Text(item.title).font(.headline).lineLimit(2)
            }
            Text(st.text).font(.footnote).bold().foregroundColor(color)
            if item.basis == .km {
                Text(tr("Every {0} km", item.intervalKm)).font(.footnote).foregroundColor(.secondary)
            } else {
                if let due = item.effectiveDueDate {
                    Text(tr("Due on {0}", MaintHistorySheet.dateString(due))).font(.footnote).foregroundColor(.secondary)
                }
                if item.repeats {
                    Text(tr("Every {0}", MaintDraft.monthsLabel(item.intervalMonths))).font(.footnote).foregroundColor(.secondary)
                }
            }
            if let d = item.lastServiceDate {
                Text(tr("Last replaced {0}", MaintHistorySheet.dateString(d))).font(.footnote).foregroundColor(.secondary)
            }
            Button { sheet = .history(item.id) } label: { Text(tr("History ›")).font(.footnote) }
            Spacer(minLength: 0)
            HStack {
                Button { sheet = .replace(item.id) } label: {
                    Label(tr("Replaced"), systemImage: "checkmark").font(.footnote).frame(maxWidth: .infinity)
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
        f.locale = Loc.shared.locale
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
                Text(tr("Today")).tag(0)
                Text(tr("7 days")).tag(1)
                Text(tr("This month")).tag(2)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Distance")).font(.subheadline).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.km(km)).font(.system(size: 44, weight: .bold))
                    Text("km").font(.title3).foregroundColor(.secondary)
                }
                Text(tr("{0} minutes riding", Int((sec / 60).rounded()))).font(.footnote).foregroundColor(.secondary)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<days.count, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(days[i].1 > 0 ? "\(Int(days[i].1.rounded()))" : "").font(.caption2)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(days[i].2 ? Color.accentColor : Color.accentColor.opacity(0.35))
                            .frame(height: max(4, CGFloat(days[i].1 / peak) * 110))
                        Text(days[i].0).font(.caption2).foregroundColor(days[i].2 ? .accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                infoTile(tr("Top speed"), "\(Int(maxKmh.rounded())) " + tr("km/h"), "speedometer")
                infoTile(tr("Average speed"), "\(Int(avg.rounded())) " + tr("km/h"), "chart.line.uptrend.xyaxis")
                infoTile(tr("Riding time"), tr("{0} minutes", Int((sec / 60).rounded())), "clock.fill")
                infoTile(tr("Average fuel use"), Fmt.km(kmpl) + " km/L", "fuelpump.fill")
            }
            Text(tr("Trips are recorded automatically while the dash is connected (distance from GPS). Trips under 200 m are ignored."))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetView(_ s: MotorSheet) -> some View {
        switch s {
        case .setLevel:
            NumberSheet(title: tr("Fuel left now (L)"), initial: fuel.remainingL(odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)) {
                fuel.setLevel($0, odo: maint.odometerKm, tank: vehicle.tankL)
            }
        case .addLiters:
            NumberSheet(title: tr("Liters added"), initial: 0) {
                fuel.addLiters($0, odo: maint.odometerKm, tank: vehicle.tankL, def: settings.defaultKmPerL)
            }
        case .addMaint:
            AddMaintSheet()
        case .history(let id):
            MaintHistorySheet(itemID: id)
        case .replace(let id):
            MaintReplaceSheet(itemID: id)
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
                    Button(tr("Cancel")) { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save")) {
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

/// Isian angka yang diketik: menyimpan teks, mengubah ke angka saat berubah.
private func digits(_ s: String) -> Int? { Int(s.filter { $0.isNumber }) }
private func decimal(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

/// Isian form item perawatan (dipakai sheet Tambah dan Ubah). Urutan: nama, ikon, acuan, lalu isian menurut acuan.
struct MaintDraft {
    var name = ""
    var icon = "wrench.fill"
    var basis: MaintBasis = .km
    // acuan kilometer
    var intervalKmText = "5000"
    var lastKmText = ""
    var warnKm = 100
    // acuan waktu
    var repeats = false
    var intervalMonths = 12
    var warnMonths = 1
    var dueDate = Date()
    // keduanya
    var lastDate = Date()

    static func monthsLabel(_ m: Int) -> String {
        if m >= 12 && m % 12 == 0 { return m == 12 ? tr("1 year") : tr("{0} years", m / 12) }
        return m == 1 ? tr("1 month") : tr("{0} months", m)
    }

    init(odo: Double) {
        lastKmText = odo > 0 ? String(format: "%g", odo.rounded()) : ""
        recomputeDue()
    }

    init(item: MaintItem) {
        name = item.name
        icon = item.icon
        basis = item.basis
        intervalKmText = String(item.intervalKm)
        lastKmText = item.lastServiceKm > 0 ? String(format: "%g", item.lastServiceKm) : ""
        warnKm = item.warnKm
        repeats = item.repeats
        intervalMonths = item.intervalMonths
        warnMonths = item.warnMonths
        lastDate = item.lastServiceDate ?? Date()
        dueDate = item.effectiveDueDate ?? Date()
    }

    /// Jatuh tempo = tanggal terakhir + selang; masih bisa diubah manual di form.
    mutating func recomputeDue() {
        dueDate = Calendar.current.date(byAdding: .month, value: intervalMonths, to: lastDate) ?? lastDate
    }

    /// Terapkan isian ke item (nama item bawaan tidak diubah).
    func apply(to item: inout MaintItem) {
        if !item.isDefault { item.name = name.trimmingCharacters(in: .whitespaces) }
        item.icon = icon
        item.basis = basis
        item.intervalKm = max(1, Int(intervalKmText.filter { $0.isNumber }) ?? item.intervalKm)
        item.lastServiceKm = Double(lastKmText.replacingOccurrences(of: ",", with: ".")) ?? item.lastServiceKm
        item.warnKm = warnKm
        item.repeats = repeats
        item.intervalMonths = intervalMonths
        item.warnMonths = warnMonths
        // acuan waktu sekali jalan tidak punya "terakhir diganti"
        if basis == .km || repeats { item.lastServiceDate = lastDate }
        item.dueDate = dueDate
    }
}

struct MaintDraftForm: View {
    @Binding var draft: MaintDraft
    var isDefaultItem = false
    var defaultTitle = ""

    var body: some View {
        Section {
            if isDefaultItem {
                HStack {
                    Text(tr("Name"))
                    Spacer()
                    Text(defaultTitle).foregroundColor(.secondary)
                }
            } else {
                TextField(tr("Item name (e.g. Front tire)"), text: $draft.name)
            }
            NavigationLink(destination: MaintIconPicker(selection: $draft.icon)) {
                HStack {
                    Text(tr("Icon"))
                    Spacer()
                    MaintIconView(icon: draft.icon, size: 22)
                }
            }
        }
        Section(header: Text(tr("Schedule based on")),
                footer: Text(draft.basis == .km
                    ? tr("The reminder appears when the distance left is at or below the value you set for this item.")
                    : (draft.repeats
                        ? tr("Repeating: the next due date is calculated from the last replacement plus the interval. You can still change the due date by hand.")
                        : tr("One time: only a due date, for example the STNK validity. The reminder appears this long before it.")))) {
            Picker(tr("Schedule based on"), selection: $draft.basis) {
                Text(tr("Kilometers")).tag(MaintBasis.km)
                Text(tr("Time")).tag(MaintBasis.time)
            }
            .pickerStyle(.segmented)
            if draft.basis == .km {
                HStack {
                    Text(tr("Every (km)"))
                    TextField("5000", text: $draft.intervalKmText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text(tr("Last replaced at (km)"))
                    TextField("0", text: $draft.lastKmText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                DatePicker(tr("Last replaced on"), selection: $draft.lastDate, in: ...Date(), displayedComponents: .date)
                Stepper(tr("Remind {0} km before service", draft.warnKm), value: $draft.warnKm, in: 100...5000, step: 100)
            } else {
                Toggle(tr("Repeat"), isOn: $draft.repeats)
                    .onChange(of: draft.repeats) { on in if on { draft.recomputeDue() } }
                // selang dan tanggal terakhir hanya muncul (dan bisa dipilih) bila Berulang dinyalakan
                if draft.repeats {
                    Picker(tr("Every"), selection: $draft.intervalMonths) {
                        ForEach(MaintenanceStore.intervalMonthChoices, id: \.self) { Text(MaintDraft.monthsLabel($0)).tag($0) }
                    }
                    .onChange(of: draft.intervalMonths) { _ in draft.recomputeDue() }
                    DatePicker(tr("Last replaced on"), selection: $draft.lastDate, in: ...Date(), displayedComponents: .date)
                        .onChange(of: draft.lastDate) { _ in draft.recomputeDue() }
                }
                DatePicker(tr("Due date"), selection: $draft.dueDate, displayedComponents: .date)
                Picker(tr("Remind me"), selection: $draft.warnMonths) {
                    ForEach(MaintenanceStore.warnMonthChoices, id: \.self) {
                        Text(tr("{0} before", MaintDraft.monthsLabel($0))).tag($0)
                    }
                }
            }
        }
    }
}

struct AddMaintSheet: View {
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation
    @State private var draft = MaintDraft(odo: 0)

    var body: some View {
        NavigationView {
            Form { MaintDraftForm(draft: $draft) }
            .navigationTitle(tr("Add item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Add")) {
                        let n = draft.name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty {
                            var item = MaintItem(id: UUID().uuidString, name: n, icon: draft.icon, intervalKm: 5000,
                                                 lastServiceKm: maint.odometerKm, lastServiceDate: Date(), history: [])
                            draft.apply(to: &item)
                            if draft.lastKmText.isEmpty { item.lastServiceKm = maint.odometerKm }
                            maint.addItem(item)
                        }
                        presentation.wrappedValue.dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { draft = MaintDraft(odo: maint.odometerKm) }
        }
    }
}

/// Catat penggantian: tanggal bawaan hari ini, ODO bawaan pembacaan sekarang; keduanya bisa diubah/diketik.
struct MaintReplaceSheet: View {
    let itemID: String
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation
    @State private var date = Date()
    @State private var odoText = ""
    @State private var newDue = Date()

    private var item: MaintItem? { maint.items.first(where: { $0.id == itemID }) }
    private var needsNewDue: Bool { item.map { $0.basis == .time && !$0.repeats } ?? false }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(maint.items.first(where: { $0.id == itemID })?.title ?? ""),
                        footer: Text(tr("The date defaults to today and the ODO to the current reading from the CCU."))) {
                    DatePicker(tr("Replaced on"), selection: $date, in: ...Date(), displayedComponents: .date)
                    if maint.items.first(where: { $0.id == itemID })?.basis != .time {
                        HStack {
                            Text(tr("ODO when replaced (km)"))
                            TextField("0", text: $odoText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    if needsNewDue {
                        DatePicker(tr("New due date"), selection: $newDue, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(tr("Replaced"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save")) {
                        maint.markServiced(itemID, date: date, odoKm: decimal(odoText) ?? maint.odometerKm, newDue: needsNewDue ? newDue : nil)
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                odoText = maint.odometerKm > 0 ? String(format: "%g", maint.odometerKm.rounded()) : ""
                let base = max(item?.effectiveDueDate ?? Date(), Date())
                newDue = Calendar.current.date(byAdding: .year, value: 1, to: base) ?? base
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
                    Text(tr("No replacement records yet.")).foregroundColor(.secondary)
                }
            }
            .navigationTitle(maint.items.first(where: { $0.id == itemID })?.title ?? tr("History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }

    static func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Loc.shared.locale
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

struct MaintEditSheet: View {
    let itemID: String
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation
    @State private var draft = MaintDraft(odo: 0)
    @State private var loaded = false

    private var item: MaintItem? { maint.items.first(where: { $0.id == itemID }) }

    var body: some View {
        NavigationView {
            Form {
                if let it = item {
                    MaintDraftForm(draft: $draft, isDefaultItem: it.isDefault, defaultTitle: it.title)
                    if !it.isDefault {
                        Section {
                            Button(tr("Delete item"), role: .destructive) {
                                maint.remove(itemID)
                                presentation.wrappedValue.dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("Edit items"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) {
                        if let i = maint.items.firstIndex(where: { $0.id == itemID }) {
                            var it = maint.items[i]
                            draft.apply(to: &it)
                            maint.items[i] = it
                        }
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded, let it = item else { return }
                draft = MaintDraft(item: it)
                loaded = true
            }
        }
    }
}

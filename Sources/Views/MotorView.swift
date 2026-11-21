import SwiftUI

enum MotorSheet: Identifiable {
    case odometer
    case addLiters
    case setLevel
    case addMaint
    case history(String)
    case editMaint(String)

    var id: String {
        switch self {
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
                        Image(systemName: "bicycle").font(.largeTitle).foregroundColor(.accentColor)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.name).font(.title2).bold()
                    let sub = [vehicle.model, vehicle.year].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).foregroundColor(.secondary) }
                    if !vehicle.plate.isEmpty {
                        Text(vehicle.plate)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                    }
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
                Button { sheet = .odometer } label: { infoTile("ODO", Fmt.km(maint.odometerKm) + " km", "road.lanes") }
                infoTile(tr("12V battery"), "— V", "bolt.fill")
                infoTile(tr("Coolant"), "— °C", "thermometer")
                infoTile(tr("Ignition"), "—", "key.fill")
            }
            Text(tr("ODO is calculated from GPS while riding and you can correct it. Battery, temperature, and ignition fill in automatically once the CCU link is up."))
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
                Image(systemName: icon).foregroundColor(.accentColor)
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
            Text(tr("Fuel left (estimate)")).font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(fuel.levelL > 0 ? "≈ \(rangeKm) km" : "— km").font(.largeTitle).bold()
                Spacer()
                Text(fuel.levelL > 0 ? "≈ \(Fmt.km(remaining)) / \(Fmt.km(vehicle.tankL)) L" : tr("No data yet"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: fuel.levelL > 0 ? frac : 0).tint(frac < 0.2 ? .red : .green)
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
        let remaining = maint.remainingKm(item)
        let used = max(0, maint.odometerKm - item.lastServiceKm)
        let frac = min(1, used / Double(max(1, item.intervalKm)))
        let color: Color = remaining < 0 ? .red : (remaining < 500 ? .orange : .accentColor)
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
            Text(remaining < 0 ? tr("Overdue {0} km", -remaining) : tr("{0} km left", remaining))
                .font(.footnote).bold().foregroundColor(color)
            Text(tr("Every {0} km", item.intervalKm)).font(.footnote).foregroundColor(.secondary)
            Button { sheet = .history(item.id) } label: { Text(tr("History ›")).font(.footnote) }
            Spacer(minLength: 0)
            HStack {
                Button { maint.markServiced(item.id) } label: {
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
                infoTile(tr("Top speed"), "\(Int(maxKmh.rounded())) km/j", "speedometer")
                infoTile(tr("Average speed"), "\(Int(avg.rounded())) km/j", "chart.line.uptrend.xyaxis")
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
        case .odometer:
            NumberSheet(title: tr("ODO (km)"), initial: maint.odometerKm) { maint.odometerKm = $0 }
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

struct AddMaintSheet: View {
    @EnvironmentObject var maint: MaintenanceStore
    @Environment(\.presentationMode) private var presentation
    @State private var name = ""
    @State private var interval = 5000

    var body: some View {
        NavigationView {
            Form {
                TextField(tr("Item name (e.g. Front tire)"), text: $name)
                Stepper(tr("Every {0} km", interval), value: $interval, in: 500...60000, step: 500)
            }
            .navigationTitle(tr("Add item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Add")) {
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
                    Text(tr("No replacement records yet.")).foregroundColor(.secondary)
                }
            }
            .navigationTitle(maint.items.first(where: { $0.id == itemID })?.name ?? tr("History"))
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

    var body: some View {
        NavigationView {
            Form {
                if let i = maint.items.firstIndex(where: { $0.id == itemID }) {
                    Section {
                        TextField(tr("Name"), text: $maint.items[i].name)
                        Stepper(tr("Every {0} km", maint.items[i].intervalKm), value: $maint.items[i].intervalKm,
                                in: 500...60000, step: 500)
                        Stepper(tr("Last replaced at {0} km", Int(maint.items[i].lastServiceKm)),
                                value: $maint.items[i].lastServiceKm, in: 0...999999, step: 100)
                    }
                    Section {
                        Button(tr("Delete item"), role: .destructive) {
                            maint.remove(itemID)
                            presentation.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationTitle(tr("Edit items"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

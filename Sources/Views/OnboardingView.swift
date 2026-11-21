import SwiftUI

/// Pengaturan awal saat app dibuka pertama kali: sapaan selamat datang + pilih bahasa (langsung di tampilan pertama),
/// nama panggilan, pilih motor, perizinan.
struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vehicle: VehicleStore
    @EnvironmentObject var perms: PermissionCenter
    @State private var step = 0
    private let lastStep = 3

    private var isCustomModel: Bool {
        !VehicleStore.presets.contains { $0.model == vehicle.model }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    switch step {
                    case 0: welcome
                    case 1: nickname
                    case 2: motorcycle
                    default: permissions
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                if step > 0 {
                    Button(tr("Back")) { withAnimation { step -= 1 } }
                        .buttonStyle(.bordered)
                }
                Button {
                    if step < lastStep { withAnimation { step += 1 } } else { finish() }
                } label: {
                    Text(step == 0 ? tr("Get started") : (step < lastStep ? tr("Next") : tr("Finish")))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // Selesai baru aktif setelah semua izin diberikan
                .disabled(step == lastStep && !perms.allGranted)
            }
            .controlSize(.large)
            .padding(24)
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image("AppLogo")
                .resizable()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            Text(tr("Welcome to XConnect")).font(.largeTitle).bold().multilineTextAlignment(.center)
            Text(tr("Show the map, motorcycle data and music on your Yamaha dash. Let's set up the app in a few quick steps."))
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
            // bahasa ditanyakan langsung di tampilan pertama
            VStack(spacing: 10) {
                Label(tr("Choose your language"), systemImage: "globe").font(.headline)
                ForEach(Loc.shared.languages, id: \.code) { lang in
                    choiceRow(title: lang.name, selected: settings.language == lang.code) {
                        settings.language = lang.code
                    }
                }
                Text(tr("You can change this later in Settings > Appearance.")).font(.footnote).foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var nickname: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle").font(.system(size: 48)).foregroundColor(.accentColor)
            Text(tr("What should we call you?")).font(.title).bold().multilineTextAlignment(.center)
            Text(tr("This name is shown as a greeting on the dash. You can leave it empty and change it later in Settings > Appearance."))
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            TextField(tr("Nickname (shown on the dash)"), text: $settings.userName)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .padding(.top, 6)
        }
    }

    private var motorcycle: some View {
        VStack(spacing: 14) {
            MotorcycleIcon().frame(width: 84, height: 50).foregroundColor(.accentColor)
            Text(tr("Choose your motorcycle")).font(.title).bold().multilineTextAlignment(.center)
            Text(tr("This sets the tank capacity for the fuel estimate. You can change everything later in Settings > Motorcycle and fuel."))
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            ForEach(VehicleStore.presets, id: \.model) { p in
                choiceRow(title: p.model, selected: vehicle.model == p.model) { choose(p.model, tank: p.tankL) }
            }
            choiceRow(title: tr("Other motorcycle"), selected: isCustomModel) {
                if !isCustomModel { choose(tr("Other motorcycle"), tank: nil) }
            }
            VStack(spacing: 10) {
                // satu kolom saja: Nama motor (berlaku untuk XMAX, NMAX, maupun motor lain)
                TextField(tr("Motorcycle name"), text: $vehicle.name)
                Stepper(tr("Tank capacity {0}", Fmt.liters(vehicle.tankL)), value: $vehicle.tankL, in: 3...30, step: 0.1)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 6)
        }
    }

    private var permissions: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield").font(.system(size: 48)).foregroundColor(.accentColor)
            Text(tr("Allow access")).font(.title).bold().multilineTextAlignment(.center)
            Text(tr("XConnect needs these to work with your motorcycle. You can review them later in Settings > Permissions."))
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 10) { PermissionsList() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.06)))
            if !perms.allGranted {
                Text(tr("Tap Allow on every item to continue. Location must be set to Always."))
                    .font(.footnote).foregroundColor(.orange).multilineTextAlignment(.center)
            }
        }
    }

    private func choiceRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.headline).foregroundColor(.primary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(selected ? 0.14 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func choose(_ model: String, tank: Double?) {
        let oldIsDefaultName = vehicle.name.isEmpty || vehicle.name == vehicle.model
            || VehicleStore.presets.contains { $0.model == vehicle.name }
        let isPreset = VehicleStore.presets.contains { $0.model == model }
        vehicle.model = model
        if let t = tank { vehicle.tankL = t }
        // XMAX/NMAX: nama motor terisi otomatis; motor lain: nama dikosongkan agar diisi sendiri
        if oldIsDefaultName { vehicle.name = isPreset ? model : "" }
    }

    private func finish() {
        if vehicle.name.trimmingCharacters(in: .whitespaces).isEmpty { vehicle.name = vehicle.model }
        guard perms.allGranted else { return }
        settings.setupDone = true
    }
}

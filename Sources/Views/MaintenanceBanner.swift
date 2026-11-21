import SwiftUI

/// Banner melayang di atas layar bila ada item perawatan yang mendekati atau melewati jadwalnya, menurut acuan dan
/// batas peringatan masing-masing item (kilometer atau waktu; diatur di tab Motor > Perawatan). Ketuk untuk membuka
/// tab Motor; X menyembunyikannya sampai tingkatnya memburuk (mendekati -> terlambat) atau item diganti/diperpanjang.
struct MaintenanceBanner: View {
    @EnvironmentObject var maint: MaintenanceStore
    @EnvironmentObject var settings: AppSettings
    @Binding var tab: Int
    @State private var dismissed: [String: String] = (UserDefaults.standard.dictionary(forKey: "maint.bannerDismissed") as? [String: String]) ?? [:]

    private struct Due { let item: MaintItem; let status: MaintStatus; let key: String }

    private var due: [Due] {
        guard settings.setupDone, settings.maintNotify else { return [] }
        return maint.items.compactMap { item -> Due? in
            if item.basis == .km && maint.odometerKm <= 0 { return nil }
            let st = maint.status(item)
            guard st.level != .ok else { return nil }
            let stamp = item.basis == .km ? "\(item.lastServiceKm)" : "\(item.effectiveDueDate?.timeIntervalSince1970 ?? 0)"
            let key = (st.level == .over ? "over" : "warn") + "|" + stamp
            return dismissed[item.id] == key ? nil : Due(item: item, status: st, key: key)
        }
        .sorted { $0.status.level.rawValue > $1.status.level.rawValue }
    }

    var body: some View {
        Group {
            if let first = due.first {
                let overdue = first.status.level == .over
                HStack(spacing: 12) {
                    MaintIconView(icon: first.item.icon, color: overdue ? .red : .orange, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Maintenance due")).font(.subheadline).bold()
                        Text(first.item.title + ": " + first.status.text
                             + (due.count > 1 ? " · " + tr("+{0} more", due.count - 1) : ""))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundColor(.secondary).padding(8)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .onTapGesture { tab = 2 }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: due.first?.key)
    }

    private func dismiss() {
        for d in due { dismissed[d.item.id] = d.key }
        UserDefaults.standard.set(dismissed, forKey: "maint.bannerDismissed")
    }
}

import SwiftUI

/// Banner melayang di atas layar bila ada item perawatan yang mendekati atau melewati jadwal servis
/// (batas pengingat di Pengaturan > Motor dan BBM). Ketuk untuk membuka tab Motor; X menyembunyikannya
/// sampai tingkatnya memburuk (mendekati -> terlambat) atau item diganti.
struct MaintenanceBanner: View {
    @EnvironmentObject var maint: MaintenanceStore
    @EnvironmentObject var settings: AppSettings
    @Binding var tab: Int
    @State private var dismissed: [String: String] = (UserDefaults.standard.dictionary(forKey: "maint.bannerDismissed") as? [String: String]) ?? [:]

    private struct Due { let item: MaintItem; let remaining: Int; let key: String }

    private var due: [Due] {
        guard settings.setupDone, settings.maintNotify, maint.odometerKm > 0 else { return [] }
        return maint.items.compactMap { item -> Due? in
            let rem = maint.remainingKm(item)
            guard rem <= settings.maintWarnKm else { return nil }
            let key = (rem < 0 ? "over" : "warn") + "|\(item.lastServiceKm)"
            return dismissed[item.id] == key ? nil : Due(item: item, remaining: rem, key: key)
        }
        .sorted { $0.remaining < $1.remaining }
    }

    var body: some View {
        Group {
            if let first = due.first {
                let overdue = first.remaining < 0
                HStack(spacing: 12) {
                    Image(systemName: "wrench.fill").font(.title2).foregroundColor(overdue ? .red : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Maintenance due")).font(.subheadline).bold()
                        Text(overdue ? tr("{0}: overdue {1} km", first.item.title, -first.remaining)
                                     : tr("{0}: {1} km left", first.item.title, first.remaining)
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

import SwiftUI

/// Banner melayang di atas layar bila ada versi baru di GitHub Releases. Ketuk untuk membuka Pengaturan,
/// tombol X menyembunyikannya sampai ada versi yang lebih baru lagi.
struct UpdateBanner: View {
    @EnvironmentObject var updater: UpdateService
    @EnvironmentObject var settings: AppSettings
    @Binding var tab: Int
    @AppStorage("update.dismissed") private var dismissed = ""

    private var version: String? {
        guard settings.setupDone, updater.updateAvailable, let v = updater.latest?.version, !v.isEmpty, v != dismissed else { return nil }
        return v
    }

    var body: some View {
        Group {
            if let v = version {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Update available")).font(.subheadline).bold()
                        Text(tr("XConnect {0} · tap to open Settings > About", v)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation { dismissed = v } } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundColor(.secondary).padding(8)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .onTapGesture { tab = 3 }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: version)
    }
}

import SwiftUI

/// Satu baris izin: ikon, judul, keterangan, status, dan tombol aksi.
struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: PermissionCenter.Status
    let action: () -> Void

    private var statusText: String {
        switch status {
        case .granted: return tr("Allowed")
        case .notDetermined: return tr("Not asked yet")
        case .whenInUse: return tr("While using the app only")
        case .denied: return tr("Denied")
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .whenInUse: return .orange
        case .denied: return .red
        case .notDetermined: return .secondary
        }
    }

    private var buttonTitle: String {
        switch status {
        case .notDetermined: return tr("Allow")
        case .whenInUse: return tr("Allow Always")
        default: return tr("Open Settings")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundColor(.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(statusText).font(.footnote.weight(.semibold)).foregroundColor(statusColor)
            }
            Spacer(minLength: 8)
            if status == .granted {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
            } else {
                Button(buttonTitle, action: action).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Daftar izin yang dipakai XConnect (dipakai di pengaturan awal dan di Pengaturan).
struct PermissionsList: View {
    @EnvironmentObject var perms: PermissionCenter

    var body: some View {
        Group {
            PermissionRow(icon: "location.fill", title: tr("Location"),
                          detail: tr("Needed for the map, navigation and auto-connect. Choose \"Always\" so the app can connect when the motorcycle is switched on, even with the phone locked."),
                          status: perms.location) { perms.requestLocation() }
            PermissionRow(icon: "antenna.radiowaves.left.and.right", title: tr("Bluetooth"),
                          detail: tr("Connects to the motorcycle CCU to read battery, ODO and temperature, and wakes the app when the motorcycle is switched on."),
                          status: perms.bluetooth) { perms.requestBluetooth() }
            PermissionRow(icon: "music.note", title: tr("Music"),
                          detail: tr("Shows the playing song on the dash and lets the handlebar buttons control playback (Media & Apple Music)."),
                          status: perms.music) { perms.requestMusic() }
            PermissionRow(icon: "photo.on.rectangle", title: tr("Photos"),
                          detail: tr("Lets you pick photos from your gallery for the dash Photos screen and the motorcycle photo."),
                          status: perms.photos) { perms.requestPhotos() }
            PermissionRow(icon: "bell.fill", title: tr("Notifications"),
                          detail: tr("Maintenance and document (e.g. driver's license) reminders."),
                          status: perms.notifications) { perms.requestNotifications() }
        }
        .onAppear { perms.refresh() }
    }
}

struct PermissionsSettings: View {
    var body: some View {
        Form {
            Section(footer: Text(tr("If a permission was denied, iOS only lets you change it in the iOS Settings app. \"Allow Always\" for Location is what lets the app connect when the phone is locked."))) {
                PermissionsList()
            }
        }
        .navigationTitle(tr("Permissions"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

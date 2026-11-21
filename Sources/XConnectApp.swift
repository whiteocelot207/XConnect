import SwiftUI

@main
struct XConnectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    private let app = AppModel.shared
    @ObservedObject private var settings = AppModel.shared.settings
    @State private var tab = 0

    private var scheme: ColorScheme? {
        switch settings.theme {
        case 1: return .dark
        case 2: return .light
        default: return nil
        }
    }

    var body: some View {
        ContentView(tab: $tab)
            .id(settings.language)        // bahasa berubah: bangun ulang tampilan dengan teks baru
            .environmentObject(app.settings)
            .environmentObject(app.bike)
            .environmentObject(app.nav)
            .environmentObject(app.places)
            .environmentObject(app.maint)
            .environmentObject(app.fuel)
            .environmentObject(app.vehicle)
            .environmentObject(app.trips)
            .environmentObject(app.weather)
            .environmentObject(app.music)
            .environmentObject(app.slides)
            .environmentObject(app.updater)
            .environmentObject(app.bike.vehicleLive)
            .preferredColorScheme(scheme)
            .accentColor(AppTheme.theme(settings.colorTheme).color)
            .tint(AppTheme.theme(settings.colorTheme).color)
            .onAppear {
                if app.settings.autoCheckUpdate, !app.settings.updateRepo.isEmpty {
                    app.updater.check(repo: app.settings.updateRepo, silent: true)
                }
            }
    }
}

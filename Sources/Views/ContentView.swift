import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nav: NavigationController
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(openSettings: { tab = 3 })
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            NavigateView()
                .tabItem { Label("Navigasi", systemImage: "location.fill") }
                .tag(1)
            MotorView()
                .tabItem { Label("Motor", systemImage: "gauge") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Pengaturan", systemImage: "gearshape") }
                .tag(3)
        }
        .onChange(of: nav.destination?.id) { id in
            if id != nil { tab = 1 }
        }
    }
}

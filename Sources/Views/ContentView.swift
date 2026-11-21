import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nav: NavigationController
    @Binding var tab: Int

    var body: some View {
        TabView(selection: $tab) {
            HomeView(openSettings: { tab = 3 })
                .tabItem { Label(tr("Home"), systemImage: "house") }
                .tag(0)
            NavigateView()
                .tabItem { Label(tr("Navigate"), systemImage: "location.fill") }
                .tag(1)
            MotorView()
                .tabItem { Label(tr("Bike"), systemImage: "gauge") }
                .tag(2)
            SettingsView()
                .tabItem { Label(tr("Settings"), systemImage: "gearshape") }
                .tag(3)
        }
        .onChange(of: nav.destination?.id) { id in
            if id != nil { tab = 1 }
        }
    }
}

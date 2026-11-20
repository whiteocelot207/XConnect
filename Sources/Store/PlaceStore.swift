import Foundation
import CoreLocation

struct Place: Codable, Identifiable, Equatable {
    var name: String
    var subtitle: String
    var lat: Double
    var lon: Double

    var id: String { String(format: "%.5f,%.5f", lat, lon) }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

final class PlaceStore: ObservableObject {
    private struct Stored: Codable {
        var home: Place?
        var work: Place?
        var favorites: [Place]
        var recents: [Place]
    }

    @Published var home: Place? { didSet { save() } }
    @Published var work: Place? { didSet { save() } }
    @Published var favorites: [Place] { didSet { save() } }
    @Published var recents: [Place] { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: "places.v1"),
           let s = try? JSONDecoder().decode(Stored.self, from: d) {
            home = s.home
            work = s.work
            favorites = s.favorites
            recents = s.recents
        } else {
            home = nil
            work = nil
            favorites = []
            recents = []
        }
    }

    /// Muat ulang dari UserDefaults (setelah memulihkan cadangan).
    func reload() {
        if let d = UserDefaults.standard.data(forKey: "places.v1"),
           let s = try? JSONDecoder().decode(Stored.self, from: d) {
            home = s.home
            work = s.work
            favorites = s.favorites
            recents = s.recents
        } else {
            home = nil
            work = nil
            favorites = []
            recents = []
        }
    }

    private func save() {
        let s = Stored(home: home, work: work, favorites: favorites, recents: recents)
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: "places.v1")
        }
    }

    func addRecent(_ p: Place) {
        var list = recents.filter { $0.id != p.id }
        list.insert(p, at: 0)
        recents = Array(list.prefix(15))
    }

    func isFavorite(_ p: Place) -> Bool {
        favorites.contains(where: { $0.id == p.id })
    }

    func renameFavorite(_ p: Place, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = favorites.firstIndex(where: { $0.id == p.id }) else { return }
        favorites[i].name = n
    }

    func toggleFavorite(_ p: Place) {
        if isFavorite(p) {
            favorites = favorites.filter { $0.id != p.id }
        } else {
            favorites.append(p)
        }
    }
}

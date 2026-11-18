import Foundation
import UIKit

final class VehicleStore: ObservableObject {
    @Published var name: String { didSet { UserDefaults.standard.set(name, forKey: "veh.name") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "veh.model") } }
    @Published var tankL: Double { didSet { UserDefaults.standard.set(tankL, forKey: "veh.tank") } }
    @Published var photo: UIImage?

    private static var photoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("motor.jpg")
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["veh.name": "XMAX", "veh.model": "XMAX", "veh.tank": 13.0])
        name = d.string(forKey: "veh.name") ?? "XMAX"
        model = d.string(forKey: "veh.model") ?? "XMAX"
        tankL = d.double(forKey: "veh.tank")
        if let data = try? Data(contentsOf: VehicleStore.photoURL) { photo = UIImage(data: data) }
    }

    func setPhoto(_ img: UIImage) {
        photo = img
        if let data = img.jpegData(compressionQuality: 0.8) {
            try? data.write(to: VehicleStore.photoURL)
        }
    }
}

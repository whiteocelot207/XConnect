import Foundation
import UIKit

final class VehicleStore: ObservableObject {
    @Published var name: String { didSet { UserDefaults.standard.set(name, forKey: "veh.name") } }
    /// tipe motor: "XMAX", "NMAX", atau teks bebas untuk motor lain
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "veh.model") } }
    @Published var tankL: Double { didSet { UserDefaults.standard.set(tankL, forKey: "veh.tank") } }
    @Published var photo: UIImage?

    /// Tipe bawaan beserta kapasitas tangkinya (liter).
    static let presets: [(model: String, tankL: Double)] = [("XMAX", 13.0), ("NMAX", 7.1)]

    static var photoURL: URL {
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

    /// Muat ulang dari UserDefaults dan file foto (setelah memulihkan cadangan).
    func reload() {
        let d = UserDefaults.standard
        name = d.string(forKey: "veh.name") ?? "XMAX"
        model = d.string(forKey: "veh.model") ?? "XMAX"
        tankL = d.double(forKey: "veh.tank")
        if let data = try? Data(contentsOf: VehicleStore.photoURL) { photo = UIImage(data: data) } else { photo = nil }
    }

    func setPhoto(_ img: UIImage) {
        let small = VehicleStore.scaled(img, maxSide: 1200)
        photo = small
        if let data = small.jpegData(compressionQuality: 0.8) {
            try? data.write(to: VehicleStore.photoURL)
        }
    }

    func removePhoto() {
        photo = nil
        try? FileManager.default.removeItem(at: VehicleStore.photoURL)
    }

    private static func scaled(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(img.size.width, img.size.height)
        guard longest > maxSide else { return img }
        let k = maxSide / longest
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

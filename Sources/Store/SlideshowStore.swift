import Foundation
import UIKit

/// Foto untuk mode slideshow di dash (disimpan sudah diperkecil di folder Documents/slides).
final class SlideshowStore: ObservableObject {
    @Published var files = [String]()

    private var cache: (name: String, img: UIImage)?

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("slides")
    }

    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let list = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        files = list.filter { $0.hasSuffix(".jpg") }.sorted()
    }

    func add(_ images: [UIImage]) {
        for img in images {
            let small = SlideshowStore.scaled(img, maxWidth: 960)
            guard let data = small.jpegData(compressionQuality: 0.8) else { continue }
            let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(4)).jpg"
            try? data.write(to: dir.appendingPathComponent(name))
        }
        reload()
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        if cache?.name == name { cache = nil }
        reload()
    }

    func image(for name: String) -> UIImage? {
        if let c = cache, c.name == name { return c.img }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)), let img = UIImage(data: data) else {
            return nil
        }
        cache = (name, img)
        return img
    }

    /// Foto yang aktif sekarang; berganti tiap `interval` detik berdasarkan jam, tanpa state tambahan.
    func current(interval: Int) -> UIImage? {
        guard !files.isEmpty else { return nil }
        let idx = (Int(Date().timeIntervalSince1970) / max(2, interval)) % files.count
        return image(for: files[idx])
    }

    private static func scaled(_ img: UIImage, maxWidth: CGFloat) -> UIImage {
        guard img.size.width > maxWidth else { return img }
        let k = maxWidth / img.size.width
        let size = CGSize(width: maxWidth, height: img.size.height * k)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

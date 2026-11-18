import SwiftUI
import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    var limit: Int
    var onPick: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        cfg.filter = .images
        cfg.selectionLimit = limit
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([UIImage]) -> Void
        init(_ f: @escaping ([UIImage]) -> Void) { onPick = f }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var images = [UIImage]()
            let lock = NSLock()
            let group = DispatchGroup()
            for r in results where r.itemProvider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                r.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let i = obj as? UIImage {
                        lock.lock()
                        images.append(i)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { [onPick] in onPick(images) }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

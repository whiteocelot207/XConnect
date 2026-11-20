import Foundation
import CallKit

/// Memantau panggilan telepon: sedang berbicara, dan panggilan masuk yang tidak terangkat (misscall).
/// Panggilan masuk yang berakhir tanpa pernah tersambung dihitung tidak terangkat (termasuk yang ditolak).
final class CallWatcher: NSObject, CXCallObserverDelegate {
    private static let key = "xc.missedCall"
    private let observer = CXCallObserver()
    var onChange: (() -> Void)?

    /// Ada panggilan tak terangkat yang belum ditangani. Tersimpan, jadi tetap ada setelah app ditutup.
    /// iOS tidak memberi app akses ke daftar panggilan/lencana "panggilan tak terjawab" di app Telepon, jadi ikon tidak bisa tahu
    /// kapan riwayat dibuka. Ikon dianggap selesai bila ada panggilan keluar atau panggilan masuk yang diangkat sesudahnya
    /// (artinya sudah ditangani), atau bila diketuk di pratinjau.
    private(set) var hasMissed: Bool = UserDefaults.standard.bool(forKey: CallWatcher.key) {
        didSet { UserDefaults.standard.set(hasMissed, forKey: CallWatcher.key) }
    }

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    var inCall: Bool { observer.calls.contains { !$0.hasEnded } }

    func clearMissed() {
        guard hasMissed else { return }
        hasMissed = false
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        if call.hasEnded && !call.isOutgoing && !call.hasConnected {
            hasMissed = true                       // masuk, berakhir tanpa terangkat (termasuk ditolak)
        } else if call.isOutgoing || call.hasConnected {
            hasMissed = false                      // menelepon balik / mengangkat panggilan: sudah ditangani
        }
        onChange?()
    }
}

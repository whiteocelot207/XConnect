import Foundation
import UIKit
import MediaPlayer
import AVFoundation

/// Membaca lagu yang sedang diputar di app Musik (Apple Music). App lain seperti Spotify tidak
/// membagikan info lagunya ke app pihak ketiga di iOS.
final class MusicService: ObservableObject {
    @Published var info = MusicInfo()
    @Published var authorized = false

    /// catatan ke Log (perintah media dari dash, perubahan volume, ganti lagu)
    var onLog: (String) -> Void = { _ in }

    private var timer: Timer?
    private var artID: UInt64 = 0
    private var art: UIImage?
    private var monitoring = false
    private var volObs: NSKeyValueObservation?

    init() {
        authorized = MPMediaLibrary.authorizationStatus() == .authorized
    }

    private static func stateName(_ s: MPMusicPlaybackState) -> String {
        switch s {
        case .playing: return "diputar"
        case .paused: return "jeda"
        case .stopped: return "berhenti"
        case .interrupted: return "terputus"
        case .seekingForward: return "maju cepat"
        case .seekingBackward: return "mundur cepat"
        @unknown default: return "?"
        }
    }

    /// Mencatat ke Log semua yang terjadi pada pemutar musik: ganti lagu, putar/jeda, maju/mundur cepat,
    /// perubahan volume. Tombol next/prev/OK di dash lewat Bluetooth (AVRCP) langsung diproses iOS,
    /// jadi hasilnya terlihat di sini walau tidak ada pesan iAP dari dash.
    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        activateAudioSession()
        let p = MPMusicPlayerController.systemMusicPlayer
        p.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        nc.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: p, queue: .main) { [weak self] _ in
            self?.onLog("Musik: status \(MusicService.stateName(p.playbackState))")
        }
        nc.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: p, queue: .main) { [weak self] _ in
            self?.onLog("Musik: lagu berganti → \(p.nowPlayingItem?.title ?? "-")")
        }
        volObs = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            DispatchQueue.main.async { self?.onLog("Volume sistem berubah → \(Int((v * 100).rounded()))%") }
        }
        // sesi audio bisa lepas (telepon, Siri, app lain): aktifkan lagi supaya volume tetap terbaca
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.activateAudioSession()
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let t = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if t == .ended { self?.activateAudioSession() }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.activateAudioSession()
        }
        registerRemoteCommands()
    }

    /// iOS hanya memperbarui AVAudioSession.outputVolume (dan KVO-nya) bila sesi audio AKTIF.
    /// Kategori ambient + mixWithOthers: tidak menghentikan atau mengganggu musik yang sedang diputar.
    func activateAudioSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
        } catch {
            onLog("Sesi audio gagal aktif: \(error.localizedDescription)")
        }
    }

    /// Volume sistem 0...1 untuk kotak "Volume HP" di dash.
    var systemVolume: Float { AVAudioSession.sharedInstance().outputVolume }

    private func registerRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        let p = MPMusicPlayerController.systemMusicPlayer
        c.playCommand.addTarget { [weak self] _ in
            self?.onLog("Perintah media: putar")
            p.play()
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.onLog("Perintah media: jeda")
            p.pause()
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onLog("Perintah media: putar/jeda (OK)")
            if p.playbackState == .playing { p.pause() } else { p.play() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.onLog("Perintah media: lagu berikutnya")
            p.skipToNextItem()
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.onLog("Perintah media: lagu sebelumnya")
            p.skipToPreviousItem()
            return .success
        }
        c.seekForwardCommand.addTarget { [weak self] ev in
            let begin = (ev as? MPSeekCommandEvent)?.type == .beginSeeking
            self?.onLog("Perintah media: tahan next (\(begin ? "mulai" : "selesai"))")
            if begin { p.beginSeekingForward() } else { p.endSeeking() }
            return .success
        }
        c.seekBackwardCommand.addTarget { [weak self] ev in
            let begin = (ev as? MPSeekCommandEvent)?.type == .beginSeeking
            self?.onLog("Perintah media: tahan previous (\(begin ? "mulai" : "selesai"))")
            if begin { p.beginSeekingBackward() } else { p.endSeeking() }
            return .success
        }
    }

    func requestAccess() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorized = status == .authorized
                self?.refresh()
            }
        }
    }

    func start() {
        stop()
        activateAudioSession()
        ensureVolumeView()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard authorized else {
            if !info.title.isEmpty { info = MusicInfo() }
            return
        }
        let p = MPMusicPlayerController.systemMusicPlayer
        guard let item = p.nowPlayingItem else {
            if !info.title.isEmpty { info = MusicInfo() }
            return
        }
        if item.persistentID != artID {
            artID = item.persistentID
            art = item.artwork?.image(at: CGSize(width: 300, height: 300))
        }
        info = MusicInfo(title: item.title ?? "", artist: item.artist ?? "",
                         duration: item.playbackDuration, position: p.currentPlaybackTime,
                         playing: p.playbackState == .playing, artwork: art)
    }

    // MARK: - Kendali dari stang

    private var volumeView: MPVolumeView?

    /// MPVolumeView harus ada di jendela aktif supaya slider volume sistemnya bisa dipakai.
    private func ensureVolumeView() {
        if let v = volumeView, v.window != nil { return }
        volumeView?.removeFromSuperview()
        let v = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
        v.alpha = 0.01
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.addSubview(v)
        volumeView = v
    }

    /// Ubah volume sistem lewat slider MPVolumeView (satu-satunya cara resmi di iOS).
    /// Mengembalikan volume baru (0...1), atau nil bila slider belum tersedia.
    /// Catatan: hanya andal saat app aktif di layar; iOS membatasi cara ini di latar belakang.
    @discardableResult
    func adjustVolume(up: Bool) -> Float? {
        ensureVolumeView()
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return nil }
        let sys = AVAudioSession.sharedInstance().outputVolume
        let base = sys > 0 ? sys : slider.value
        let target = min(1, max(0, base + (up ? 0.0625 : -0.0625)))
        slider.setValue(target, animated: false)
        slider.sendActions(for: .valueChanged)
        slider.sendActions(for: .touchUpInside)
        return target
    }

    func next() { MPMusicPlayerController.systemMusicPlayer.skipToNextItem() }
    func previous() { MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem() }
    func togglePlay() {
        let p = MPMusicPlayerController.systemMusicPlayer
        if p.playbackState == .playing { p.pause() } else { p.play() }
    }
}

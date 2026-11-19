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
    private var keepAlivePlayer: AVAudioPlayer?
    /// pengaturan "Jaga data HP tetap hidup" dan status dash; audio senyap hanya berputar bila keduanya true
    var keepAliveEnabled = true
    var dashConnected = false

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
            self?.updateKeepAlive()
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let t = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            self?.onLog("Audio: interupsi \(t == .began ? "mulai" : "selesai")")
            if t == .ended { self?.updateKeepAlive() }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keepAlivePlayer = nil
            self?.updateKeepAlive()
        }
        // catatan di Log untuk menelusuri bila musik berhenti saat suara petunjuk arah berbunyi
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let r = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            self?.onLog("Audio: rute berubah (alasan \(r))")
        }
        nc.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { [weak self] n in
            let t = (n.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt) ?? 99
            self?.onLog("Audio: app lain meminta audio lain diam (tipe \(t))")
        }
        registerRemoteCommands()
    }

    /// iOS hanya memperbarui AVAudioSession.outputVolume (dan KVO-nya) bila sesi audio AKTIF, dan sesi ambient
    /// ikut mati saat app pindah ke latar belakang atau layar terkunci. Saat dash tersambung dipakai kategori
    /// playback + mixWithOthers dengan audio senyap (mode latar "audio"), jadi volume dan data HP lain terus berubah.
    /// mixWithOthers: musik yang sedang diputar tidak terganggu.
    func activateAudioSession() {
        if guidanceActive { return }          // suara petunjuk arah sedang memegang sesi
        let s = AVAudioSession.sharedInstance()
        do {
            // selalu playback + mixWithOthers (tidak berpindah-pindah kategori, karena perpindahan itu bisa
            // menghentikan pemutar musik); tanpa audio yang diputar, sesi ini tidak mengganggu app lain
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
        } catch {
            onLog("Sesi audio gagal aktif: \(error.localizedDescription)")
        }
    }

    /// Nyalakan/matikan audio senyap sesuai pengaturan dan status dash.
    func updateKeepAlive() {
        if guidanceActive { return }
        activateAudioSession()
        if keepAliveEnabled && (dashConnected || navActive) {
            if keepAlivePlayer == nil {
                keepAlivePlayer = try? AVAudioPlayer(data: MusicService.silentWAV())
                keepAlivePlayer?.numberOfLoops = -1
                keepAlivePlayer?.volume = 0
                keepAlivePlayer?.prepareToPlay()
            }
            if let p = keepAlivePlayer, !p.isPlaying {
                if !p.play() { onLog("Audio senyap gagal diputar (data HP di latar belakang bisa tertahan)") }
            }
        } else if let p = keepAlivePlayer {
            p.stop()
            keepAlivePlayer = nil
        }
    }

    // MARK: - Suara petunjuk arah

    private var guidanceActive = false
    /// true selama navigasi berjalan: audio senyap dijaga hidup supaya sesi audio tidak berubah saat suara berbunyi
    var navActive = false

    /// Dipanggil sebelum suara petunjuk arah. Kategori sesi tidak diubah, sesi tidak dilepas, dan audio senyap
    /// tidak dihentikan (semua itu bisa membuat pemutar musik berhenti). Dengan `duck`, volume ponsel
    /// diturunkan sendiri ke `level` (mis. 0,5 = separuh dari volume sekarang) selama suara berbunyi, lalu
    /// dikembalikan di `endGuidanceAudio`.
    func beginGuidanceAudio(duck: Bool, level: Float) {
        activateAudioSession()                 // sama seperti biasa: playback + mixWithOthers
        guidanceActive = true
        let s = AVAudioSession.sharedInstance()
        guard duck, duckedFrom == nil else { return }
        let orig = s.outputVolume
        guard orig > 0.02 else { return }
        let target = max(0.02, orig * min(max(level, 0.1), 1.0))
        duckedFrom = orig
        duckedTo = target
        SystemVolume.set(target)
    }

    /// Dipanggil setelah suara selesai: volume dikembalikan, lalu pengaturan audio app seperti semula.
    func endGuidanceAudio() {
        guard guidanceActive else { return }
        restoreVolume()
        finishGuidanceAudio()
    }

    private var duckedFrom: Float?
    private var duckedTo: Float = 0

    /// Kembalikan volume ke nilai sebelum diturunkan, kecuali pengguna sudah mengubahnya sendiri (tombol volume).
    private func restoreVolume() {
        guard let orig = duckedFrom else { return }
        duckedFrom = nil
        let now = AVAudioSession.sharedInstance().outputVolume
        if abs(now - duckedTo) < 0.08 { SystemVolume.set(orig) }
    }

    private func finishGuidanceAudio() {
        guidanceActive = false
        updateKeepAlive()
    }

    /// WAV mono 8 kHz, 1 detik, semua nol (senyap).
    private static func silentWAV() -> Data {
        let rate: UInt32 = 8000
        let dataSize: UInt32 = 8000 * 2
        var b = [UInt8]()
        func u32(_ v: UInt32) { b += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        func u16(_ v: UInt16) { b += [UInt8(v & 0xFF), UInt8(v >> 8)] }
        b += Array("RIFF".utf8); u32(36 + dataSize); b += Array("WAVE".utf8)
        b += Array("fmt ".utf8); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        b += Array("data".utf8); u32(dataSize)
        b += [UInt8](repeating: 0, count: Int(dataSize))
        return Data(b)
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


/// Mengatur volume sistem lewat MPVolumeView tersembunyi (satu-satunya cara di iOS untuk mengubah volume dari app).
enum SystemVolume {
    private static let view: MPVolumeView = {
        let v = MPVolumeView(frame: CGRect(x: -3000, y: -3000, width: 10, height: 10))
        v.alpha = 0.01
        v.isUserInteractionEnabled = false
        return v
    }()

    static func set(_ value: Float) {
        let apply = {
            if view.superview == nil {
                let win = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow } ?? UIApplication.shared.windows.first
                win?.addSubview(view)
            }
            view.layoutIfNeeded()
            if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
                slider.value = min(max(0, value), 1)
                slider.sendActions(for: .valueChanged)
            }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        // pemasangan pertama: slider baru muncul setelah layout, ulangi sekali
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { apply() }
    }
}

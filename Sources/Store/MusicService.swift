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
    /// volume sistem berubah (tombol HP, Control Center, atau slider dari stang): diteruskan ke BikeController untuk dikirim ke dash
    var onSystemVolume: (Float) -> Void = { _ in }
    /// volume sistem terakhir yang diketahui dari KVO/notifikasi/slider (lebih mutakhir daripada outputVolume yang bisa basi)
    private var knownVolume: Float?
    private var lastViewVolume: Float?
    private var keepAlivePlayer: AVAudioPlayer?
    /// pengaturan "Jaga data HP tetap hidup" dan status dash; audio senyap hanya berputar bila keduanya true
    var keepAliveEnabled = true
    var dashConnected = false
    /// Handler MPRemoteCommandCenter (putar/jeda/next/prev) dari dash. Default MATI: NConnect (jalur Yamaha) tidak
    /// mendaftarkan satu pun handler ini (hasil membaca binary 0.11.2). Aplikasi yang punya handler remote command dan
    /// sesi .playback yang aktif ikut dihitung iOS sebagai kandidat "Now Playing", dan itu bisa membuat app Musik
    /// berstatus terputus saat suara petunjuk berbunyi. Tombol dash lewat AVRCP tetap diproses iOS langsung ke app Musik.
    var remoteCommandsEnabled = false

    init() {
        authorized = MPMediaLibrary.authorizationStatus() == .authorized
    }

    private static func stateName(_ s: MPMusicPlaybackState) -> String {
        switch s {
        case .playing: return tr("playing")
        case .paused: return tr("paused")
        case .stopped: return tr("stopped")
        case .interrupted: return tr("interrupted")
        case .seekingForward: return tr("fast forward")
        case .seekingBackward: return tr("rewind")
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
            self?.onLog(tr("Music: state {0}", MusicService.stateName(p.playbackState)))
            self?.resumeIfInterruptedByGuidance()
        }
        nc.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: p, queue: .main) { [weak self] _ in
            self?.onLog(tr("Music: track changed → {0}", p.nowPlayingItem?.title ?? "-"))
        }
        volObs = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            DispatchQueue.main.async { self?.noteSystemVolume(v, source: "KVO") }
        }
        // Notifikasi volume sistem (dikirim iOS tiap volume berubah, termasuk dari tombol fisik HP, selama app hidup).
        // outputVolume/KVO kadang tidak memperbarui nilainya saat app di latar belakang, jadi ini jalur cadangan.
        nc.addObserver(forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
                       object: nil, queue: .main) { [weak self] n in
            guard let v = (n.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? NSNumber)?.floatValue else { return }
            self?.noteSystemVolume(v, source: "notifikasi")
        }
        // sesi audio bisa lepas (telepon, Siri, app lain): aktifkan lagi supaya volume tetap terbaca
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateKeepAlive()
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let t = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            self?.onLog(tr("Audio: interruption {0}", t == .began ? tr("started") : tr("ended")))
            if t == .ended { self?.updateKeepAlive() }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keepAlivePlayer = nil
            self?.updateKeepAlive()
        }
        // catatan di Log untuk menelusuri bila musik berhenti saat suara petunjuk arah berbunyi
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let r = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            self?.onLog(tr("Audio: route changed (reason {0})", r))
        }
        nc.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { [weak self] n in
            let t = (n.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt) ?? 99
            self?.onLog(tr("Audio: another app asked other audio to stay silent (type {0})", t))
        }
        if remoteCommandsEnabled { registerRemoteCommands() }
    }

    /// iOS hanya memperbarui AVAudioSession.outputVolume (dan KVO-nya) bila sesi audio AKTIF, dan sesi ambient
    /// ikut mati saat app pindah ke latar belakang atau layar terkunci. Saat dash tersambung dipakai kategori
    /// playback + mixWithOthers dengan audio senyap (mode latar "audio"), jadi volume dan data HP lain terus berubah.
    /// mixWithOthers: musik yang sedang diputar tidak terganggu.
    func activateAudioSession() {
        if guidanceActive || restartWork != nil { return }          // suara petunjuk arah sedang memegang sesi
        let s = AVAudioSession.sharedInstance()
        do {
            // selalu playback + mixWithOthers (tidak berpindah-pindah kategori, karena perpindahan itu bisa
            // menghentikan pemutar musik); tanpa audio yang diputar, sesi ini tidak mengganggu app lain
            // jangan menyetel ulang kategori bila sudah sama: setCategory berulang (tiap app aktif) bisa memicu
            // perubahan rute audio Bluetooth yang sempat mengganggu sambungan dash
            // PERIKSA PERSIS (kategori + mode + opsi). Sebelumnya hanya `contains(.mixWithOthers)`: opsi suara petunjuk
            // (0x13 = duckOthers + interruptSpoken + mixWithOthers) juga memuat mixWithOthers, jadi sesi dianggap
            // "sudah benar" dan tetap membawa duckOthers + mode voicePrompt. Akibatnya audio senyap berjalan dengan
            // duckOthers aktif terus dan musik tidak pernah kembali ke volume semula.
            if s.category != .playback || s.mode != .default || s.categoryOptions != [.mixWithOthers] {
                try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try s.setActive(true)
        } catch {
            onLog(tr("Audio session failed to activate: {0}", error.localizedDescription))
        }
    }

    /// Nyalakan/matikan audio senyap sesuai pengaturan dan status dash.
    func updateKeepAlive() {
        if guidanceActive || restartWork != nil { return }
        activateAudioSession()
        if keepAliveEnabled && (dashConnected || navActive) {
            if keepAlivePlayer == nil {
                keepAlivePlayer = try? AVAudioPlayer(data: MusicService.silentWAV())
                keepAlivePlayer?.numberOfLoops = -1
                keepAlivePlayer?.volume = 0
                keepAlivePlayer?.prepareToPlay()
            }
            if let p = keepAlivePlayer, !p.isPlaying {
                if !p.play() { onLog(tr("Silent audio failed to play (phone data in the background may stall)")) }
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

    /// Dipanggil sebelum suara petunjuk arah. Musik dikecilkan lewat sesi audio, BUKAN lewat volume ponsel.
    /// Konfigurasi ini disalin persis dari NConnect 0.11.2 (Voice.say, hasil membaca binary):
    /// setCategory(.playback, mode: .voicePrompt, options: 0x13) lalu setActive(true).
    /// 0x13 = `.duckOthers` (0x02) + `.interruptSpokenAudioAndMixWithOthers` (0x11, sudah memuat mixWithOthers).
    /// Versi sebelumnya memakai opsi 3 (mixWithOthers + duckOthers) tanpa flag interruptSpoken; di log app Musik
    /// tetap menjadi "terputus" saat sesi diaktifkan, sedangkan NConnect dengan opsi 0x13 tidak.
    /// Tanpa `duck`, suara hanya dicampur (`.mixWithOthers`) dan musik dibiarkan.
    func beginGuidanceAudio(duck: Bool) {
        let p = MPMusicPlayerController.systemMusicPlayer
        let s = AVAudioSession.sharedInstance()
        if !guidanceActive {
            musicWasPlaying = p.playbackState == .playing
            autoResumeCount = 0
            // keadaan SEBELUM sesi suara diubah, untuk membedakan "terputus oleh sesi suara" dari "sudah terputus sebelumnya"
            onLog(tr("Voice: before session: music={0} otherAudio={1} options={2} mode={3} silent={4}", MusicService.stateName(p.playbackState), s.isOtherAudioPlaying, s.categoryOptions.rawValue, s.mode.rawValue, keepAlivePlayer?.isPlaying == true ? tr("running") : tr("off")))
        }
        autoResumeUntil = .distantFuture
        // ucapan baru datang saat sesi sedang dilepas: batalkan pelepasan itu, sesi dipakai lagi
        releaseWork?.cancel()
        releaseWork = nil
        releasing = false
        // ucapan beruntun: sesi sudah dalam konfigurasi yang sama, jangan diubah lagi
        if guidanceActive, guidanceDuck == duck { return }
        let opts: AVAudioSession.CategoryOptions = duck
            ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers]      // = 0x13, sama dengan NConnect
            : [.mixWithOthers]
        // NConnect (jalur Yamaha) TIDAK punya audio senyap permanen: di antara pemberitahuan sesinya mati, lalu
        // setiap suara mengaktifkan sesi dari nol (voicePrompt + 0x13) dan melepasnya dengan notifyOthersOnDeactivation.
        // Mengubah opsi pada sesi yang sedang aktif dan memutar audio (cara XConnect sebelumnya) membuat Apple Music
        // berhenti dan ducking tidak dilepas bersih. Jadi lepas dulu audio senyap + sesi, baru aktifkan sesi suara.
        restartWork?.cancel()
        restartWork = nil
        if !guidanceActive {
            if let kp = keepAlivePlayer { kp.stop(); keepAlivePlayer = nil }
            do { try s.setActive(false, options: .notifyOthersOnDeactivation) }
            catch { onLog(tr("Voice: old session failed to release: {0}", error.localizedDescription)) }
        }
        guidanceActive = true
        guidanceDuck = duck
        do {
            try s.setCategory(.playback, mode: .voicePrompt, options: opts)
            try s.setActive(true)
            onLog(tr("Voice: session active (duck {0}, system volume {1}%)", duck ? tr("yes") : tr("no"), Int((s.outputVolume * 100).rounded())))
            onLog(tr("Voice: options={0} mode={1} otherAudio={2} silenceOtherAudio={3} music={4}", s.categoryOptions.rawValue, s.mode.rawValue, s.isOtherAudioPlaying, s.secondaryAudioShouldBeSilencedHint, MusicService.stateName(p.playbackState)))
        } catch {
            onLog(tr("Voice: session failed to activate: {0}", error.localizedDescription))
        }
    }

    private var guidanceDuck = false

    // Pengaman (tidak mengganggu selama musik baik-baik saja): iOS sering melaporkan status "terputus" sesaat
    // ketika sesi suara berganti, padahal musik jalan terus (ducking). NConnect tidak pernah memanggil play().
    // Di log terakhir, play() langsung pada setiap status "terputus" justru membuat jeda-putar yang terdengar
    // tersendat dan bisa membuat volume musik tidak kembali. Jadi sekarang: tunggu dulu; hanya bila setelah
    // `resumeDelay` musik MASIH terputus (benar-benar berhenti), kirim satu kali play().
    private var musicWasPlaying = false
    private var autoResumeUntil = Date.distantPast
    private var autoResumeCount = 0
    private var resumeWork: DispatchWorkItem?
    private let resumeDelay: TimeInterval = 1.2

    private func resumeIfInterruptedByGuidance() {
        guard musicWasPlaying, Date() < autoResumeUntil, autoResumeCount < 1 else { return }
        resumeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, self.musicWasPlaying, self.autoResumeCount < 1 else { return }
            let p = MPMusicPlayerController.systemMusicPlayer
            guard p.playbackState == .interrupted || p.playbackState == .paused else { return }   // sudah pulih sendiri
            self.autoResumeCount += 1
            self.onLog(tr("Music: still {0} after {1} s, resumed (1)", MusicService.stateName(p.playbackState), self.resumeDelay))
            p.play()
        }
        resumeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + resumeDelay, execute: w)
    }

    /// true selama sesi suara petunjuk masih dipegang (dipakai pengawas di VoiceGuide)
    var isGuidanceActive: Bool { guidanceActive }

    private var releasing = false
    private var releaseWork: DispatchWorkItem?

    /// Dipanggil setelah suara selesai, sama dengan NConnect (Voice.didFinish, cabang audio senyap mati):
    /// lepas sesi dengan `notifyOthersOnDeactivation` supaya iOS melepas ducking dan musik kembali ke volume semula.
    /// Audio senyap (bila diperlukan) dihidupkan lagi setelah jeda singkat, supaya tidak menimpa proses un-duck.
    ///
    /// Penyebab musik tetap pelan (ducking tidak lepas): `setActive(false)` sering GAGAL tepat setelah suara selesai
    /// ("sesi masih punya I/O yang berjalan"), karena iOS belum selesai menutup keluaran suara. Dulu kegagalan itu hanya
    /// dicatat lalu diabaikan: sesi tetap aktif (lalu audio senyap menyalakannya lagi) sehingga iOS tidak pernah memberi
    /// tahu app musik untuk mengembalikan volume. Sekarang pelepasan DIULANG tiap 0,25 dtk (maks. 12x) sampai berhasil.
    func endGuidanceAudio() {
        guard guidanceActive, !releasing else { return }
        releasing = true
        releaseAttempt(0)
    }

    private func releaseAttempt(_ n: Int) {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setActive(false, options: .notifyOthersOnDeactivation)
            if n > 0 { onLog(tr("Voice: session released on attempt #{0}", n + 1)) }
        } catch {
            if n < 12 {
                if n == 0 { onLog(tr("Voice: session cannot be released yet ({0}), retrying", error.localizedDescription)) }
                let w = DispatchWorkItem { [weak self] in
                    self?.releaseWork = nil
                    self?.releaseAttempt(n + 1)
                }
                releaseWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
                return
            }
            onLog(tr("Voice: session failed to release after {0} attempts: {1}", n + 1, error.localizedDescription))
        }
        finishRelease()
    }

    private func finishRelease() {
        let s = AVAudioSession.sharedInstance()
        // Kembalikan kategori ke konfigurasi dasar (tanpa duckOthers) selagi sesi nonaktif, supaya sesi berikutnya
        // (audio senyap / pemberitahuan berikutnya) tidak mewarisi duckOthers + voicePrompt dari suara sebelumnya.
        do { try s.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
        catch { onLog(tr("Voice: base category failed to restore: {0}", error.localizedDescription)) }
        pauseGuardUntil = Date().addingTimeInterval(2.0)
        autoResumeUntil = Date().addingTimeInterval(4.0)
        autoResumeCount = 0          // jatah baru untuk interupsi yang muncul setelah suara selesai
        guidanceActive = false
        releasing = false
        releaseWork = nil
        restartWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.restartWork = nil
            self?.updateKeepAlive()
        }
        restartWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
        resumeIfInterruptedByGuidance()
        onLog(tr("Voice: done (session released), system volume {0}%", Int((s.outputVolume * 100).rounded())))
    }

    private var restartWork: DispatchWorkItem?

    /// Perintah "jeda" yang datang saat/segera setelah suara petunjuk berbunyi bukan dari pengguna,
    /// melainkan efek samping perubahan sesi audio; jangan diteruskan ke pemutar musik.
    private var pauseGuardUntil = Date.distantPast
    private var shouldIgnorePause: Bool { guidanceActive || Date() < pauseGuardUntil }

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
            self?.onLog(tr("Media command: play"))
            p.play()
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            if self?.shouldIgnorePause == true {
                self?.onLog(tr("Media command: pause IGNORED (during a voice prompt)"))
                return .success
            }
            self?.onLog(tr("Media command: pause"))
            p.pause()
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            if self?.shouldIgnorePause == true {
                self?.onLog(tr("Media command: play/pause IGNORED (during a voice prompt)"))
                return .success
            }
            self?.onLog(tr("Media command: play/pause (OK)"))
            if p.playbackState == .playing { p.pause() } else { p.play() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.onLog(tr("Media command: next track"))
            p.skipToNextItem()
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.onLog(tr("Media command: previous track"))
            p.skipToPreviousItem()
            return .success
        }
        c.seekForwardCommand.addTarget { [weak self] ev in
            let begin = (ev as? MPSeekCommandEvent)?.type == .beginSeeking
            self?.onLog(tr("Media command: hold next ({0})", begin ? tr("started") : tr("ended")))
            if begin { p.beginSeekingForward() } else { p.endSeeking() }
            return .success
        }
        c.seekBackwardCommand.addTarget { [weak self] ev in
            let begin = (ev as? MPSeekCommandEvent)?.type == .beginSeeking
            self?.onLog(tr("Media command: hold previous ({0})", begin ? tr("started") : tr("ended")))
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
    private var lastVolumeTarget: Float = 0
    private var lastVolumeSet = Date.distantPast

    /// Semua sumber perubahan volume sistem lewat sini. Nilai yang sama dengan target yang baru kita setel dari stang
    /// dianggap gema dan tidak mengubah apa pun; nilai lain berarti volume diubah dari luar (tombol HP), jadi target
    /// lama dibuang dan klik stang berikutnya dihitung dari volume yang benar.
    func noteSystemVolume(_ v: Float, source: String) {
        if let k = knownVolume, abs(k - v) < 0.001 { return }
        knownVolume = v
        let echo = abs(v - lastVolumeTarget) < 0.02 && Date().timeIntervalSince(lastVolumeSet) < 1.5
        if !echo {
            lastVolumeSet = .distantPast
            onLog(tr("System volume changed externally → {0}% ({1})", Int((v * 100).rounded()), source))
        }
        onSystemVolume(v)
    }

    /// Cadangan ketiga: nilai slider MPVolumeView mengikuti volume sistem walau outputVolume basi. Dipanggil tiap 1 dtk.
    func pollVolumeView() {
        guard let v = volumeView, v.window != nil,
              let slider = v.subviews.compactMap({ $0 as? UISlider }).first else { return }
        let val = slider.value
        // bacaan pertama hanya dicatat: slider bisa 0 sesaat sebelum sinkron dengan volume sistem
        guard let prev = lastViewVolume else { lastViewVolume = val; return }
        guard abs(prev - val) > 0.001 else { return }
        lastViewVolume = val
        noteSystemVolume(val, source: "slider")
    }

    @discardableResult
    func adjustVolume(up: Bool) -> Float? {
        ensureVolumeView()
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return nil }
        // outputVolume baru ikut berubah beberapa ratus ms setelah slider digeser. Bila klik berikutnya datang cepat
        // (klik 2x di stang membatalkan volume klik pertama), pakai target terakhir sebagai dasar; kalau tidak,
        // pembatalan dihitung dari nilai lama dan volume malah bergeser satu langkah.
        // Dasar: target klik stang sebelumnya bila masih baru (outputVolume belum sempat ikut berubah); selain itu volume
        // terkini dari KVO/notifikasi/slider. outputVolume saja bisa basi setelah volume diubah dari HP, dan itu yang membuat
        // langkah dari stang meleset.
        let fresh = Date().timeIntervalSince(lastVolumeSet) < 1.5
        let sys = AVAudioSession.sharedInstance().outputVolume
        let base = fresh ? lastVolumeTarget : (knownVolume ?? (sys > 0 ? sys : slider.value))
        let target = min(1, max(0, (base * 16).rounded() / 16 + (up ? 0.0625 : -0.0625)))   // iOS: 16 langkah volume
        lastVolumeTarget = target
        lastVolumeSet = Date()
        knownVolume = target
        slider.setValue(target, animated: false)
        slider.sendActions(for: .valueChanged)
        slider.sendActions(for: .touchUpInside)
        return target
    }

    func next() { MPMusicPlayerController.systemMusicPlayer.skipToNextItem() }
    func previous() { MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem() }

    /// Pesan singkat di layar Musik dash (mis. \"Lagu berikutnya\") selama 1,5 dtk.
    private var toastText = ""
    private var toastUntil = Date.distantPast
    var activeToast: String { Date() < toastUntil ? toastText : "" }

    /// Tekan tahan di stang: lagu berikutnya / sebelumnya.
    func skip(next forward: Bool) {
        guard authorized else {
            onLog(tr("Music: Media & Apple Music permission not granted, cannot change track"))
            return
        }
        if forward { next() } else { previous() }
        toastText = forward ? tr("Next track  ▶▶") : tr("◀◀  Previous track")
        toastUntil = Date().addingTimeInterval(1.5)
        onLog(tr("Music: {0} (hold on the handlebar)", forward ? tr("next track") : tr("previous track")))
        // perbarui info lagu secepatnya (judul baru), tidak menunggu timer 1 dtk
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }
    func togglePlay() {
        let p = MPMusicPlayerController.systemMusicPlayer
        if p.playbackState == .playing { p.pause() } else { p.play() }
    }

    /// Putar/jeda dari stang (atas lalu bawah cepat): sama dengan togglePlay, ditambah pesan di dash dan catatan Log.
    func wheelTogglePlay() {
        guard authorized else {
            onLog(tr("Music: Media & Apple Music permission not granted, cannot play/pause"))
            return
        }
        let wasPlaying = MPMusicPlayerController.systemMusicPlayer.playbackState == .playing
        togglePlay()
        toastText = wasPlaying ? tr("Pause  ❚❚") : tr("Play  ▶")
        toastUntil = Date().addingTimeInterval(1.5)
        onLog(tr("Music: {0} (quick up-down on the handlebar)", wasPlaying ? tr("paused") : tr("play")))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }
}

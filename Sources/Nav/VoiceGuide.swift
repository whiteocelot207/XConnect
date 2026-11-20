import Foundation
import AVFoundation
import AudioToolbox

/// Suara petunjuk arah berbahasa Indonesia.
///
/// Musik app lain dikecilkan lewat sesi audio (`.duckOthers`, diatur MusicService.beginGuidanceAudio),
/// bukan lewat volume ponsel, jadi volume master iPhone tidak ikut turun. Pola ini sama dengan NConnect.
///
/// Dua jalur ucapan:
///  - Penguat mati (0 dB): AVSpeechSynthesizer berbicara langsung lewat sesi audio app, volume paling tinggi = volume ponsel.
///  - Penguat menyala: suara diambil sebagai buffer PCM (`synth.write`) lalu diputar lewat AVAudioEngine dengan
///    gain tambahan (hingga +18 dB) dan limiter supaya tidak pecah. Bila pengambilan buffer gagal, otomatis
///    kembali ke jalur langsung.
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let settings: AppSettings
    private weak var music: MusicService?

    /// ucapan yang sedang berjalan; callback delegate dari ucapan lama (yang diganti/dibatalkan) diabaikan
    private var current: AVSpeechUtterance?
    private var currentText = ""
    private var speakStart = Date.distantPast
    private var watchTimer: Timer?

    // Jalur penguat
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let gainEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let limiter: AVAudioUnitEffect
    private var graphBuilt = false
    private var graphFormat: AVAudioFormat?
    private var boostActive = false
    private var boostToken = 0
    private var boostWriteDone = false
    private var boostPending = 0
    private var boostGotBuffer = false

    init(settings: AppSettings, music: MusicService) {
        self.settings = settings
        self.music = music
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        super.init()
        synth.usesApplicationAudioSession = true     // pakai sesi audio app (kategori/opsi dari MusicService)
        synth.delegate = self
        gainEQ.bands[0].bypass = true                // hanya globalGain yang dipakai, tanpa pembentukan nada
    }

    /// Mengucapkan teks bila suara petunjuk arah dinyalakan. Ucapan yang sedang berjalan diganti
    /// (petunjuk terbaru selalu lebih penting daripada yang lama).
    func speak(_ text: String, force: Bool = false) {
        guard force || settings.guideVoice, !text.isEmpty else { return }
        if Thread.isMainThread { speakNow(text) } else { DispatchQueue.main.async { self.speakNow(text) } }
    }

    /// Navigasi mulai/selesai: audio senyap dijaga selama navigasi supaya sesi audio tetap sama saat suara berbunyi.
    func setNavigating(_ on: Bool) {
        let apply = { [weak self] in
            self?.music?.navActive = on
            self?.music?.updateKeepAlive()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    func test() {
        speak("Dalam 100 meter, belok kanan ke Jalan Lingkar Luar Jakarta", force: true)
    }

    /// Hentikan suara sekarang (navigasi dihentikan).
    func cancel() {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.current = nil
            self.stopWatch()
            self.stopBoostPlayback()
            if self.synth.isSpeaking { self.synth.stopSpeaking(at: .immediate) }
            self.music?.endGuidanceAudio()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    // MARK: - Ucapan

    private var guideVolume: Float { Float(min(max(settings.guideVolume, 0.2), 1.0)) }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: VoiceGuide.normalize(text))
        u.voice = AVSpeechSynthesisVoice(language: "id-ID")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        return u
    }

    private func speakNow(_ text: String) {
        stopBoostPlayback()
        current = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        music?.beginGuidanceAudio(duck: settings.guideDuck)
        currentText = text
        speakStart = Date()
        startWatch()
        if settings.guideBoostDb >= 1 {
            speakBoosted(text)
        } else {
            speakPlain(text)
        }
    }

    private func speakPlain(_ text: String) {
        let u = makeUtterance(text)
        u.volume = guideVolume                        // hanya volume suara ini, bukan volume ponsel
        current = u
        synth.speak(u)
    }

    /// Selesai atau dibatalkan (jalur langsung): lepas ducking hanya bila tidak ada ucapan lain yang menyusul.
    private func finishedPlain(_ utterance: AVSpeechUtterance) {
        guard utterance === current, !boostActive else { return }
        // jeda singkat: tepat saat didFinish, iOS kadang belum menutup keluaran suara dan pelepasan sesi ditolak
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, utterance === self.current, !self.synth.isSpeaking else { return }
            self.current = nil
            self.stopWatch()
            self.music?.endGuidanceAudio()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finishedPlain(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finishedPlain(utterance) }

    // MARK: - Pengawas

    /// Pengaman: bila callback selesai tidak pernah datang (ucapan gagal mulai, sesi audio direbut app lain),
    /// ducking tetap harus dilepas. Dicek tiap detik selama sesi suara dipegang.
    private func startWatch() {
        watchTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.watchTick() }
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
    }

    private func stopWatch() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private func watchTick() {
        guard let m = music, m.isGuidanceActive else { stopWatch(); return }
        let age = Date().timeIntervalSince(speakStart)
        if boostActive {
            if age > 30 { finishBoost() }               // ucapan boost tidak mungkin selama ini
            return
        }
        if age > 2.0, !synth.isSpeaking {
            current = nil
            stopWatch()
            m.endGuidanceAudio()
        }
    }

    // MARK: - Jalur penguat

    private func speakBoosted(_ text: String) {
        boostToken += 1
        let token = boostToken
        boostActive = true
        boostWriteDone = false
        boostPending = 0
        boostGotBuffer = false
        // total gain = penguat + (volume suara yang dipilih, sebagai dB negatif)
        let volDb = 20 * log10f(guideVolume)
        gainEQ.globalGain = min(24, max(-24, Float(settings.guideBoostDb) + volDb))
        let u = makeUtterance(text)
        u.volume = 1.0
        current = u
        synth.write(u) { [weak self] buffer in
            DispatchQueue.main.async { self?.boostBuffer(buffer, token: token) }
        }
        // cadangan: tidak ada buffer sama sekali dalam 1,5 dtk -> ucapkan langsung tanpa penguat
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.boostToken == token, self.boostActive, !self.boostGotBuffer else { return }
            self.fallbackToPlain(token: token, reason: "tidak ada buffer suara")
        }
    }

    private func boostBuffer(_ buffer: AVAudioBuffer, token: Int) {
        guard token == boostToken, boostActive, let pcm = buffer as? AVAudioPCMBuffer else { return }
        boostGotBuffer = true
        if pcm.frameLength == 0 {                      // buffer kosong = akhir ucapan
            boostWriteDone = true
            boostCheckDone(token: token)
            return
        }
        guard let fb = floatBuffer(pcm), prepareEngine(fb.format) else {
            fallbackToPlain(token: token, reason: "mesin audio gagal")
            return
        }
        boostPending += 1
        player.scheduleBuffer(fb, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.boostToken == token else { return }
                self.boostPending -= 1
                self.boostCheckDone(token: token)
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func boostCheckDone(token: Int) {
        guard token == boostToken, boostActive, boostWriteDone, boostPending <= 0 else { return }
        finishBoost()
    }

    private func finishBoost() {
        stopBoostPlayback()
        current = nil
        stopWatch()
        // mesin audio sudah berhenti: I/O sesi bebas, pelepasan sesi (dengan pengulangan) bisa berhasil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, !self.boostActive, self.current == nil else { return }
            self.music?.endGuidanceAudio()
        }
    }

    private func fallbackToPlain(token: Int, reason: String) {
        guard token == boostToken, boostActive else { return }
        music?.onLog("Suara: penguat dilewati (\(reason)), diucapkan langsung")
        stopBoostPlayback()                            // menaikkan boostToken: callback boost yang tersisa diabaikan
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speakPlain(currentText)
    }

    /// Hentikan putaran buffer dan mesin audio; callback boost yang masih tertunda tidak berlaku lagi.
    private func stopBoostPlayback() {
        boostToken += 1
        boostActive = false
        boostPending = 0
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
    }

    private func prepareEngine(_ format: AVAudioFormat) -> Bool {
        if !graphBuilt {
            engine.attach(player)
            engine.attach(gainEQ)
            engine.attach(limiter)
            graphBuilt = true
        }
        if graphFormat != format {
            if engine.isRunning { engine.stop() }
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(gainEQ)
            engine.disconnectNodeOutput(limiter)
            engine.connect(player, to: gainEQ, format: format)
            engine.connect(gainEQ, to: limiter, format: format)
            engine.connect(limiter, to: engine.mainMixerNode, format: format)
            graphFormat = format
        }
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                music?.onLog("Suara: mesin audio gagal start: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }

    /// Mesin audio (EQ + limiter) butuh PCM float 32-bit tidak-interleaved; suara sistem kadang Int16.
    private func floatBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if src.format.commonFormat == .pcmFormatFloat32 && !src.format.isInterleaved { return src }
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: src.format.sampleRate,
                                         channels: src.format.channelCount, interleaved: false),
              let conv = AVAudioConverter(from: src.format, to: outFmt),
              let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: src.frameLength) else { return nil }
        var consumed = false
        var err: NSError?
        let status = conv.convert(to: out, error: &err) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return src
        }
        return (status == .error || err != nil) ? nil : out
    }

    // MARK: - Teks untuk diucapkan

    /// Merapikan nama jalan agar dibaca benar oleh suara Indonesia:
    /// angka Romawi menjadi angka ("Maligi I" -> "Maligi 1", dibaca "satu") dan singkatan umum dibuka
    /// ("Jl." -> "Jalan", "Gg." -> "Gang", "Jend." -> "Jenderal").
    static func normalize(_ text: String) -> String {
        var out = text
        // singkatan
        let abbr: [(String, String)] = [
            ("\\b(?:Jl|Jln)\\b\\.?", "Jalan"), ("\\bGg\\b\\.?", "Gang"), ("\\bJend\\b\\.?", "Jenderal"),
            ("\\bProf\\b\\.?", "Profesor"), ("\\bDr\\b\\.?", "Doktor"), ("\\bIr\\b\\.?", "Insinyur"),
            ("\\bKav\\b\\.?", "Kavling"), ("\\bNo\\b\\.?(?=\\s*\\d)", "Nomor")
        ]
        for (pat, rep) in abbr {
            if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: rep)
            }
        }
        // angka Romawi I..XXXIX yang berdiri sendiri sebagai kata
        if let re = try? NSRegularExpression(pattern: "\\b[IVX]+\\b") {
            let ns = out as NSString
            let matches = re.matches(in: out, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let token = ns.substring(with: m.range)
                if let v = romanValue(token) {
                    out = (out as NSString).replacingCharacters(in: m.range, with: String(v))
                }
            }
        }
        return out
    }

    private static func romanValue(_ s: String) -> Int? {
        let vals: [Character: Int] = ["I": 1, "V": 5, "X": 10]
        var total = 0
        var prev = 0
        for ch in s.reversed() {
            guard let v = vals[ch] else { return nil }
            total += v < prev ? -v : v
            prev = max(prev, v)
        }
        guard total > 0, total < 40, roman(total) == s else { return nil }     // hanya angka Romawi yang valid
        return total
    }

    private static func roman(_ n: Int) -> String {
        var n = n
        var r = ""
        for (v, t) in [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
            while n >= v { r += t; n -= v }
        }
        return r
    }
}

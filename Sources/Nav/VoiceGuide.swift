import Foundation
import AVFoundation

/// Suara petunjuk arah berbahasa Indonesia.
///
/// iOS tidak mengizinkan app mengatur volume app musik lain, jadi musik hanya bisa dikecilkan lewat volume
/// ponsel (diatur MusicService). Supaya suara petunjuk tidak ikut pelan, suaranya dibuat sebagai audio
/// terpisah (teks -> buffer lewat AVSpeechSynthesizer.write, diputar lewat AVAudioEngine) lalu diperkeras
/// sebesar kebalikan pengecilan volume, jadi terdengar sekeras volume semula.
final class VoiceGuide: NSObject {
    private let synth = AVSpeechSynthesizer()
    private let settings: AppSettings
    private weak var music: MusicService?
    private var generation = 0
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    init(settings: AppSettings, music: MusicService) {
        self.settings = settings
        self.music = music
        super.init()
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
        speak("Dalam 100 meter, belok kanan ke Jalan Contoh", force: true)
    }

    /// Hentikan suara sekarang (navigasi dihentikan).
    func cancel() {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.generation += 1
            self.stopPlayback()
            self.music?.endGuidanceAudio()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    // MARK: - Ucapan

    private func speakNow(_ text: String) {
        generation += 1
        let gen = generation
        stopPlayback()
        music?.beginGuidanceAudio(duck: settings.guideDuck, level: Float(settings.guideDuckLevel))

        let u = AVSpeechUtterance(string: VoiceGuide.normalize(text))
        u.voice = AVSpeechSynthesisVoice(language: "id-ID")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        var buffers = [AVAudioPCMBuffer]()
        synth.write(u) { [weak self] buf in
            guard let pcm = buf as? AVAudioPCMBuffer else { return }
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                if pcm.frameLength > 0 {
                    buffers.append(pcm)
                } else {
                    // buffer kosong = selesai disintesis; beri waktu volume ponsel turun dulu, lalu putar
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.play(buffers, gen: gen)
                    }
                }
            }
        }
    }

    private func convert(_ b: AVAudioPCMBuffer, to fmt: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let conv = AVAudioConverter(from: b.format, to: fmt),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: b.frameLength) else { return nil }
        var used = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if used { status.pointee = .noDataNow; return nil }
            used = true
            status.pointee = .haveData
            return b
        }
        return err == nil ? out : nil
    }

    private func play(_ bufs: [AVAudioPCMBuffer], gen: Int) {
        guard gen == generation else { return }
        guard let first = bufs.first,
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: first.format.sampleRate,
                                      channels: first.format.channelCount, interleaved: false) else {
            finish(gen)
            return
        }
        var floats = [AVAudioPCMBuffer]()
        for b in bufs {
            if b.format == fmt { floats.append(b) } else if let c = convert(b, to: fmt) { floats.append(c) }
        }
        guard !floats.isEmpty else { finish(gen); return }

        // puncak sinyal, supaya perkerasan tidak membuat suara pecah
        var peak: Float = 0
        for b in floats {
            guard let ch = b.floatChannelData else { continue }
            for c in 0..<Int(fmt.channelCount) {
                for i in 0..<Int(b.frameLength) { peak = max(peak, abs(ch[c][i])) }
            }
        }
        // suara = volume yang diatur / sisa volume ponsel (mis. ponsel diturunkan ke 50% -> suara diperkeras 2x)
        let level = settings.guideDuck ? Float(min(max(settings.guideDuckLevel, 0.1), 1.0)) : 1
        var gain = Float(min(max(settings.guideVolume, 0.2), 1.0)) / level
        if peak > 0 { gain = min(gain, 0.97 / peak) }
        let db = max(-40, min(24, 20 * log10(max(gain, 0.01))))

        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = db
        eng.attach(node)
        eng.attach(eq)
        eng.connect(node, to: eq, format: fmt)
        eng.connect(eq, to: eng.mainMixerNode, format: fmt)
        do {
            try eng.start()
        } catch {
            finish(gen)
            return
        }
        for (i, b) in floats.enumerated() {
            if i == floats.count - 1 {
                node.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async { self?.finish(gen) }
                }
            } else {
                node.scheduleBuffer(b, completionHandler: nil)
            }
        }
        engine = eng
        player = node
        node.play()
    }

    private func stopPlayback() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    /// Suara selesai: bersihkan, lalu kembalikan volume ponsel (kecuali sudah ada ucapan yang lebih baru).
    private func finish(_ gen: Int) {
        guard gen == generation else { return }
        stopPlayback()
        // jeda singkat supaya ekor suara tidak terpotong sebelum volume naik lagi
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, gen == self.generation else { return }
            self.music?.endGuidanceAudio()
        }
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

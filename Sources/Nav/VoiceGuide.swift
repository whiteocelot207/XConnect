import Foundation
import AVFoundation

/// Suara petunjuk arah berbahasa Indonesia.
///
/// Musik app lain dikecilkan lewat sesi audio (`.duckOthers`, diatur MusicService.beginGuidanceAudio),
/// bukan lewat volume ponsel, jadi volume master iPhone tidak ikut turun. Suara petunjuk diucapkan
/// langsung oleh AVSpeechSynthesizer lewat sesi audio app (mode voicePrompt) dan tetap pada volume
/// penuh; tidak ada lagi kompensasi perkerasan. Besar pengecilan musik ditentukan iOS (tidak bisa
/// diatur persen dari app). Pola ini sama dengan NConnect.
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let settings: AppSettings
    private weak var music: MusicService?

    init(settings: AppSettings, music: MusicService) {
        self.settings = settings
        self.music = music
        super.init()
        synth.usesApplicationAudioSession = true     // pakai sesi audio app (kategori/opsi dari MusicService)
        synth.delegate = self
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
            if self.synth.isSpeaking { self.synth.stopSpeaking(at: .immediate) }
            self.music?.endGuidanceAudio()
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    // MARK: - Ucapan

    private func speakNow(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        music?.beginGuidanceAudio(duck: settings.guideDuck)

        let u = AVSpeechUtterance(string: VoiceGuide.normalize(text))
        u.voice = AVSpeechSynthesisVoice(language: "id-ID")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.volume = Float(min(max(settings.guideVolume, 0.2), 1.0))   // hanya volume suara ini, bukan volume ponsel
        synth.speak(u)
    }

    /// Selesai atau dibatalkan: lepas ducking hanya bila tidak ada ucapan lain yang menyusul.
    private func finishedOne() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.synth.isSpeaking else { return }
            self.music?.endGuidanceAudio()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finishedOne() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finishedOne() }

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

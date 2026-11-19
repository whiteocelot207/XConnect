import Foundation
import AVFoundation

/// Suara petunjuk arah berbahasa Indonesia. Saat berbunyi, sesi audio diminta lewat MusicService
/// supaya musik dari app lain dikecilkan (ducking) dan otomatis kembali normal setelah selesai.
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let settings: AppSettings
    private weak var music: MusicService?
    private var pending = 0

    init(settings: AppSettings, music: MusicService) {
        self.settings = settings
        self.music = music
        super.init()
        synth.delegate = self
    }

    /// Mengucapkan teks bila suara petunjuk arah dinyalakan. Ucapan yang sedang berjalan diganti
    /// (petunjuk terbaru selalu lebih penting daripada yang lama).
    func speak(_ text: String, force: Bool = false) {
        guard force || settings.guideVoice, !text.isEmpty else { return }
        if Thread.isMainThread { speakNow(text) } else { DispatchQueue.main.async { self.speakNow(text) } }
    }

    func test() {
        speak("Dalam 100 meter, belok kanan ke Jalan Contoh", force: true)
    }

    /// Hentikan suara sekarang (navigasi dihentikan).
    func cancel() {
        if Thread.isMainThread { synth.stopSpeaking(at: .immediate) }
        else { DispatchQueue.main.async { self.synth.stopSpeaking(at: .immediate) } }
    }

    private func speakNow(_ text: String) {
        pending += 1
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        music?.beginGuidanceAudio(duck: settings.guideDuck)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "id-ID")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.volume = Float(min(max(0.2, settings.guideVolume), 1.0))
        u.preUtteranceDelay = 0.15           // beri waktu musik mengecil sebelum suara mulai
        u.postUtteranceDelay = 0.1
        synth.speak(u)
    }

    private func utteranceEnded() {
        DispatchQueue.main.async {
            self.pending = max(0, self.pending - 1)
            guard self.pending == 0 else { return }
            // jeda singkat supaya I/O suara benar-benar berhenti sebelum sesi dilepas
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.pending == 0 else { return }
                self.music?.endGuidanceAudio()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        utteranceEnded()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        utteranceEnded()
    }
}

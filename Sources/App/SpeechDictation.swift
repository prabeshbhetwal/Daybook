import Foundation
import AVFoundation
import Speech

/// Speech to text inside the app, the way a chat app's microphone works:
/// press to listen, words appear as they are recognised, press to stop. The
/// system's own Dictation setting is not involved; this asks for the
/// microphone and speech recognition directly and prefers on-device
/// recognition when the language has it.
@MainActor final class SpeechDictation: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case requesting
        case listening
        case failed(String)

        var message: String? {
            if case .failed(let text) = self { return text }
            return nil
        }
    }

    @Published private(set) var status: Status = .idle
    /// The words recognised so far in this listening spell.
    @Published private(set) var transcript = ""

    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    override init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        super.init()
    }

    var isListening: Bool { status == .listening }
    var isBusy: Bool { status == .listening || status == .requesting }

    /// Whether this Mac can recognise speech in the user's language at all.
    var isSupported: Bool { recognizer != nil }

    func toggle() {
        if isBusy { stop() } else { start() }
    }

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            status = .failed("Speech recognition is not available for your language on this Mac.")
            return
        }
        status = .requesting
        SFSpeechRecognizer.requestAuthorization { [weak self] authorisation in
            DispatchQueue.main.async {
                guard let self, self.status == .requesting else { return }
                switch authorisation {
                case .authorized: self.requestMicrophone()
                case .denied:
                    self.status = .failed("Speech recognition was refused. Allow it in System Settings › "
                                          + "Privacy & Security › Speech Recognition.")
                case .restricted, .notDetermined:
                    self.status = .failed("Speech recognition is not allowed on this Mac.")
                @unknown default:
                    self.status = .failed("Speech recognition is not allowed on this Mac.")
                }
            }
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.status == .requesting else { return }
                if granted {
                    self.beginListening()
                } else {
                    self.status = .failed("Microphone access was refused. Allow it in System Settings › "
                                          + "Privacy & Security › Microphone.")
                }
            }
        }
    }

    private func beginListening() {
        guard let recognizer else { return }
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .failed("No microphone was found.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            status = .failed("The microphone could not be started.")
            return
        }
        audioEngine = engine
        self.request = request
        transcript = ""
        status = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.status == .listening else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if let error {
                    // Silence long enough for the recogniser to give up is not
                    // a failure worth a message; anything else is.
                    let code = (error as NSError).code
                    self.tearDown()
                    self.status = code == 1_110 || code == 216 ? .idle
                        : .failed("Dictation stopped: \(error.localizedDescription)")
                } else if result?.isFinal == true {
                    self.tearDown()
                    self.status = .idle
                }
            }
        }
    }

    /// Stops listening and keeps whatever was recognised.
    func stop() {
        tearDown()
        status = .idle
    }

    func clearError() {
        if case .failed = status { status = .idle }
    }

    private func tearDown() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
    }

    /// The note as it should read while words arrive: what was already
    /// written, a space, then the transcript so far.
    nonisolated static func merge(base: String, transcript: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty { return spoken }
        if spoken.isEmpty { return trimmedBase }
        return trimmedBase + " " + spoken
    }
}

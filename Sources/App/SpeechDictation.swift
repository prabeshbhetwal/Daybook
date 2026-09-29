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
        /// `settings` is the Privacy & Security pane that can undo a refusal.
        case failed(String, settings: URL? = nil)

        var message: String? {
            if case .failed(let text, _) = self { return text }
            return nil
        }

        var privacySettings: URL? {
            if case .failed(_, let url) = self { return url }
            return nil
        }
    }

    private static func privacyPane(_ anchor: String) -> URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)
    }

    @Published private(set) var status: Status = .idle
    /// The words recognised so far in this listening spell.
    @Published private(set) var transcript = ""

    private let recognizer: SFSpeechRecognizer?
    private var spoken = DictationTranscript()
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
                                          + "Privacy & Security › Speech Recognition.",
                                          settings: Self.privacyPane("Privacy_SpeechRecognition"))
                case .restricted:
                    self.status = .failed("Dictation is restricted on this Mac, for example by Screen Time "
                                          + "or a device profile.")
                case .notDetermined:
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
                                          + "Privacy & Security › Microphone.",
                                          settings: Self.privacyPane("Privacy_Microphone"))
                }
            }
        }
    }

    private func beginListening() {
        guard let recognizer else { return }
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Sentences end in full stops and questions in question marks, as they
        // do in a chat app's dictation, rather than one unbroken run of words.
        request.addsPunctuation = true
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
        spoken = DictationTranscript()
        transcript = ""
        status = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.status == .listening else { return }
                if let result {
                    self.transcript = self.spoken.receive(
                        result.bestTranscription.formattedString,
                        endsUtterance: result.speechRecognitionMetadata != nil || result.isFinal)
                }
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

/// Everything said in one listening spell, across pauses.
///
/// The recogniser reports the current utterance, not the whole spell: after a
/// pause it starts afresh, and a note that showed only its latest result lost
/// every word spoken before the pause. Finished utterances are kept here and
/// the one in progress is added after them. An utterance counts as finished
/// when the recogniser says so, or when its next result is plainly a new
/// start: shorter, and beginning with a different word.
struct DictationTranscript: Equatable {
    private var finished: [String] = []
    private var current = ""

    var text: String { (finished + [current]).filter { !$0.isEmpty }.joined(separator: " ") }

    mutating func receive(_ result: String, endsUtterance: Bool) -> String {
        let words = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty, let last = finished.last,
           Self.plain(words).hasPrefix(Self.plain(last)) {
            // Not a new utterance after all: the recogniser went on with the
            // one it had just finished, or sent it again. Kept once.
            finished.removeLast()
        }
        if Self.startsAfresh(words, after: current) {
            finished.append(current)
        }
        current = words
        if endsUtterance && !current.isEmpty {
            finished.append(current)
            current = ""
        }
        return text
    }

    /// A revision of the utterance in progress keeps its first word and
    /// rarely shrinks; a new utterance does neither.
    private static func startsAfresh(_ next: String, after current: String) -> Bool {
        guard !current.isEmpty, !next.isEmpty, next.count < current.count else { return false }
        return firstWord(next) != firstWord(current)
    }

    /// Words only, for comparing results that differ in case or punctuation.
    private static func plain(_ text: String) -> String {
        text.lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }

    private static func firstWord(_ text: String) -> String {
        String(text.split(separator: " ").first ?? "")
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
    }
}

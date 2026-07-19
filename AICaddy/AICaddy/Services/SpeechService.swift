import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechService {
    var isListening = false
    var transcript = ""
    var error: String?
    var isAuthorized = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var pendingResult: ((String) -> Void)?
    private var hasDelivered = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = status == .authorized
                if status != .authorized {
                    self?.error = "Speech recognition not authorized"
                }
            }
        }
    }

    func startListening(onResult: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition unavailable"
            return
        }

        // Stop any existing session
        stopListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false  // use server for accuracy, falls back to on-device

        recognitionRequest = request
        transcript = ""
        error = nil
        pendingResult = onResult
        hasDelivered = false

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch let audioError {
            self.error = "Audio session error: \(audioError.localizedDescription)"
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch let engineError {
            self.error = "Could not start audio engine: \(engineError.localizedDescription)"
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] taskResult, taskError in
            guard let self else { return }

            if let taskResult {
                let text = taskResult.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcript = text
                }

                if taskResult.isFinal {
                    DispatchQueue.main.async {
                        self.stopListening()
                        self.deliver(text)
                    }
                }
            }

            if let taskError {
                DispatchQueue.main.async {
                    // Don't report cancellation errors
                    if (taskError as NSError).code != 216 {
                        self.error = taskError.localizedDescription
                    }
                    self.stopListening()
                }
            }
        }
    }

    /// User-initiated "I'm done talking" — stops the session and submits whatever
    /// was transcribed so far. Without this, tapping stop cancels the recognition
    /// task and the final-result callback (and the user's input) is silently lost.
    func finishListening() {
        let text = transcript
        stopListening()
        deliver(text)
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    /// Deliver the result exactly once per listening session.
    private func deliver(_ text: String) {
        guard !hasDelivered else { return }
        hasDelivered = true
        let callback = pendingResult
        pendingResult = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        callback?(trimmed)
    }
}

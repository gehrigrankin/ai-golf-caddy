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
    private var onResult: ((String) -> Void)?
    private var resultDelivered = false

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
        cancelListening()

        self.onResult = onResult
        resultDelivered = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Golf courses have spotty cell coverage — stay on-device whenever the
        // hardware supports it so voice input works with zero signal.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation

        recognitionRequest = request
        transcript = ""
        error = nil

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
            deactivateAudioSession()
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
                        self.finishListening(deliver: true)
                    }
                }
            }

            if let taskError {
                DispatchQueue.main.async {
                    let code = (taskError as NSError).code
                    // 216/301 = cancellation — not a real error. If we have a
                    // transcript, deliver it rather than dropping the input.
                    if code != 216 && code != 301 && self.transcript.isEmpty {
                        self.error = taskError.localizedDescription
                    }
                    self.finishListening(deliver: true)
                }
            }
        }
    }

    /// User tapped stop: hand the words we heard to the app. Cancelling the task
    /// here without delivering would silently drop the input (the old bug that
    /// made voice entry feel broken on the course).
    func stopListening() {
        finishListening(deliver: true)
    }

    /// Tear down without delivering a result (e.g. leaving the screen).
    func cancelListening() {
        finishListening(deliver: false)
    }

    private func finishListening(deliver: Bool) {
        let text = transcript

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        deactivateAudioSession()

        if deliver, !resultDelivered, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            resultDelivered = true
            let callback = onResult
            onResult = nil
            callback?(text)
        } else if !deliver {
            onResult = nil
        }
    }

    /// Give the audio session back so the user's music resumes after dictation.
    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

import Foundation
import WatchConnectivity

/// iPhone-side counterpart to the watch app's WatchConnectivityManager.
/// Without this the watch sends scores into the void and its sync requests
/// never get a reply.
@Observable
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    /// Called on the main thread when the watch submits a score phrase
    /// like "par" or "2 putts" for a hole.
    var onScoreInput: ((_ input: String, _ hole: Int) -> Void)?

    private var lastState: [String: Any] = ["isRoundActive": false]

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Push current round state to the watch.
    func updateState(
        currentHole: Int,
        currentPar: Int,
        totalScore: Int,
        scoreToPar: Int,
        distToGreen: Int?,
        courseName: String,
        isRoundActive: Bool
    ) {
        var state: [String: Any] = [
            "currentHole": currentHole,
            "currentPar": currentPar,
            "totalScore": totalScore,
            "scoreToPar": scoreToPar,
            "courseName": courseName,
            "isRoundActive": isRoundActive,
        ]
        if let distToGreen { state["distToGreen"] = distToGreen }
        lastState = state

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(state, replyHandler: nil, errorHandler: nil)
        } else {
            // Delivered when the watch app next wakes
            try? session.updateApplicationContext(state)
        }
    }

    func roundEnded() {
        updateState(currentHole: 1, currentPar: 4, totalScore: 0, scoreToPar: 0,
                    distToGreen: nil, courseName: "", isRoundActive: false)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message: message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message: message, replyHandler: replyHandler)
    }

    private func handle(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        let type = message["type"] as? String
        switch type {
        case "scoreInput":
            if let input = message["input"] as? String {
                let hole = message["hole"] as? Int ?? 0
                DispatchQueue.main.async { [weak self] in
                    self?.onScoreInput?(input, hole)
                }
            }
            replyHandler?(lastState)
        case "syncRequest":
            replyHandler?(lastState)
        default:
            replyHandler?([:])
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

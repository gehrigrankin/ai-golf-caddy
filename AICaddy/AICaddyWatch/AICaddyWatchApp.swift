import SwiftUI
import WatchConnectivity

@main
struct AICaddyWatchApp: App {
    @State private var connectivity = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            WatchRoundView(connectivity: connectivity)
        }
    }
}

/// Manages communication between Apple Watch and iPhone
@Observable
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    var isReachable = false
    var currentHole: Int = 1
    var currentPar: Int = 4
    var totalScore: Int = 0
    var scoreToPar: Int = 0
    var distToGreen: Int?
    var courseName: String = ""
    var isRoundActive = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // Send score input to iPhone
    func sendScore(_ input: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "scoreInput", "input": input, "hole": currentHole],
            replyHandler: nil
        )
    }

    // Request current round state from iPhone
    func requestSync() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["type": "syncRequest"], replyHandler: { reply in
            DispatchQueue.main.async {
                self.updateFromMessage(reply)
            }
        })
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.updateFromMessage(message)
        }
    }

    // State pushed while the watch app was asleep arrives here
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.updateFromMessage(applicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    private func updateFromMessage(_ message: [String: Any]) {
        if let hole = message["currentHole"] as? Int { currentHole = hole }
        if let par = message["currentPar"] as? Int { currentPar = par }
        if let score = message["totalScore"] as? Int { totalScore = score }
        if let stp = message["scoreToPar"] as? Int { scoreToPar = stp }
        if let dist = message["distToGreen"] as? Int { distToGreen = dist }
        if let name = message["courseName"] as? String { courseName = name }
        if let active = message["isRoundActive"] as? Bool { isRoundActive = active }
    }
}

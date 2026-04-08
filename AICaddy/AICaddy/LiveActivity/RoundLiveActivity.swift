import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity attributes for showing round progress on lock screen
struct RoundActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentHole: Int
        var currentPar: Int
        var totalScore: Int
        var scoreToPar: Int
        var distToGreen: Int?
        var lastHoleScore: Int?
        var lastHolePar: Int?
    }

    // Fixed attributes (don't change during the activity)
    let courseName: String
    let teeName: String
    let startTime: Date
}

/// Manages starting/stopping/updating the Live Activity
@Observable
final class LiveActivityManager {
    private var activity: Activity<RoundActivityAttributes>?

    var isActive: Bool { activity != nil }

    func startActivity(courseName: String, teeName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = RoundActivityAttributes(
            courseName: courseName,
            teeName: teeName,
            startTime: Date()
        )

        let initialState = RoundActivityAttributes.ContentState(
            currentHole: 1,
            currentPar: 4,
            totalScore: 0,
            scoreToPar: 0
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(
        currentHole: Int,
        currentPar: Int,
        totalScore: Int,
        scoreToPar: Int,
        distToGreen: Int?,
        lastHoleScore: Int?,
        lastHolePar: Int?
    ) {
        let state = RoundActivityAttributes.ContentState(
            currentHole: currentHole,
            currentPar: currentPar,
            totalScore: totalScore,
            scoreToPar: scoreToPar,
            distToGreen: distToGreen,
            lastHoleScore: lastHoleScore,
            lastHolePar: lastHolePar
        )

        Task {
            await activity?.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func endActivity(finalScore: Int, scoreToPar: Int) {
        let finalState = RoundActivityAttributes.ContentState(
            currentHole: 18,
            currentPar: 0,
            totalScore: finalScore,
            scoreToPar: scoreToPar
        )

        Task {
            await activity?.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 3600)  // dismiss after 1 hour
            )
            await MainActor.run { activity = nil }
        }
    }
}

// MARK: - Live Activity UI (for Widget Extension)

/// Lock screen compact view
struct RoundLiveActivityView: View {
    let context: ActivityViewContext<RoundActivityAttributes>

    var body: some View {
        HStack {
            // Left: course and hole
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.courseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Hole \(context.state.currentHole)")
                    .font(.headline.bold())
                Text("Par \(context.state.currentPar)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Center: distance
            if let dist = context.state.distToGreen {
                VStack(spacing: 0) {
                    Text("\(dist)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                    Text("yds")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right: score
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(context.state.totalScore)")
                    .font(.title2.bold())
                let stp = context.state.scoreToPar
                Text(stp == 0 ? "E" : (stp > 0 ? "+\(stp)" : "\(stp)"))
                    .font(.caption.bold())
                    .foregroundStyle(stp < 0 ? .red : stp > 0 ? .cyan : .green)

                // Last hole score
                if let lastScore = context.state.lastHoleScore,
                   let lastPar = context.state.lastHolePar {
                    let diff = lastScore - lastPar
                    Text("Last: \(lastScore)")
                        .font(.system(size: 9))
                        .foregroundStyle(diff < 0 ? .red : diff > 0 ? .cyan : .green)
                }
            }
        }
        .padding()
    }
}

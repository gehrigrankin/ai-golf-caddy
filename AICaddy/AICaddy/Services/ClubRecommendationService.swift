import Foundation
import SwiftData
import CoreLocation

/// The actual "AI Caddy" — recommends clubs based on your history and current distance.
@Observable
final class ClubRecommendationService {
    private var clubHistory: [Club: [Int]] = [:]  // club -> distances hit

    /// Load historical club distances from completed rounds
    func loadHistory(rounds: [Round]) {
        clubHistory = [:]
        for round in rounds where round.isComplete {
            for hole in round.holes {
                for shot in hole.shots where !shot.isPutt && !shot.isPenalty {
                    if let club = shot.club, let dist = shot.distanceYards, dist > 0 {
                        clubHistory[club, default: []].append(dist)
                    }
                }
            }
        }
    }

    /// Get club recommendation for a given distance
    func recommend(distanceYards: Int) -> ClubRecommendation? {
        guard !clubHistory.isEmpty else { return nil }

        // Find clubs where the average distance is close to what we need
        var candidates: [(club: Club, avg: Int, count: Int, diff: Int)] = []

        for (club, distances) in clubHistory {
            guard distances.count >= 2 else { continue }  // need at least 2 data points
            let avg = distances.reduce(0, +) / distances.count
            let diff = abs(avg - distanceYards)
            candidates.append((club, avg, distances.count, diff))
        }

        guard !candidates.isEmpty else { return nil }

        // Sort by closest to target distance
        candidates.sort { $0.diff < $1.diff }

        let best = candidates[0]
        let alternate = candidates.count > 1 ? candidates[1] : nil

        // Determine recommendation reasoning
        let reasoning: String
        let diffFromTarget = best.avg - distanceYards

        if abs(diffFromTarget) <= 5 {
            reasoning = "Your \(best.club.displayName) averages \(best.avg)y — right on the number."
        } else if diffFromTarget > 0 {
            reasoning = "Your \(best.club.displayName) averages \(best.avg)y. A smooth swing should be perfect for \(distanceYards)y."
        } else {
            reasoning = "Your \(best.club.displayName) averages \(best.avg)y. Give it a little extra for \(distanceYards)y."
        }

        return ClubRecommendation(
            primaryClub: best.club,
            primaryAvg: best.avg,
            primaryCount: best.count,
            alternateClub: alternate?.club,
            alternateAvg: alternate?.avg,
            alternateCount: alternate?.count,
            targetDistance: distanceYards,
            reasoning: reasoning
        )
    }

    /// Get your average distances for all clubs (for the bag/stats screen)
    var clubAverages: [(club: Club, avg: Int, count: Int)] {
        clubHistory
            .filter { $0.value.count >= 1 }
            .map { (club: $0.key, avg: $0.value.reduce(0, +) / $0.value.count, count: $0.value.count) }
            .sorted { $0.avg > $1.avg }
    }

    /// Check if we have enough data to make recommendations
    var hasData: Bool { !clubHistory.isEmpty }
}

struct ClubRecommendation {
    let primaryClub: Club
    let primaryAvg: Int
    let primaryCount: Int
    let alternateClub: Club?
    let alternateAvg: Int?
    let alternateCount: Int?
    let targetDistance: Int
    let reasoning: String
}

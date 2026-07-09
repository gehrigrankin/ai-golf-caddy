import Foundation
import SwiftData
import CoreLocation

/// The actual "AI Caddy" — recommends clubs based on your history and current distance.
/// Falls back to typical amateur distances until it has learned yours, so the very
/// first round still gets advice.
@Observable
final class ClubRecommendationService {
    private var clubHistory: [Club: [Int]] = [:]  // club -> distances hit
    private var bagClubs: [BagClub] = []

    /// Typical carry distances (average amateur) used until we've learned yours.
    static let standardDistances: [Club: Int] = [
        .driver: 230, .wood3: 215, .wood5: 205, .wood7: 195,
        .hybrid2: 210, .hybrid3: 200, .hybrid4: 190, .hybrid5: 180,
        .iron2: 200, .iron3: 190, .iron4: 180, .iron5: 170, .iron6: 160,
        .iron7: 150, .iron8: 140, .iron9: 130,
        .pw: 115, .gw: 100, .sw: 85, .lw: 70,
    ]

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

    /// Tell the caddy what's in the bag (limits recommendations to clubs you carry
    /// and lets it surface your swing thought for the chosen club).
    func loadBag(_ bag: GolfBag?) {
        bagClubs = bag?.clubs ?? []
    }

    /// Get club recommendation for a distance.
    /// - Parameters:
    ///   - distanceYards: actual GPS distance to the target
    ///   - playsLikeYards: wind/temp/elevation-adjusted distance (if known); the club
    ///     is chosen for THIS number
    ///   - conditionsNote: short human note like "+8y wind" shown in the reasoning
    func recommend(
        distanceYards: Int,
        playsLikeYards: Int? = nil,
        conditionsNote: String? = nil
    ) -> ClubRecommendation? {
        let target = playsLikeYards ?? distanceYards

        // Candidate set: every club we have history for, plus every club in the bag
        // (or the whole standard set when there's no bag configured yet).
        var clubs = Set(clubHistory.keys)
        if bagClubs.isEmpty {
            clubs.formUnion(Self.standardDistances.keys)
        } else {
            clubs.formUnion(bagClubs.map(\.club))
        }
        clubs.remove(.putter)

        var candidates: [(club: Club, avg: Int, count: Int, diff: Int, fromHistory: Bool)] = []
        for club in clubs {
            let distances = clubHistory[club] ?? []
            if distances.count >= 2 {
                let avg = distances.reduce(0, +) / distances.count
                candidates.append((club, avg, distances.count, abs(avg - target), true))
            } else if let standard = Self.standardDistances[club] {
                candidates.append((club, standard, 0, abs(standard - target), false))
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Closest to target wins; prefer learned data on ties.
        candidates.sort {
            if $0.diff != $1.diff { return $0.diff < $1.diff }
            return $0.fromHistory && !$1.fromHistory
        }

        let best = candidates[0]
        let alternate = candidates.count > 1 ? candidates[1] : nil

        var reasoning: String
        let source = best.fromHistory
            ? "Your \(best.club.displayName) averages \(best.avg)y"
            : "A typical \(best.club.displayName) carries about \(best.avg)y"
        let diffFromTarget = best.avg - target

        if abs(diffFromTarget) <= 5 {
            reasoning = "\(source) — right on the number."
        } else if diffFromTarget > 0 {
            reasoning = "\(source). A smooth swing covers \(target)y."
        } else {
            reasoning = "\(source). Give it a little extra for \(target)y."
        }
        if let playsLike = playsLikeYards, playsLike != distanceYards {
            let note = conditionsNote.map { " (\($0))" } ?? ""
            reasoning = "Plays like \(playsLike)y\(note). " + reasoning
        }
        if !best.fromHistory {
            reasoning += " Log shots with clubs and I'll learn your real distances."
        }

        let thought = bagClubs.first(where: { $0.club == best.club })?.swingThought

        return ClubRecommendation(
            primaryClub: best.club,
            primaryAvg: best.avg,
            primaryCount: best.count,
            primaryIsFromHistory: best.fromHistory,
            alternateClub: alternate?.club,
            alternateAvg: alternate?.avg,
            alternateCount: alternate?.count,
            targetDistance: distanceYards,
            playsLikeDistance: playsLikeYards,
            reasoning: reasoning,
            swingThought: thought
        )
    }

    /// Get your average distances for all clubs (for the bag/stats screen)
    var clubAverages: [(club: Club, avg: Int, count: Int)] {
        clubHistory
            .filter { $0.value.count >= 1 }
            .map { (club: $0.key, avg: $0.value.reduce(0, +) / $0.value.count, count: $0.value.count) }
            .sorted { $0.avg > $1.avg }
    }

    /// Check if we have learned data (recommendations work either way)
    var hasData: Bool { !clubHistory.isEmpty }
}

struct ClubRecommendation {
    let primaryClub: Club
    let primaryAvg: Int
    let primaryCount: Int
    let primaryIsFromHistory: Bool
    let alternateClub: Club?
    let alternateAvg: Int?
    let alternateCount: Int?
    let targetDistance: Int
    let playsLikeDistance: Int?
    let reasoning: String
    let swingThought: String?
}

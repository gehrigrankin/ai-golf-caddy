import SwiftUI

struct RoundSummaryView: View {
    let round: Round
    let onDone: () -> Void
    var onHoleTap: ((Int) -> Void)?

    private var stats: RoundStats {
        StatsCalculator.calculate(holes: round.holes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 4) {
                    Text("Round Summary")
                        .font(.title2.bold())
                    Text("\(round.courseName) · \(round.teeName)")
                        .foregroundStyle(.secondary)
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Big score
                VStack(spacing: 4) {
                    Text("\(stats.totalStrokes)")
                        .font(.system(size: 64, weight: .bold))
                    ScoreText(scoreToPar: stats.scoreToPar)
                        .font(.title.bold())
                    Text("Front \(stats.frontNine) · Back \(stats.backNine)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Key stats
                LazyVGrid(columns: [.init(), .init(), .init()], spacing: 8) {
                    StatCard(label: "Putts", value: "\(stats.totalPutts)", sub: String(format: "%.1f/hole", stats.puttsPerHole))
                    StatCard(label: "GIR", value: "\(stats.greensInRegulation)/\(stats.girHoles)",
                             sub: String(format: "%.0f%%", stats.greensInRegulationPct))
                    StatCard(label: "Fairways", value: "\(stats.fairwaysHit)/\(stats.fairwayHoles)",
                             sub: String(format: "%.0f%%", stats.fairwaysPct))
                }

                // Scoring distribution
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scoring").font(.subheadline.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ScoringPill(label: "Eagles", count: stats.eagles, color: .yellow)
                        ScoringPill(label: "Birdies", count: stats.birdies, color: .red)
                        ScoringPill(label: "Pars", count: stats.pars, color: .green)
                        ScoringPill(label: "Bogeys", count: stats.bogeys, color: .cyan)
                        ScoringPill(label: "Dbl", count: stats.doubleBogeys, color: .blue)
                        ScoringPill(label: "3+", count: stats.triplePlus, color: .gray)
                    }
                }

                // Detailed stats
                LazyVGrid(columns: [.init(), .init()], spacing: 8) {
                    StatCard(label: "1-Putts", value: "\(stats.oneputts)")
                    StatCard(label: "3-Putts", value: "\(stats.threeputts)")
                    if stats.upAndDownAttempts > 0 {
                        StatCard(label: "Up & Down", value: String(format: "%.0f%%", stats.upAndDownPct),
                                 sub: "\(stats.upAndDowns)/\(stats.upAndDownAttempts)")
                    }
                    if stats.sandSaveAttempts > 0 {
                        StatCard(label: "Sand Saves", value: String(format: "%.0f%%", stats.sandSavePct),
                                 sub: "\(stats.sandSaves)/\(stats.sandSaveAttempts)")
                    }
                    if stats.scramblingPct > 0 {
                        StatCard(label: "Scrambling", value: String(format: "%.0f%%", stats.scramblingPct))
                    }
                    if stats.avgDrivingDistance > 0 {
                        StatCard(label: "Avg Drive", value: "\(stats.avgDrivingDistance)y",
                                 sub: "\(stats.driveCount) drives")
                    }
                }

                // Par performance
                if stats.par3Avg > 0 || stats.par4Avg > 0 || stats.par5Avg > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Avg by Par").font(.subheadline.bold()).foregroundStyle(.secondary)
                        LazyVGrid(columns: [.init(), .init(), .init()], spacing: 8) {
                            if stats.par3Avg > 0 { StatCard(label: "Par 3", value: String(format: "%.1f", stats.par3Avg)) }
                            if stats.par4Avg > 0 { StatCard(label: "Par 4", value: String(format: "%.1f", stats.par4Avg)) }
                            if stats.par5Avg > 0 { StatCard(label: "Par 5", value: String(format: "%.1f", stats.par5Avg)) }
                        }
                    }
                }

                // Club distances
                if !stats.clubDistances.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Club Distances").font(.subheadline.bold()).foregroundStyle(.secondary)
                        LazyVGrid(columns: [.init(), .init()], spacing: 8) {
                            ForEach(
                                stats.clubDistances.sorted { $0.value.avg > $1.value.avg },
                                id: \.key
                            ) { club, data in
                                StatCard(label: club.displayName, value: "\(data.avg)y", sub: "\(data.count) shots")
                            }
                        }
                    }
                }

                // Scorecard
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scorecard").font(.subheadline.bold()).foregroundStyle(.secondary)
                    ScorecardView(
                        holes: round.holes,
                        courseName: round.courseName,
                        teeName: round.teeName,
                        onHoleTap: onHoleTap
                    )
                }

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var sub: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            if let sub {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ScoringPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

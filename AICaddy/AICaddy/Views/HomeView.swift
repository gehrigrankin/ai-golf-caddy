import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Round.date, order: .reverse) private var allRounds: [Round]
    @State private var showNewRound = false
    /// When set, the round sheet resumes this round instead of starting fresh.
    @State private var roundToResume: Round?

    let locationService: LocationService
    let speechService: SpeechService
    let shotParser: ShotParserService
    let courseSearch: CourseSearchService
    let clubRecommender: ClubRecommendationService

    private var inProgressRound: Round? {
        allRounds.first { !$0.isComplete }
    }

    private var recentCompleted: [Round] {
        Array(allRounds.filter(\.isComplete).prefix(5))
    }

    private var handicapRounds: [HandicapRound] {
        allRounds.filter(\.isComplete)
            .sorted { $0.date > $1.date }
            .prefix(20)
            .compactMap { HandicapRound.fromRound($0) }
    }

    private var calculatedHandicap: Double? {
        HandicapCalculator.calculateIndex(rounds: handicapRounds)
    }

    private var totalRoundsPlayed: Int {
        allRounds.filter(\.isComplete).count
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Header ──
                    headerSection
                        .padding(.bottom, 28)

                    // ── Primary Action ──
                    primaryActionSection
                        .padding(.bottom, 24)

                    // ── Stats Strip ──
                    if totalRoundsPlayed > 0 {
                        statsStripSection
                            .padding(.bottom, 24)
                    }

                    // ── Recent Rounds ──
                    if !recentCompleted.isEmpty {
                        recentRoundsSection
                            .padding(.bottom, 24)
                    }

                    // ── Navigation ──
                    navigationSection
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.black)
            .fullScreenCover(isPresented: $showNewRound) {
                RoundView(
                    locationService: locationService,
                    speechService: speechService,
                    shotParser: shotParser,
                    courseSearch: courseSearch,
                    clubRecommender: clubRecommender,
                    existingRound: roundToResume
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Caddy")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Handicap badge
                if let handicap = calculatedHandicap {
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f", handicap))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("HCP")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.12))
                            .overlay(Circle().stroke(Color.green.opacity(0.25), lineWidth: 1))
                    )
                }
            }
            .padding(.top, 16)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Primary Action

    private var primaryActionSection: some View {
        VStack(spacing: 12) {
            // Resume in-progress round
            if let inProgress = inProgressRound {
                Button {
                    // Actually resume this round — without setting roundToResume
                    // the sheet starts a brand-new round and the old one is lost.
                    roundToResume = inProgress
                    showNewRound = true
                } label: {
                    HStack(spacing: 14) {
                        // Hole progress ring (don't assume 18 holes)
                        let holeCount = max(1, inProgress.holes.count)
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: Double(inProgress.currentHole) / Double(holeCount))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(inProgress.currentHole)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(inProgress.courseName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Hole \(inProgress.currentHole) of \(holeCount) · \(inProgress.teeName)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            let score = inProgress.holes.reduce(0) { $0 + $1.strokes }
                            Text("\(score)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }

            // Start new round button
            Button {
                roundToResume = nil
                showNewRound = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                    Text("Start Round")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.green)
                )
            }
        }
    }

    // MARK: - Stats Strip

    private var statsStripSection: some View {
        let completed = allRounds.filter(\.isComplete)
        let allStats = completed.map { StatsCalculator.calculate(holes: $0.holes) }
        let avgScore = allStats.isEmpty ? 0.0 : Double(allStats.reduce(0) { $0 + $1.totalStrokes }) / Double(allStats.count)
        let avgPutts = allStats.isEmpty ? 0.0 : Double(allStats.reduce(0) { $0 + $1.totalPutts }) / Double(allStats.count)
        let avgGIR = allStats.isEmpty ? 0.0 : allStats.reduce(0.0) { $0 + $1.greensInRegulationPct } / Double(allStats.count)
        let bestScore = allStats.map(\.totalStrokes).min() ?? 0

        return HStack(spacing: 0) {
            StatsPill(value: String(format: "%.0f", avgScore), label: "Avg", highlight: false)
            Divider().frame(height: 28).background(Color.white.opacity(0.08))
            StatsPill(value: "\(bestScore)", label: "Best", highlight: false)
            Divider().frame(height: 28).background(Color.white.opacity(0.08))
            StatsPill(value: String(format: "%.0f", avgPutts), label: "Putts", highlight: false)
            Divider().frame(height: 28).background(Color.white.opacity(0.08))
            StatsPill(value: String(format: "%.0f%%", avgGIR), label: "GIR", highlight: avgGIR >= 50)
            Divider().frame(height: 28).background(Color.white.opacity(0.08))
            StatsPill(value: "\(totalRoundsPlayed)", label: "Rounds", highlight: false)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Recent Rounds

    private var recentRoundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                NavigationLink {
                    HistoryView()
                } label: {
                    Text("See All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            ForEach(recentCompleted) { round in
                NavigationLink {
                    RoundSummaryView(round: round, onDone: {})
                } label: {
                    RecentRoundCard(round: round)
                }
            }
        }
    }

    // MARK: - Navigation Grid

    private var navigationSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                NavCard(icon: "clock.arrow.circlepath", title: "History", accent: .blue) {
                    NavigationLink { HistoryView() } label: { Color.clear }
                }
                NavCard(icon: "chart.xyaxis.line", title: "Stats", accent: .purple) {
                    NavigationLink { StatsDeepDiveView() } label: { Color.clear }
                }
            }
            HStack(spacing: 10) {
                NavCard(icon: "bag.fill", title: "My Bag", accent: .orange) {
                    NavigationLink { BagView() } label: { Color.clear }
                }
                NavCard(icon: "gear", title: "Settings", accent: .gray) {
                    NavigationLink { Text("Settings") } label: { Color.clear }
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct StatsPill: View {
    let value: String
    let label: String
    let highlight: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? .green : .white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecentRoundCard: View {
    let round: Round

    private var stats: RoundStats {
        StatsCalculator.calculate(holes: round.holes)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Score circle
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.12))
                    .overlay(Circle().stroke(scoreColor.opacity(0.25), lineWidth: 1))
                Text("\(stats.totalStrokes)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(round.courseName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(round.date.formatted(.dateTime.month(.abbreviated).day()))
                        .foregroundStyle(.white.opacity(0.4))
                    if stats.totalPutts > 0 {
                        Text("\(stats.totalPutts)P")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if stats.girHoles > 0 {
                        Text("\(stats.greensInRegulation)G")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .font(.system(size: 11))
            }

            Spacer()

            let stp = stats.scoreToPar
            Text(stp == 0 ? "E" : (stp > 0 ? "+\(stp)" : "\(stp)"))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.15))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var scoreColor: Color {
        let stp = stats.scoreToPar
        if stp < 0 { return .red }
        if stp == 0 { return .green }
        if stp <= 5 { return .cyan }
        return .white.opacity(0.6)
    }
}

private struct NavCard<Destination: View>: View {
    let icon: String
    let title: String
    let accent: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        ZStack {
            destination()
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(16)
        }
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }
}

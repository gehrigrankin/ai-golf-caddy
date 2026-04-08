import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Round.date, order: .reverse) private var allRounds: [Round]
    @State private var showNewRound = false

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero
                    VStack(spacing: 8) {
                        Text("⛳")
                            .font(.system(size: 48))
                        Text("AI Caddy")
                            .font(.largeTitle.bold())
                        Text("Track your round with voice.\nGet the stats you never had time to log.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Handicap Index
                    if let handicap = calculatedHandicap {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HANDICAP INDEX")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f", handicap))
                                    .font(.system(size: 28, weight: .bold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(handicapRounds.count) rounds")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("WHS")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Resume in-progress
                    if let inProgress = inProgressRound {
                        Button { showNewRound = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ROUND IN PROGRESS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.orange)
                                    Text(inProgress.courseName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Hole \(inProgress.currentHole) · \(inProgress.teeName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(inProgress.holes.reduce(0) { $0 + $1.strokes })")
                                        .font(.title.bold())
                                    Text(inProgress.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // Start new round
                    Button { showNewRound = true } label: {
                        Text("Start New Round")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Quick links
                    HStack(spacing: 12) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            QuickLink(icon: "chart.bar.fill", title: "History",
                                      sub: "\(recentCompleted.count) rounds")
                        }
                        NavigationLink {
                            HistoryView()
                        } label: {
                            QuickLink(icon: "chart.line.uptrend.xyaxis", title: "Stats",
                                      sub: "Trends")
                        }
                    }

                    // Recent rounds
                    if !recentCompleted.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Rounds")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)

                            ForEach(recentCompleted) { round in
                                NavigationLink {
                                    RoundSummaryView(round: round, onDone: {})
                                } label: {
                                    RoundRow(round: round)
                                        .padding(12)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .fullScreenCover(isPresented: $showNewRound) {
                RoundView(
                    locationService: locationService,
                    speechService: speechService,
                    shotParser: shotParser,
                    courseSearch: courseSearch,
                    clubRecommender: clubRecommender
                )
            }
        }
    }
}

struct QuickLink: View {
    let icon: String
    let title: String
    let sub: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
            Text(title).font(.subheadline.bold())
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

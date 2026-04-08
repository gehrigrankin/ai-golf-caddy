import SwiftUI
import SwiftData

struct RoundView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let locationService: LocationService
    let speechService: SpeechService
    let shotParser: ShotParserService
    let courseSearch: CourseSearchService
    let clubRecommender: ClubRecommendationService

    @Query(sort: \Course.createdAt, order: .reverse) private var savedCourses: [Course]
    @Query(filter: #Predicate<Round> { $0.isComplete }, sort: \Round.date) private var completedRounds: [Round]

    @State private var phase: Phase = .search
    @State private var round: Round?
    @State private var activeCourse: Course?
    @State private var currentHole = 1
    @State private var showScorecard = false

    enum Phase { case search, setup, play, summary }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .search:
                    CourseSearchView(
                        courseSearch: courseSearch,
                        locationService: locationService,
                        onCourseLoaded: { course in
                            modelContext.insert(course)
                            activeCourse = course
                            if course.tees.count == 1 {
                                startRound(course: course, teeName: course.tees[0].name)
                            } else {
                                phase = .setup
                            }
                        },
                        onSkip: { phase = .setup }
                    )
                    .navigationTitle("New Round")

                case .setup:
                    CourseSetupView(
                        onComplete: { course, tee in
                            if activeCourse == nil {
                                modelContext.insert(course)
                            }
                            activeCourse = course
                            startRound(course: course, teeName: tee)
                        },
                        existingCourses: {
                            if let ac = activeCourse {
                                return [ac] + savedCourses.filter { $0.id != ac.id }
                            }
                            return savedCourses.map { $0 }
                        }()
                    )
                    .navigationTitle(activeCourse != nil ? "Select Tee" : "New Round")

                case .play:
                    if let round, var hole = currentHoleBinding {
                        VStack(spacing: 0) {
                            if showScorecard {
                                ScrollView {
                                    VStack(spacing: 12) {
                                        ScorecardView(
                                            holes: round.holes,
                                            courseName: round.courseName,
                                            teeName: round.teeName,
                                            onHoleTap: { n in
                                                currentHole = n
                                                showScorecard = false
                                            }
                                        )
                                        Text("Tap a hole to jump to it")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding()
                                }
                            } else {
                                HolePlayView(
                                    hole: holeBinding,
                                    holeGps: currentHoleGps,
                                    userLocation: locationService.location,
                                    totalScore: round.holes.reduce(0) { $0 + $1.strokes },
                                    totalPar: round.holes.filter { $0.strokes > 0 }.reduce(0) { $0 + $1.par },
                                    onNext: {
                                        if currentHole < 18 {
                                            currentHole += 1
                                        } else {
                                            finishRound()
                                        }
                                    },
                                    onPrev: {
                                        if currentHole > 1 { currentHole -= 1 }
                                    },
                                    isFirst: currentHole == 1,
                                    isLast: currentHole == 18,
                                    speech: speechService,
                                    shotParser: shotParser,
                                    clubRecommendation: currentClubRecommendation
                                )
                            }

                            // Hole dots
                            if !showScorecard {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(round.holes) { h in
                                            Button {
                                                currentHole = h.holeNumber
                                            } label: {
                                                Text("\(h.holeNumber)")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .frame(width: 28, height: 28)
                                                    .background(
                                                        h.holeNumber == currentHole ? Color.green :
                                                            h.strokes > 0 ? Color(.systemGray4) : Color(.systemGray6)
                                                    )
                                                    .foregroundStyle(h.holeNumber == currentHole ? .white : .primary)
                                                    .clipShape(Circle())
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .navigationTitle("Hole \(currentHole)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(showScorecard ? "Hole" : "Card") {
                                    showScorecard.toggle()
                                }
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                            }
                        }
                    }

                case .summary:
                    if let round {
                        RoundSummaryView(
                            round: round,
                            onDone: { dismiss() },
                            onHoleTap: { n in
                                currentHole = n
                                showScorecard = false
                                phase = .play
                            }
                        )
                        .navigationTitle("Summary")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if phase == .play {
                            // Save progress before leaving
                            dismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Home")
                        }
                    }
                }
            }
        }
        .onAppear {
            locationService.startTracking()
            speechService.requestAuthorization()
            clubRecommender.loadHistory(rounds: completedRounds)
        }
        .onDisappear {
            locationService.stopTracking()
            speechService.stopListening()
        }
    }

    // MARK: - Hole binding

    private var holeBinding: Binding<HoleScore> {
        Binding(
            get: {
                round?.holes.first { $0.holeNumber == currentHole }
                    ?? HoleScore(holeNumber: currentHole, par: 4)
            },
            set: { newValue in
                guard var holes = round?.holes,
                      let idx = holes.firstIndex(where: { $0.holeNumber == currentHole })
                else { return }
                holes[idx] = newValue
                round?.holes = holes
            }
        )
    }

    private var currentHoleBinding: HoleScore? {
        round?.holes.first { $0.holeNumber == currentHole }
    }

    private var currentHoleGps: HoleGps? {
        activeCourse?.tees.first?.holes.first { $0.holeNumber == currentHole }?.gps
    }

    /// Club recommendation based on GPS distance to green center
    private var currentClubRecommendation: ClubRecommendation? {
        guard let loc = locationService.location,
              let greenCenter = currentHoleGps?.greenCenter
        else { return nil }
        let dist = LocationService.distanceYards(from: loc, to: greenCenter.coordinate)
        // Only recommend for approach shots (not on the green, not teeing off on par 4/5)
        guard dist > 30 && dist < 300 else { return nil }
        return clubRecommender.recommend(distanceYards: dist)
    }

    // MARK: - Actions

    private func startRound(course: Course, teeName: String) {
        guard let tee = course.tees.first(where: { $0.name == teeName }) ?? course.tees.first else { return }

        let holes = tee.holes.map { h in
            HoleScore(holeNumber: h.holeNumber, par: h.par, yardage: h.yardage)
        }

        let newRound = Round(
            courseId: course.id,
            courseName: course.name,
            teeName: tee.name,
            holes: holes,
            courseTee: tee
        )

        modelContext.insert(newRound)
        round = newRound
        currentHole = 1
        phase = .play
    }

    private func finishRound() {
        round?.isComplete = true
        phase = .summary
    }
}

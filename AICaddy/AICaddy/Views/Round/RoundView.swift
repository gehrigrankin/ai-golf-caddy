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
    /// Resume an in-progress round instead of starting a new one.
    var existingRound: Round? = nil

    @Query(sort: \Course.createdAt, order: .reverse) private var savedCourses: [Course]
    @Query(filter: #Predicate<Round> { $0.isComplete == true }, sort: \Round.date) private var completedRounds: [Round]

    @State private var phase: Phase = .search
    @State private var round: Round?
    @State private var activeCourse: Course?
    @State private var currentHole = 1
    @State private var showScorecard = false
    /// Decoded once — Round.courseTee decodes JSON on every access, far too hot
    /// for a body that re-evaluates on every GPS tick.
    @State private var activeTee: CourseTee?
    @State private var autoAdvance = AutoAdvanceService()

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
                    if let round, currentHoleScore != nil {
                        VStack(spacing: 0) {
                            // Auto-advance suggestion banner
                            if let suggested = autoAdvance.suggestedAdvance {
                                HStack(spacing: 10) {
                                    Image(systemName: "figure.walk")
                                        .foregroundStyle(.green)
                                    Text("At hole \(suggested) tee box")
                                        .font(.subheadline)
                                    Spacer()
                                    Button("Advance") {
                                        currentHole = suggested
                                        autoAdvance.confirmAdvance()
                                        HapticsService.holeAdvanced()
                                    }
                                    .font(.subheadline.bold())
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    Button {
                                        autoAdvance.dismissAdvance()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.12))
                            }

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
                                    holesPlayed: round.holes.filter { $0.strokes > 0 }.count,
                                    onNext: {
                                        if currentHole < lastHoleNumber {
                                            currentHole += 1
                                        } else {
                                            finishRound()
                                        }
                                    },
                                    onPrev: {
                                        if currentHole > 1 { currentHole -= 1 }
                                    },
                                    isFirst: currentHole == 1,
                                    isLast: currentHole == lastHoleNumber,
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
                        // Progress is already persisted (round + currentHole);
                        // the round shows up as resumable on the home screen.
                        dismiss()
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
            resumeIfNeeded()
        }
        .onChange(of: currentHole) { _, newValue in
            round?.currentHole = newValue
        }
        .onChange(of: locationService.fixCount) {
            checkAutoAdvance()
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

    private var currentHoleScore: HoleScore? {
        round?.holes.first { $0.holeNumber == currentHole }
    }

    /// Highest hole number in this round — 9-hole courses exist, never assume 18.
    private var lastHoleNumber: Int {
        round?.holes.map(\.holeNumber).max() ?? 18
    }

    /// GPS for the current hole, from the tee that was actually played (stored
    /// on the round itself so it survives app restarts / resume).
    private var currentHoleGps: HoleGps? {
        activeTee?.holes.first { $0.holeNumber == currentHole }?.gps
    }

    private var nextTeeGps: GpsPoint? {
        activeTee?.holes.first { $0.holeNumber == currentHole + 1 }?.gps?.tee
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

    private func resumeIfNeeded() {
        guard round == nil, let existing = existingRound, !existing.isComplete else { return }
        round = existing
        activeTee = existing.courseTee
        activeCourse = savedCourses.first { $0.id == existing.courseId }
        let maxHole = existing.holes.map(\.holeNumber).max() ?? 18
        currentHole = min(max(1, existing.currentHole), maxHole)
        phase = .play
    }

    private func startRound(course: Course, teeName: String) {
        guard let tee = course.tees.first(where: { $0.name == teeName }) ?? course.tees.first else { return }

        var holes = tee.holes.map { h in
            HoleScore(holeNumber: h.holeNumber, par: h.par, yardage: h.yardage)
        }
        // A course loaded from the API can come back with no hole data — a round
        // with zero holes renders a permanently blank screen. Fall back to a
        // standard 18 so the round is still playable.
        if holes.isEmpty {
            holes = (1...18).map { HoleScore(holeNumber: $0, par: 4) }
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
        activeTee = tee
        currentHole = 1
        phase = .play
    }

    private func finishRound() {
        round?.currentHole = currentHole
        round?.isComplete = true
        HapticsService.roundComplete()
        phase = .summary
    }

    private func checkAutoAdvance() {
        guard phase == .play, let loc = locationService.location, round != nil else { return }
        let scored = (currentHoleScore?.strokes ?? 0) > 0
        autoAdvance.checkForAdvance(
            currentHole: currentHole,
            userLocation: loc,
            nextTeebox: nextTeeGps,
            lastHole: lastHoleNumber,
            hasScoredCurrentHole: scored
        )
    }
}

import SwiftUI
import SwiftData

struct RoundView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let locationService: LocationService
    let speechService: SpeechService
    let shotParser: ShotParserService
    let clubRecommender: ClubRecommendationService

    /// Pass an in-progress round to resume it instead of starting a new one.
    var existingRound: Round?

    @Query(sort: \Course.createdAt, order: .reverse) private var savedCourses: [Course]
    @Query(filter: #Predicate<Round> { $0.isComplete == true }, sort: \Round.date) private var completedRounds: [Round]
    @Query private var bags: [GolfBag]

    @State private var phase: Phase = .search
    @State private var round: Round?
    @State private var activeCourse: Course?
    @State private var currentHole = 1
    @State private var showScorecard = false
    @State private var showDiscardConfirm = false
    @State private var weather = WeatherService()
    @State private var autoAdvance = AutoAdvanceService()
    @State private var watchBridge = PhoneWatchBridge()
    @State private var lastWatchPush = Date.distantPast

    @AppStorage("autoAdvanceEnabled") private var autoAdvanceEnabled = true

    enum Phase { case search, setup, play, summary }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .search:
                    CourseSearchView(
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
                    if let round {
                        VStack(spacing: 0) {
                            // Auto-advance suggestion
                            if let next = autoAdvance.suggestedAdvance {
                                autoAdvanceBanner(next: next)
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
                                    clubRecommendation: currentClubRecommendation,
                                    weather: weather,
                                    playsLikeToCenter: playsLikeToCenter
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
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button {
                                        finishRound()
                                    } label: {
                                        Label("Finish Round", systemImage: "flag.checkered")
                                    }
                                    Button(role: .destructive) {
                                        showDiscardConfirm = true
                                    } label: {
                                        Label("Discard Round", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .confirmationDialog(
                            "Discard this round? All scores will be deleted.",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Discard Round", role: .destructive) { discardRound() }
                            Button("Keep Playing", role: .cancel) {}
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
                        // Progress is already saved (scores + current hole persist
                        // on every change) — leaving just closes the screen and the
                        // round shows up on Home ready to resume.
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
            clubRecommender.loadBag(bags.first)
            autoAdvance.isEnabled = autoAdvanceEnabled
            watchBridge.onScoreInput = { input, hole in
                applyWatchInput(input, hole: hole)
            }

            // Resume an in-progress round exactly where it was left
            if round == nil, let existing = existingRound, !existing.isComplete {
                round = existing
                currentHole = min(max(existing.currentHole, 1), 18)
                phase = .play
            }
            pushWatchState()
        }
        .onDisappear {
            locationService.stopTracking()
            speechService.cancelListening()
        }
        .onChange(of: currentHole) {
            round?.currentHole = currentHole
            autoAdvance.confirmAdvance()  // reset suggestion state on any hole change
            pushWatchState()
        }
        .onChange(of: round?.holes.reduce(0) { $0 + $1.strokes }) {
            pushWatchState()
        }
        .onChange(of: locationService.location?.latitude) {
            handleLocationUpdate()
        }
        .task(id: phase) {
            guard phase == .play else { return }
            await refreshWeatherIfNeeded()
        }
    }

    // MARK: - Auto-advance banner

    private func autoAdvanceBanner(next: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .foregroundStyle(.green)
            Text("Looks like you're at hole \(next)")
                .font(.subheadline)
            Spacer()
            Button("Go") {
                currentHole = next
            }
            .font(.subheadline.bold())
            .foregroundStyle(.green)
            Button {
                autoAdvance.dismissAdvance()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.12))
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

    private var currentHoleGps: HoleGps? {
        // The round carries its own copy of the tee data, so GPS works on
        // resume too (activeCourse is nil after an app relaunch).
        if let gps = round?.courseTee?.holes.first(where: { $0.holeNumber == currentHole })?.gps {
            return gps
        }
        return activeCourse?.tees.first?.holes.first { $0.holeNumber == currentHole }?.gps
    }

    private func holeGps(for holeNumber: Int) -> HoleGps? {
        round?.courseTee?.holes.first(where: { $0.holeNumber == holeNumber })?.gps
    }

    // MARK: - Conditions ("plays like")

    private var distanceToCenter: Int? {
        guard let loc = locationService.location,
              let green = currentHoleGps?.greenCenter else { return nil }
        return LocationService.distanceYards(from: loc, to: green.coordinate)
    }

    /// Wind + temperature adjusted distance to the green center
    private var playsLikeToCenter: Int? {
        guard let loc = locationService.location,
              let green = currentHoleGps?.greenCenter,
              let dist = distanceToCenter,
              weather.hasWind || weather.temperature != nil else { return nil }
        let bearing = LocationService.bearingDegrees(from: loc, to: green.coordinate)
        let playsLike = weather.playsLikeDistance(yards: dist, shotBearing: bearing)
        return playsLike == dist ? nil : playsLike
    }

    /// Club recommendation based on GPS distance, adjusted for conditions
    private var currentClubRecommendation: ClubRecommendation? {
        guard let dist = distanceToCenter else { return nil }
        // Only recommend for realistic full shots (not on the green, not 400y out)
        guard dist > 30 && dist < 320 else { return nil }

        var note: String?
        if let playsLike = playsLikeToCenter {
            let delta = playsLike - dist
            if delta != 0, weather.hasWind {
                note = "\(delta > 0 ? "+" : "")\(delta)y wind"
            }
        }
        return clubRecommender.recommend(
            distanceYards: dist,
            playsLikeYards: playsLikeToCenter,
            conditionsNote: note
        )
    }

    private func refreshWeatherIfNeeded() async {
        guard weather.isStale else { return }
        let coordinate = locationService.location
            ?? activeCourse?.location?.coordinate
            ?? round?.courseTee?.holes.first?.gps?.tee?.coordinate
        guard let coordinate else { return }
        await weather.fetchWeather(at: coordinate)
    }

    // MARK: - Location-driven behavior

    private func handleLocationUpdate() {
        guard phase == .play, let loc = locationService.location else { return }

        // Suggest advancing when the player walks to the next tee box
        if currentHole < 18 {
            autoAdvance.checkForAdvance(
                currentHole: currentHole,
                userLocation: loc,
                nextTeebox: holeGps(for: currentHole + 1)?.tee
            )
        }

        // Keep the watch's distance fresh, gently throttled
        if Date().timeIntervalSince(lastWatchPush) > 15 {
            pushWatchState()
        }
    }

    // MARK: - Watch

    private func pushWatchState() {
        lastWatchPush = Date()
        guard let round, phase == .play || phase == .summary else {
            watchBridge.roundEnded()
            return
        }
        let played = round.holes.filter { $0.strokes > 0 }
        let totalScore = played.reduce(0) { $0 + $1.strokes }
        let totalPar = played.reduce(0) { $0 + $1.par }
        let par = round.holes.first { $0.holeNumber == currentHole }?.par ?? 4

        var dist: Int?
        if let loc = locationService.location, let green = currentHoleGps?.greenCenter {
            dist = LocationService.distanceYards(from: loc, to: green.coordinate)
        }

        watchBridge.updateState(
            currentHole: currentHole,
            currentPar: par,
            totalScore: totalScore,
            scoreToPar: totalScore - totalPar,
            distToGreen: dist,
            courseName: round.courseName,
            isRoundActive: phase == .play && !round.isComplete
        )
    }

    /// Score arriving from the Apple Watch ("par", "5", "2 putts", ...)
    private func applyWatchInput(_ input: String, hole holeNumber: Int) {
        guard let round else { return }
        let target = holeNumber > 0 ? holeNumber : currentHole
        guard var holes = Optional(round.holes),
              let idx = holes.firstIndex(where: { $0.holeNumber == target }) else { return }

        let parsed = shotParser.localParse(
            input: input,
            par: holes[idx].par,
            currentShotNumber: holes[idx].shots.count + 1
        )
        if let strokes = parsed.totalStrokes { holes[idx].strokes = strokes }
        if let putts = parsed.putts { holes[idx].putts = putts }
        if !parsed.shots.isEmpty {
            holes[idx].shots.append(contentsOf: parsed.shots)
            if parsed.totalStrokes == nil {
                // Count penalty strokes, and never downgrade an entered score
                let fromShots = holes[idx].shots.count + holes[idx].shots.filter(\.isPenalty).count
                holes[idx].strokes = max(holes[idx].strokes, fromShots)
            }
        }
        StatsCalculator.deriveHoleStats(&holes[idx])
        round.holes = holes
        pushWatchState()
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
        pushWatchState()
    }

    private func finishRound() {
        guard let round else { return }
        guard round.holes.contains(where: { $0.strokes > 0 }) else {
            // Nothing recorded — treat "finish" as discard rather than saving
            // an empty round that would pollute history and handicap.
            discardRound()
            return
        }
        round.isComplete = true
        phase = .summary
        pushWatchState()
    }

    private func discardRound() {
        if let round {
            modelContext.delete(round)
        }
        round = nil
        watchBridge.roundEnded()
        dismiss()
    }
}

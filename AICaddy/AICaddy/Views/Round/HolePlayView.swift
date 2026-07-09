import SwiftUI
import CoreLocation

struct HolePlayView: View {
    @Binding var hole: HoleScore
    let holeGps: HoleGps?
    let userLocation: CLLocationCoordinate2D?
    let totalScore: Int
    let totalPar: Int
    let onNext: () -> Void
    let onPrev: () -> Void
    let isFirst: Bool
    let isLast: Bool

    @State private var parsing = false
    @State private var lastParse = ""
    @State private var showMap = true
    @State private var showWindSheet = false

    @Bindable var speech: SpeechService
    let shotParser: ShotParserService
    var clubRecommendation: ClubRecommendation?
    var weather: WeatherService?
    var playsLikeToCenter: Int?

    @AppStorage("showWind") private var showWind = true

    private var runningToPar: Int { totalScore - totalPar }
    private var holesPlayed: Int { hole.holeNumber - 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Running score
                HStack {
                    Text(runningToPar == 0 ? "E" : (runningToPar > 0 ? "+\(runningToPar)" : "\(runningToPar)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    + Text(" thru \(holesPlayed > 0 ? "\(holesPlayed)" : "-")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalScore) strokes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Hole header
                VStack(spacing: 4) {
                    Text("Hole \(hole.holeNumber)")
                        .font(.system(size: 36, weight: .bold))
                    HStack(spacing: 12) {
                        Text("Par \(hole.par)")
                            .foregroundStyle(.secondary)
                        if let y = hole.yardage {
                            Text("\(y) yds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Wind & conditions chip — tap to set wind manually when
                // there's no weather data (or to correct it)
                if showWind, let weather {
                    Button { showWindSheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wind")
                                .font(.caption)
                            if let summary = weather.windSummary {
                                Text(summary)
                                if weather.isManual {
                                    Text("(manual)").foregroundStyle(.tertiary)
                                }
                            } else {
                                Text("Set wind")
                            }
                            if let temp = weather.temperature {
                                Text("· \(temp)°")
                            }
                            if let playsLike = playsLikeToCenter {
                                Text("· plays \(playsLike)y")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }

                // Map (with GPS) or distance-less fallback
                if showMap, let gps = holeGps {
                    HoleMapView(
                        holeGps: gps,
                        holeNumber: hole.holeNumber,
                        par: hole.par,
                        userLocation: userLocation,
                        playsLikeCenter: playsLikeToCenter
                    )
                } else if holeGps == nil, hole.yardage == nil {
                    Text("No GPS data for this hole — enter scores below")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Score +/- with circle
                HStack(spacing: 24) {
                    Button { adjustStrokes(-1) } label: {
                        Image(systemName: "minus")
                            .font(.title2.bold())
                            .frame(width: 56, height: 56)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }

                    VStack(spacing: 4) {
                        ScoreCircle(strokes: hole.strokes, par: hole.par, size: 80)
                        if hole.strokes > 0 {
                            Text(hole.scoreLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button { adjustStrokes(1) } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .frame(width: 56, height: 56)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: hole.strokes)

                // Quick stats: Putts, Fairway, GIR
                HStack(spacing: 8) {
                    // Putts
                    VStack(spacing: 4) {
                        Text("Putts").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button { adjustPutts(-1) } label: {
                                Image(systemName: "minus").font(.caption)
                                    .frame(width: 28, height: 28)
                                    .background(Color(.systemGray5))
                                    .clipShape(Circle())
                            }
                            Text(hole.putts.map { "\($0)" } ?? "-")
                                .font(.title3.bold())
                                .frame(width: 24)
                            Button { adjustPutts(1) } label: {
                                Image(systemName: "plus").font(.caption)
                                    .frame(width: 28, height: 28)
                                    .background(Color(.systemGray5))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Fairway
                    Button { toggleFairway() } label: {
                        VStack(spacing: 4) {
                            Text("Fairway").font(.caption).foregroundStyle(.secondary)
                            Text(fairwayText)
                                .font(.title3.bold())
                                .foregroundStyle(fairwayColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(fairwayBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(hole.par < 4)
                    .opacity(hole.par < 4 ? 0.4 : 1)

                    // GIR
                    Button { toggleGIR() } label: {
                        VStack(spacing: 4) {
                            Text("GIR").font(.caption).foregroundStyle(.secondary)
                            Text(girText)
                                .font(.title3.bold())
                                .foregroundStyle(girColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(girBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Club recommendation (the AI caddy!)
                if let rec = clubRecommendation {
                    ClubRecommendationView(recommendation: rec)
                }

                // Quick-input buttons for common scores
                QuickScoreButtons(par: hole.par) { input in
                    handleInput(input)
                }

                // Voice / text input
                VoiceInputView(
                    onResult: handleInput,
                    disabled: parsing,
                    placeholder: voicePrompt,
                    speech: speech
                )

                if parsing {
                    Text("Processing...")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                if !lastParse.isEmpty && !parsing {
                    Text("Recorded: \(lastParse)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Shot log
                if !hole.shots.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Shot Log").font(.subheadline.bold()).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") { clearShots() }
                                .font(.caption).foregroundStyle(.red)
                        }
                        ForEach(hole.shots) { shot in
                            HStack(spacing: 8) {
                                Text("\(shot.shotNumber).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                if let club = shot.club {
                                    Text(club.displayName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                }
                                if let dist = shot.distanceYards {
                                    Text("\(dist)y")
                                        .font(.subheadline)
                                }
                                if let result = shot.result {
                                    Text(result.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                if shot.isPutt {
                                    Text("putt")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Navigation
                HStack(spacing: 12) {
                    Button { onPrev() } label: {
                        Text("Prev Hole")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)

                    Button { onNext() } label: {
                        Text(isLast ? "Finish Round" : "Next Hole")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showWindSheet) {
            if let weather {
                ManualWindSheet(weather: weather)
                    .presentationDetents([.height(320)])
            }
        }
    }

    // MARK: - Actions

    private func adjustStrokes(_ delta: Int) {
        hole.strokes = max(0, hole.strokes + delta)
        StatsCalculator.deriveHoleStats(&hole)
    }

    private func adjustPutts(_ delta: Int) {
        hole.putts = max(0, (hole.putts ?? 0) + delta)
    }

    private func toggleFairway() {
        guard hole.par >= 4 else { return }
        switch hole.fairwayHit {
        case true: hole.fairwayHit = false
        case false: hole.fairwayHit = nil
        default: hole.fairwayHit = true
        }
    }

    private func toggleGIR() {
        switch hole.greenInRegulation {
        case true: hole.greenInRegulation = false
        case false: hole.greenInRegulation = nil
        default: hole.greenInRegulation = true
        }
    }

    private func clearShots() {
        hole.shots = []
        hole.strokes = 0
        hole.putts = nil
        hole.fairwayHit = nil
        hole.greenInRegulation = nil
        hole.upAndDown = nil
        hole.sandSave = nil
        lastParse = ""
    }

    private func handleInput(_ input: String) {
        parsing = true
        lastParse = ""

        Task {
            let parsed = await shotParser.parse(
                input: input,
                holeNumber: hole.holeNumber,
                par: hole.par,
                yardage: hole.yardage,
                currentShotNumber: hole.shots.count + 1
            )

            await MainActor.run {
                let hadShotsBefore = !hole.shots.isEmpty

                if let strokes = parsed.totalStrokes {
                    hole.strokes = strokes
                    lastParse = "Score: \(strokes)"
                }

                if !parsed.shots.isEmpty {
                    hole.shots.append(contentsOf: parsed.shots)
                    if parsed.totalStrokes == nil {
                        // Count penalties (water/OB) on top of swings, and never
                        // DOWNGRADE a score the golfer already entered — adding
                        // "2 putts" after saying "5" must not turn the 5 into a 2.
                        let fromShots = hole.shots.count + hole.shots.filter(\.isPenalty).count
                        hole.strokes = max(hole.strokes, fromShots)
                    }
                    let desc = parsed.shots.map { s in
                        [s.club?.displayName, s.distanceYards.map { "\($0)y" }, s.result?.displayName]
                            .compactMap { $0 }.joined(separator: " ")
                    }.joined(separator: ", ")
                    lastParse = desc.isEmpty ? "shots added" : desc
                }

                if let putts = parsed.putts { hole.putts = putts }
                // "fairway" only means FIR when it describes the TEE shot — a
                // par-5 layup finding the fairway isn't a fairway in regulation.
                if let fir = parsed.fairwayHit, !hadShotsBefore || fir == false {
                    hole.fairwayHit = fir
                }
                if let gir = parsed.greenInRegulation { hole.greenInRegulation = gir }

                StatsCalculator.deriveHoleStats(&hole)
                parsing = false
            }
        }
    }

    // MARK: - Display helpers

    private var fairwayText: String {
        hole.par < 4 ? "N/A" : (hole.fairwayHit == true ? "Hit" : hole.fairwayHit == false ? "Miss" : "-")
    }
    private var fairwayColor: Color {
        hole.fairwayHit == true ? .green : hole.fairwayHit == false ? .red : .primary
    }
    private var fairwayBg: Color {
        hole.fairwayHit == true ? .green.opacity(0.15) : hole.fairwayHit == false ? .red.opacity(0.15) : Color(.systemGray6)
    }
    private var girText: String {
        hole.greenInRegulation == true ? "Yes" : hole.greenInRegulation == false ? "No" : "-"
    }
    private var girColor: Color {
        hole.greenInRegulation == true ? .green : hole.greenInRegulation == false ? .red : .primary
    }
    private var girBg: Color {
        hole.greenInRegulation == true ? .green.opacity(0.15) : hole.greenInRegulation == false ? .red.opacity(0.15) : Color(.systemGray6)
    }

    /// Context-aware voice prompt that changes based on what shot you're on
    private var voicePrompt: String {
        let shotNum = hole.shots.count + 1
        if shotNum == 1 {
            // Tee shot
            if hole.par == 3 { return "\"7 iron on the green\" or \"par\"" }
            return "\"driver 250 fairway\" or \"\(hole.par)\""
        } else if hole.greenInRegulation == true || hole.shots.last?.result == .green {
            // On the green
            return "\"2 putts\" or \"1 putt birdie\""
        } else if shotNum == hole.par - 1 {
            // Approach shot
            return "\"8 iron on the green\" or \"bunker\""
        } else if hole.shots.last?.result == .bunker {
            return "\"sand wedge on the green\" or \"chip and a putt\""
        } else {
            return "\"chip and 2 putts\" or \"bogey\""
        }
    }
}

// MARK: - Manual Wind Entry

/// Set wind by feel when WeatherKit data isn't available on the course.
struct ManualWindSheet: View {
    @Bindable var weather: WeatherService
    @Environment(\.dismiss) private var dismiss

    @State private var speed: Double = 10
    @State private var directionIndex: Int = 0

    private static let directions: [(label: String, degrees: Double)] = [
        ("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
        ("S", 180), ("SW", 225), ("W", 270), ("NW", 315),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("Wind")
                .font(.headline)

            HStack {
                Text("Speed")
                    .foregroundStyle(.secondary)
                Slider(value: $speed, in: 0...40, step: 1)
                Text("\(Int(speed)) mph")
                    .font(.subheadline.bold())
                    .frame(width: 60, alignment: .trailing)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Blowing from")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Direction", selection: $directionIndex) {
                    ForEach(Self.directions.indices, id: \.self) { i in
                        Text(Self.directions[i].label).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                if weather.isManual {
                    Button("Clear") {
                        weather.clearManualWind()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    weather.setManualWind(
                        speedMph: speed,
                        directionDegrees: Self.directions[directionIndex].degrees
                    )
                    dismiss()
                } label: {
                    Text("Set Wind")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .onAppear {
            if let s = weather.windSpeed { speed = s.rounded() }
            if let d = weather.windDirection {
                // nearest compass segment
                let idx = Self.directions.enumerated().min(by: {
                    angleDelta($0.element.degrees, d) < angleDelta($1.element.degrees, d)
                })?.offset ?? 0
                directionIndex = idx
            }
        }
    }

    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }
}

// MARK: - Quick Score Buttons

struct QuickScoreButtons: View {
    let par: Int
    let onInput: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Quick Input")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                QuickButton(label: "Birdie", sub: "\(par - 1)", color: .red) {
                    onInput("birdie")
                }
                QuickButton(label: "Par", sub: "\(par)", color: .green) {
                    onInput("par")
                }
                QuickButton(label: "Bogey", sub: "\(par + 1)", color: .cyan) {
                    onInput("bogey")
                }
                QuickButton(label: "Dbl", sub: "\(par + 2)", color: .blue) {
                    onInput("double bogey")
                }
            }
        }
    }
}

private struct QuickButton: View {
    let label: String
    let sub: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(sub)
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

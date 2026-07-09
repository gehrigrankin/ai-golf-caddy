import XCTest
import CoreLocation
@testable import AICaddy

/// Unit tests for the on-course core logic. These mirror the assertions in
/// AICaddy/Simulation (the Linux round simulator) — keep both in sync.
final class ShotParserTests: XCTestCase {
    let parser = ShotParserService(apiKey: "")

    func parse(_ input: String, par: Int = 4, shotNumber: Int = 1) -> ParsedShotInput {
        parser.localParse(input: input, par: par, currentShotNumber: shotNumber)
    }

    // MARK: Simple scores

    func testBareNumber() {
        XCTAssertEqual(parse("4").totalStrokes, 4)
    }

    func testScoreWords() {
        XCTAssertEqual(parse("par", par: 4).totalStrokes, 4)
        XCTAssertEqual(parse("birdie", par: 4).totalStrokes, 3)
        XCTAssertEqual(parse("eagle", par: 5).totalStrokes, 3)
        XCTAssertEqual(parse("double bogey", par: 4).totalStrokes, 6)
        XCTAssertEqual(parse("four").totalStrokes, 4)          // speech returns words
        XCTAssertEqual(parse("made par", par: 4).totalStrokes, 4)
        XCTAssertEqual(parse("par with 2 putts", par: 4).putts, 2)
    }

    func testPuttsExpandIntoShots() {
        let r = parse("2 putts")
        XCTAssertEqual(r.putts, 2)
        XCTAssertEqual(r.shots.count, 2)
        XCTAssertTrue(r.shots.allSatisfy(\.isPutt))
        XCTAssertEqual(r.shots.last?.result, .holed)
    }

    // MARK: Regression tests for on-course bugs

    func testSandWedgeOnGreenIsNotBunker() {
        // "sand" used to match before "green" and record a bunker
        let r = parse("sand wedge on the green")
        XCTAssertEqual(r.shots.first?.club, .sw)
        XCTAssertEqual(r.shots.first?.result, .green)
    }

    func testLobWedgeIsNotPenalty() {
        // "lob" contains "ob" — used to flag out-of-bounds penalty
        let r = parse("lob wedge to the green")
        XCTAssertEqual(r.shots.first?.club, .lw)
        XCTAssertEqual(r.shots.first?.isPenalty, false)
    }

    func testDistanceDigitsDontBecomeWedges() {
        // "260" used to match the "60" alias -> lob wedge
        let r = parse("driver 260 down the middle of the fairway")
        XCTAssertEqual(r.shots.first?.club, .driver)
        XCTAssertEqual(r.shots.first?.distanceYards, 260)
        XCTAssertEqual(r.fairwayHit, true)
    }

    func testDegreeLoftIsClubNotDistance() {
        let r = parse("56 degree 80 yards")
        XCTAssertEqual(r.shots.first?.club, .sw)
        XCTAssertEqual(r.shots.first?.distanceYards, 80)
    }

    func testTrailingPuttsSegmentExpands() {
        let r = parse("driver 250 fairway then 8 iron on the green and 2 putts")
        XCTAssertEqual(r.shots.count, 4)
        XCTAssertEqual(r.putts, 2)
        XCTAssertEqual(r.shots.map(\.club), [.driver, .iron8, .putter, .putter])
    }

    func testResultIsWhereBallEnded() {
        let r = parse("punched out of the trees to the fairway")
        XCTAssertEqual(r.shots.first?.result, .fairway)
    }

    func testWaterIsPenalty() {
        let r = parse("7 iron in the water", par: 3)
        XCTAssertEqual(r.shots.first?.result, .water)
        XCTAssertEqual(r.shots.first?.isPenalty, true)
    }

    func testHyphenatedSpeech() {
        let r = parse("7-iron 150 on the green")
        XCTAssertEqual(r.shots.first?.club, .iron7)
        XCTAssertEqual(r.shots.first?.distanceYards, 150)
    }

    func testGarbageDoesNotInventScores() {
        for junk in ["", "um", "nice weather today", "asdf qwerty"] {
            let r = parse(junk)
            XCTAssertNil(r.totalStrokes, "\"\(junk)\" should not produce a score")
        }
    }
}

final class ConditionsTests: XCTestCase {

    func testHeadwindPlaysLonger() {
        let w = WeatherService()
        w.setManualWind(speedMph: 10, directionDegrees: 0) // wind FROM north
        // shooting due north into it
        XCTAssertGreaterThan(w.adjustedDistance(yards: 150, shotBearing: 0), 150)
        // shooting due south = tailwind
        XCTAssertLessThan(w.adjustedDistance(yards: 150, shotBearing: 180), 150)
    }

    func testHotDayPlaysShorter() {
        let w = WeatherService()
        w.temperature = 105  // Gilbert in July
        XCTAssertLessThan(w.temperatureAdjustment(yards: 150), 150)
        w.temperature = 40
        XCTAssertGreaterThan(w.temperatureAdjustment(yards: 150), 150)
    }

    func testBearingAndDistance() {
        let a = CLLocationCoordinate2D(latitude: 33.3623, longitude: -111.7433)
        let north = CLLocationCoordinate2D(latitude: 33.3623 + 400 * 0.9144 / 111320, longitude: -111.7433)
        XCTAssertLessThanOrEqual(abs(LocationService.distanceYards(from: a, to: north) - 400), 2)
        XCTAssertEqual(LocationService.bearingDegrees(from: a, to: north), 0, accuracy: 1)
    }
}

final class ClubRecommendationTests: XCTestCase {

    func testFirstRoundStillGetsAdvice() {
        // No history at all — the caddy must fall back to standard distances
        let rec = ClubRecommendationService()
        let r = rec.recommend(distanceYards: 150)
        XCTAssertNotNil(r, "a brand-new user must still get club advice")
        XCTAssertEqual(r?.primaryIsFromHistory, false)
    }

    func testRecommendationTargetsPlaysLike() {
        let rec = ClubRecommendationService()
        let r = rec.recommend(distanceYards: 150, playsLikeYards: 165, conditionsNote: "+15y wind")
        // 165 plays-like should pull a longer club than 150 actual
        XCTAssertLessThanOrEqual(abs((r?.primaryAvg ?? 0) - 165), 15)
    }
}

final class ScoringTests: XCTestCase {

    func testPenaltyStrokesCount() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        hole.shots = [
            Shot(shotNumber: 1, club: .driver, result: .water, isPenalty: true),
            Shot(shotNumber: 2, club: .driver, result: .fairway),
            Shot(shotNumber: 3, club: .iron8, result: .green),
            Shot(shotNumber: 4, club: .putter, isPutt: true),
            Shot(shotNumber: 5, club: .putter, result: .holed, isPutt: true),
        ]
        let strokes = hole.shots.count + hole.shots.filter(\.isPenalty).count
        XCTAssertEqual(strokes, 6, "water ball = swing + penalty stroke")
    }

    func testGIRDerivation() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        hole.shots = [
            Shot(shotNumber: 1, club: .driver, result: .fairway),
            Shot(shotNumber: 2, club: .iron7, result: .green),
            Shot(shotNumber: 3, club: .putter, isPutt: true),
            Shot(shotNumber: 4, club: .putter, result: .holed, isPutt: true),
        ]
        hole.strokes = 4
        StatsCalculator.deriveHoleStats(&hole)
        XCTAssertEqual(hole.greenInRegulation, true)
        XCTAssertEqual(hole.fairwayHit, true)
        XCTAssertEqual(hole.putts, 2)
    }

    func testPartialRoundExcludedFromHandicap() {
        let holes = (1...9).map { n -> HoleScore in
            var h = HoleScore(holeNumber: n, par: 4)
            h.strokes = 5
            return h
        }
        let round = Round(courseId: "x", courseName: "Test", teeName: "White", holes: holes)
        round.isComplete = true
        XCTAssertNil(HandicapRound.fromRound(round), "9-hole rounds must not produce an 18-hole differential")
    }
}

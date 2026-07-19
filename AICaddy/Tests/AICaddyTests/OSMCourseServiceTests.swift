import Testing
import Foundation
import CoreLocation
@testable import AICaddy

/// Tests for the OpenStreetMap/Overpass course data path — the service the app
/// actually uses to find courses and load hole GPS data.
@Suite("OSM course service")
struct OSMCourseServiceTests {

    // MARK: - Fixture builders (synthetic Overpass responses)

    private let base = CLLocationCoordinate2D(latitude: 33.5, longitude: -112.0)

    private func overpassJSON(_ elements: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["elements": elements])
    }

    private func geom(_ coords: [CLLocationCoordinate2D]) -> [[String: Any]] {
        coords.map { ["lat": $0.latitude, "lon": $0.longitude] }
    }

    private func holeWay(id: Int, ref: String, par: String? = nil, dist: String? = nil,
                         handicap: String? = nil, geometry: [[String: Any]]) -> [String: Any] {
        var tags: [String: String] = ["golf": "hole", "ref": ref]
        if let par { tags["par"] = par }
        if let dist { tags["dist"] = dist }
        if let handicap { tags["handicap"] = handicap }
        return ["type": "way", "id": id, "tags": tags, "geometry": geometry]
    }

    private func featureWay(id: Int, golf: String, geometry: [[String: Any]]) -> [String: Any] {
        ["type": "way", "id": id, "tags": ["golf": golf], "geometry": geometry]
    }

    /// A simple straight hole: tee at `tee`, green `yards` north of it.
    private func straightHole(id: Int, ref: String, tee: CLLocationCoordinate2D,
                              yards: Double, par: String = "4", dist: String? = nil) -> [String: Any] {
        let green = GeoMath.offsetYards(tee, bearingDegrees: 0, yards: yards)
        return holeWay(id: id, ref: ref, par: par, dist: dist,
                       geometry: geom([tee, green]))
    }

    // MARK: - Course list parsing

    @Test func parsesCourseList() {
        let elements: [[String: Any]] = [
            ["type": "way", "id": 111,
             "tags": ["name": "Papago Golf Course", "addr:city": "Phoenix", "addr:state": "AZ"],
             "center": ["lat": 33.4530, "lon": -111.9528]],
            ["type": "relation", "id": 222,
             "tags": ["name": "Encanto Golf Course"]],
            ["type": "way", "id": 333, "tags": [:]],  // unnamed — dropped
        ]
        let results = OSMCourseService.parseCourseResults(data: overpassJSON(elements))

        #expect(results.count == 2)
        #expect(results[0].id == "way-111")
        #expect(results[0].name == "Papago Golf Course")
        #expect(results[0].city == "Phoenix")
        #expect(results[0].location?.lat == 33.4530)
        #expect(results[1].id == "relation-222")
        #expect(results[1].location == nil)
    }

    @Test("A course mapped as both way and relation appears once")
    func dedupsWayAndRelation() {
        let elements: [[String: Any]] = [
            ["type": "way", "id": 111, "tags": ["name": "Papago Golf Course"],
             "center": ["lat": 33.45, "lon": -111.95]],
            ["type": "relation", "id": 999, "tags": ["name": "Papago Golf Course"]],
        ]
        let results = OSMCourseService.parseCourseResults(data: overpassJSON(elements))
        #expect(results.count == 1)
        #expect(results[0].id == "way-111")  // first occurrence wins
    }

    @Test func malformedCourseData() {
        #expect(OSMCourseService.parseCourseResults(data: Data()).isEmpty)
        #expect(OSMCourseService.parseCourseResults(data: overpassJSON([])).isEmpty)
        let garbage = try! JSONSerialization.data(withJSONObject: ["elements": "nope"])
        #expect(OSMCourseService.parseCourseResults(data: garbage).isEmpty)
    }

    // MARK: - Search regex escaping

    @Test("Regression: punctuation in a course name must not break the Overpass regex")
    func escapesRegexMetacharacters() {
        #expect(OSMCourseService.escapeOverpassRegex("TPC (Stadium)") == #"TPC \(Stadium\)"#)
        #expect(OSMCourseService.escapeOverpassRegex("Papago") == "Papago")
        #expect(OSMCourseService.escapeOverpassRegex("What? Golf*") == #"What\? Golf\*"#)
        #expect(OSMCourseService.escapeOverpassRegex(#"Quote"Club"#) == #"Quote\"Club"#)
        #expect(OSMCourseService.escapeOverpassRegex("A+B [East]") == #"A\+B \[East\]"#)
    }

    // MARK: - Hole parsing

    @Test func parsesBasicHole() {
        let data = overpassJSON([
            straightHole(id: 1, ref: "1", tee: base, yards: 400, par: "4", dist: "365"),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))

        #expect(holes.count == 18)  // normalized to a full course
        let h1 = holes[0]
        #expect(h1.holeNumber == 1)
        #expect(h1.par == 4)
        #expect(h1.yardage == Int(365 * 1.09361))  // dist tag is meters
        #expect(h1.gps?.tee?.lat == base.latitude)
        #expect(h1.gps?.greenCenter != nil)
    }

    @Test("Yardage falls back to the mapped hole-line length when dist is missing")
    func yardageFromGeometry() {
        let data = overpassJSON([
            straightHole(id: 1, ref: "1", tee: base, yards: 412),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))
        let yardage = holes[0].yardage
        #expect(yardage != nil)
        #expect(abs(yardage! - 412) <= 2)
    }

    @Test("Green polygon gives distinct front/back and a centroid center")
    func greenPolygonFrontBack() {
        let greenCenter = GeoMath.offsetYards(base, bearingDegrees: 0, yards: 400)
        // Closed polygon: N/E/S/W vertices, first repeated at the end (OSM style)
        let n = GeoMath.offsetYards(greenCenter, bearingDegrees: 0, yards: 12)
        let e = GeoMath.offsetYards(greenCenter, bearingDegrees: 90, yards: 12)
        let s = GeoMath.offsetYards(greenCenter, bearingDegrees: 180, yards: 12)
        let w = GeoMath.offsetYards(greenCenter, bearingDegrees: 270, yards: 12)

        let data = overpassJSON([
            holeWay(id: 1, ref: "1", par: "4", geometry: geom([base, greenCenter])),
            featureWay(id: 50, golf: "green", geometry: geom([n, e, s, w, n])),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))
        let gps = holes[0].gps

        // Front must be the vertex nearest the tee (south), back the farthest (north)
        let front = gps?.greenFront
        let back = gps?.greenBack
        #expect(front != nil && back != nil)
        #expect(front != back)  // the old first/last-vertex logic made these identical
        let teeToFront = LocationService.distanceYards(from: base, to: front!.coordinate)
        let teeToBack = LocationService.distanceYards(from: base, to: back!.coordinate)
        #expect(teeToFront < teeToBack)
        #expect(teeToBack - teeToFront >= 20)  // ~24y green depth

        // Center is the polygon centroid (closing vertex must not bias it north)
        let centerError = LocationService.distanceYards(from: gps!.greenCenter!.coordinate, to: greenCenter)
        #expect(centerError <= 2)
    }

    @Test("Regression: adjacent course's holes must not duplicate hole numbers")
    func dedupsAdjacentCourseHoles() {
        let farTee = GeoMath.offsetYards(base, bearingDegrees: 90, yards: 1500)
        let data = overpassJSON([
            // The neighbor's hole 1 comes FIRST in the response
            straightHole(id: 99, ref: "1", tee: farTee, yards: 380),
            straightHole(id: 1, ref: "1", tee: base, yards: 400),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))

        let holeOnes = holes.filter { $0.holeNumber == 1 }
        #expect(holeOnes.count == 1)
        // Kept the hole belonging to OUR course (tee at the course center)
        #expect(abs(holeOnes[0].gps!.tee!.lat - base.latitude) < 0.0001)
    }

    @Test("Regression: partially-mapped course fills gaps so every hole is playable")
    func partialMappingNormalized() {
        let data = overpassJSON([
            straightHole(id: 1, ref: "1", tee: base, yards: 400),
            straightHole(id: 3, ref: "3", tee: GeoMath.offsetYards(base, bearingDegrees: 45, yards: 900), yards: 180, par: "3"),
            straightHole(id: 12, ref: "12", tee: GeoMath.offsetYards(base, bearingDegrees: 90, yards: 1200), yards: 520, par: "5"),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))

        // Mapped past hole 9 → treated as an 18-hole course, all holes present
        #expect(holes.count == 18)
        #expect(holes.map(\.holeNumber) == Array(1...18))
        #expect(holes[2].par == 3)          // real mapped hole survives
        #expect(holes[2].gps != nil)
        #expect(holes[1].par == 4)          // gap-filled placeholder
        #expect(holes[1].gps == nil)
        #expect(holes[11].par == 5)
    }

    @Test func nineHoleCourseStaysNine() {
        let elements = (1...7).map { n in
            straightHole(id: n, ref: "\(n)",
                         tee: GeoMath.offsetYards(base, bearingDegrees: Double(n) * 40, yards: Double(n) * 150),
                         yards: 350)
        }
        let holes = OSMCourseService.parseHoleData(data: overpassJSON(elements), courseCenter: GpsPoint(coordinate: base))
        #expect(holes.count == 9)  // don't inflate a 9-hole course to 18
        #expect(holes.map(\.holeNumber) == Array(1...9))
    }

    @Test func hazardsAttachToNearbyHoles() {
        let greenCenter = GeoMath.offsetYards(base, bearingDegrees: 0, yards: 400)
        let nearBunker = GeoMath.offsetYards(greenCenter, bearingDegrees: 90, yards: 30)
        let farBunker = GeoMath.offsetYards(greenCenter, bearingDegrees: 90, yards: 500)
        let penaltyArea = GeoMath.offsetYards(greenCenter, bearingDegrees: 270, yards: 80)

        let data = overpassJSON([
            holeWay(id: 1, ref: "1", par: "4", geometry: geom([base, greenCenter])),
            featureWay(id: 60, golf: "bunker", geometry: geom([nearBunker])),
            featureWay(id: 61, golf: "bunker", geometry: geom([farBunker])),
            // Modern OSM water tagging — the old code only knew *_water_hazard
            featureWay(id: 62, golf: "penalty_area", geometry: geom([penaltyArea])),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))
        let hazards = holes[0].gps?.hazards ?? []

        #expect(hazards.count == 2)  // near bunker + penalty area; far bunker excluded
        #expect(hazards.contains { $0.type == "bunker" })
        #expect(hazards.contains { $0.type == "water" })
    }

    @Test func invalidRefsSkipped() {
        let data = overpassJSON([
            straightHole(id: 1, ref: "A", tee: base, yards: 400),     // non-numeric
            straightHole(id: 2, ref: "0", tee: base, yards: 400),     // out of range
            straightHole(id: 3, ref: "40", tee: base, yards: 400),    // out of range
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))
        #expect(holes.isEmpty)
    }

    @Test func missingParDefaultsToFour() {
        let data = overpassJSON([
            holeWay(id: 1, ref: "1", geometry: geom([base, GeoMath.offsetYards(base, bearingDegrees: 0, yards: 400)])),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))
        #expect(holes[0].par == 4)
    }

    @Test func malformedHoleData() {
        #expect(OSMCourseService.parseHoleData(data: Data(), courseCenter: nil).isEmpty)
        #expect(OSMCourseService.parseHoleData(data: overpassJSON([]), courseCenter: nil).isEmpty)
    }

    // MARK: - Normalization edge cases

    @Test func normalizedEdgeCases() {
        #expect(OSMCourseService.normalized([]).isEmpty)

        // 27-hole complex keeps all 27
        let twentySeven = (1...27).map { CourseHoleData(holeNumber: $0, par: 4) }
        #expect(OSMCourseService.normalized(twentySeven).count == 27)

        // Exactly 18 mapped → unchanged
        let eighteen = (1...18).map { CourseHoleData(holeNumber: $0, par: 4) }
        #expect(OSMCourseService.normalized(eighteen).map(\.holeNumber) == Array(1...18))
    }

    // MARK: - Geometry helpers

    @Test func centroidIgnoresClosingVertex() {
        let a = base
        let b = GeoMath.offsetYards(base, bearingDegrees: 0, yards: 20)
        let c = GeoMath.offsetYards(base, bearingDegrees: 90, yards: 20)
        let way: [String: Any] = ["geometry": geom([a, b, c, a])]  // closed

        let center = OSMCourseService.centroid(of: way)
        #expect(center != nil)
        // Centroid of 3 distinct vertices, not 4 (a must not count twice)
        let expectedLat = (a.latitude + b.latitude + c.latitude) / 3
        #expect(abs(center!.lat - expectedLat) < 1e-9)
    }

    @Test func pathLength() {
        let mid = GeoMath.offsetYards(base, bearingDegrees: 0, yards: 200)
        let end = GeoMath.offsetYards(mid, bearingDegrees: 90, yards: 100)  // dogleg right
        let length = OSMCourseService.pathYards(geom([base, mid, end]))
        #expect(abs(length - 300) <= 2)  // 200 + 100 along the path
        #expect(OSMCourseService.pathYards(geom([base])) == 0)
        #expect(OSMCourseService.pathYards([]) == 0)
    }

    // MARK: - End-to-end: OSM data → playable round

    @Test("Parsed OSM holes produce a playable round (no blank-screen trap)")
    func osmHolesMakePlayableRound() {
        // Sparse, messy OSM data: 3 holes mapped out of 18, one duplicate
        let data = overpassJSON([
            straightHole(id: 1, ref: "1", tee: base, yards: 400),
            straightHole(id: 99, ref: "1", tee: GeoMath.offsetYards(base, bearingDegrees: 90, yards: 1600), yards: 350),
            straightHole(id: 7, ref: "7", tee: GeoMath.offsetYards(base, bearingDegrees: 180, yards: 700), yards: 165, par: "3"),
            straightHole(id: 15, ref: "15", tee: GeoMath.offsetYards(base, bearingDegrees: 270, yards: 900), yards: 540, par: "5"),
        ])
        let holes = OSMCourseService.parseHoleData(data: data, courseCenter: GpsPoint(coordinate: base))
        let tee = CourseTee(name: "Default", holes: holes)

        // The exact flow RoundView.startRound runs:
        let holeScores = tee.holes.map { HoleScore(holeNumber: $0.holeNumber, par: $0.par, yardage: $0.yardage) }
        #expect(!holeScores.isEmpty)
        #expect(holeScores.first?.holeNumber == 1)  // round starts on a hole that EXISTS
        #expect(holeScores.map(\.holeNumber) == Array(1...18))
        #expect(holeScores.reduce(0) { $0 + $1.par } >= 54)
    }
}

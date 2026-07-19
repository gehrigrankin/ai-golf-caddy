import Foundation
import CoreLocation

struct CourseSearchResult: Identifiable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let location: GpsPoint?
}

enum CourseSearchError: LocalizedError {
    case apiError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiError: return "Course search failed"
        case .invalidResponse: return "Invalid response from course API"
        }
    }
}

/// Free course search and hole data via OpenStreetMap Overpass API.
/// No API key needed. Parsing is static/internal so the test suite can drive it
/// with recorded Overpass responses.
final class OSMCourseService {
    private let overpassURL = "https://overpass-api.de/api/interpreter"

    /// Search for golf courses by name
    func searchByName(_ name: String) async throws -> [CourseSearchResult] {
        let escaped = Self.escapeOverpassRegex(name)
        let query = """
        [out:json][timeout:15];
        way["leisure"="golf_course"]["name"~"\(escaped)",i];
        out center tags;
        relation["leisure"="golf_course"]["name"~"\(escaped)",i];
        out center tags;
        """
        let data = try await overpassRequest(query: query)
        return Self.parseCourseResults(data: data)
    }

    /// Search for golf courses near a location
    func searchNearby(lat: Double, lng: Double, radiusMeters: Int = 15000) async throws -> [CourseSearchResult] {
        let query = """
        [out:json][timeout:15];
        (
          way["leisure"="golf_course"](around:\(radiusMeters),\(lat),\(lng));
          relation["leisure"="golf_course"](around:\(radiusMeters),\(lat),\(lng));
        );
        out center tags;
        """
        let data = try await overpassRequest(query: query)
        return Self.parseCourseResults(data: data)
    }

    /// Fetch full hole details for a course (par, yardage, GPS for tees/greens/bunkers/water)
    func fetchCourseHoles(courseName: String, lat: Double, lng: Double) async throws -> [CourseHoleData] {
        // Get all golf features within 2km of the course center.
        // "penalty_area" is the modern OSM tag for water (post-2019 rules);
        // the *_water_hazard tags are the older scheme — ask for all of them.
        let query = """
        [out:json][timeout:25];
        (
          way["golf"="hole"](around:2000,\(lat),\(lng));
          way["golf"="tee"](around:2000,\(lat),\(lng));
          way["golf"="green"](around:2000,\(lat),\(lng));
          way["golf"="bunker"](around:2000,\(lat),\(lng));
          way["golf"="water_hazard"](around:2000,\(lat),\(lng));
          way["golf"="lateral_water_hazard"](around:2000,\(lat),\(lng));
          way["golf"="penalty_area"](around:2000,\(lat),\(lng));
        );
        out body geom;
        """
        let data = try await overpassRequest(query: query)
        return Self.parseHoleData(data: data, courseCenter: GpsPoint(lat: lat, lng: lng))
    }

    // MARK: - Parsing (static + internal for tests)

    static func parseCourseResults(data: Data) -> [CourseSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }

        var seenNames = Set<String>()
        var results: [CourseSearchResult] = []

        for elem in elements {
            let tags = elem["tags"] as? [String: String] ?? [:]
            guard let name = tags["name"] else { continue }

            // A course mapped as both a way and a relation comes back twice —
            // keep the first occurrence.
            let nameKey = name.lowercased()
            guard !seenNames.contains(nameKey) else { continue }
            seenNames.insert(nameKey)

            // Way and relation IDs are separate OSM namespaces — prefix the
            // type so "way 123" can't collide with "relation 123".
            let type = (elem["type"] as? String) ?? "elem"
            let id = "\(type)-\(elem["id"] ?? 0)"

            var location: GpsPoint?
            if let center = elem["center"] as? [String: Any],
               let lat = center["lat"] as? Double,
               let lng = center["lon"] as? Double {
                location = GpsPoint(lat: lat, lng: lng)
            }

            results.append(CourseSearchResult(
                id: id,
                name: name,
                city: tags["addr:city"],
                state: tags["addr:state"],
                location: location
            ))
        }

        return results
    }

    static func parseHoleData(data: Data, courseCenter: GpsPoint?) -> [CourseHoleData] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }

        // Separate elements by type
        var holeWays: [[String: Any]] = []
        var greenWays: [[String: Any]] = []
        var bunkerWays: [[String: Any]] = []
        var waterWays: [[String: Any]] = []

        for elem in elements {
            let tags = elem["tags"] as? [String: String] ?? [:]
            switch tags["golf"] ?? "" {
            case "hole": holeWays.append(elem)
            case "green": greenWays.append(elem)
            case "bunker": bunkerWays.append(elem)
            case "water_hazard", "lateral_water_hazard", "penalty_area": waterWays.append(elem)
            default: break
            }
        }

        // The 2km radius can catch holes from an ADJACENT course (TPC Stadium
        // and Champions are neighbors) — that produces duplicate hole numbers,
        // which breaks round navigation. Deduplicate by keeping the candidate
        // nearest the course center.
        var byNumber: [Int: (hole: CourseHoleData, refPoint: GpsPoint?)] = [:]

        for holeWay in holeWays {
            let tags = holeWay["tags"] as? [String: String] ?? [:]
            guard let refStr = tags["ref"], let holeNumber = Int(refStr),
                  (1...36).contains(holeNumber) else { continue }

            let par = Int(tags["par"] ?? "") ?? 4
            let geometry = holeWay["geometry"] as? [[String: Any]] ?? []

            // Yardage: the dist tag when present (meters), else the actual
            // length of the mapped hole line — most OSM holes lack dist.
            var yardage: Int?
            if let distStr = tags["dist"] ?? tags["distance"], let meters = Double(distStr) {
                yardage = Int(meters * 1.09361)
            } else {
                let pathLength = pathYards(geometry)
                if pathLength > 50 { yardage = Int(pathLength) }
            }

            let handicapIndex = Int(tags["handicap"] ?? "")

            // Tee = first point of the hole way, green = last point
            var gps = HoleGps()
            let points = vertices(geometry)
            gps.tee = points.first
            gps.greenCenter = points.last

            // Match the green polygon for a better center + true front/back.
            // OSM greens are closed polygons, so "first/last vertex" are the
            // SAME point — front/back must come from nearest/farthest vertex.
            if let greenWay = nearestFeature(greenWays, to: gps.greenCenter, withinYards: 100),
               let greenCentroid = centroid(of: greenWay) {
                gps.greenCenter = greenCentroid
                if let tee = gps.tee {
                    let greenPts = vertices(greenWay["geometry"] as? [[String: Any]] ?? [])
                    gps.greenFront = greenPts.min { distanceYards($0, tee) < distanceYards($1, tee) }
                    gps.greenBack = greenPts.max { distanceYards($0, tee) < distanceYards($1, tee) }
                }
            }

            // Nearby hazards
            var hazards: [HoleHazard] = []
            if let holeCenter = gps.greenCenter ?? gps.tee {
                for bunkerWay in bunkerWays {
                    if let center = centroid(of: bunkerWay),
                       distanceYards(center, holeCenter) < 200 {
                        hazards.append(HoleHazard(type: "bunker", position: center, label: "Bunker"))
                    }
                }
                for waterWay in waterWays {
                    if let center = centroid(of: waterWay),
                       distanceYards(center, holeCenter) < 300 {
                        hazards.append(HoleHazard(type: "water", position: center, label: "Water"))
                    }
                }
            }
            if !hazards.isEmpty { gps.hazards = hazards }

            let hasGps = gps.tee != nil || gps.greenCenter != nil
            let candidate = CourseHoleData(
                holeNumber: holeNumber,
                par: par,
                yardage: yardage,
                handicapIndex: handicapIndex,
                gps: hasGps ? gps : nil
            )
            let refPoint = gps.tee ?? gps.greenCenter

            if let existing = byNumber[holeNumber] {
                if let cc = courseCenter, let newRef = refPoint, let oldRef = existing.refPoint,
                   distanceYards(newRef, cc) < distanceYards(oldRef, cc) {
                    byNumber[holeNumber] = (candidate, refPoint)
                }
                // otherwise keep the existing (nearer or equally unknown) hole
            } else {
                byNumber[holeNumber] = (candidate, refPoint)
            }
        }

        let holes = byNumber.values.map(\.hole).sorted { $0.holeNumber < $1.holeNumber }
        return normalized(holes)
    }

    /// Fill gaps in partially-mapped courses. OSM data is community-sourced —
    /// a course may have only holes 3, 7 and 12 mapped. A round that starts on
    /// a hole that doesn't exist renders a blank screen, so fill missing holes
    /// with par-4 placeholders.
    ///
    /// Hole count: only treat the course as 9 holes when the mapping actually
    /// looks like a well-mapped nine (5+ holes, none past 9). Sparse data
    /// defaults to 18 — capping a real 18-hole course at 9 makes the back nine
    /// unscoreable, while extra holes on a true 9-hole course are just skipped.
    static func normalized(_ holes: [CourseHoleData]) -> [CourseHoleData] {
        guard let maxNumber = holes.map(\.holeNumber).max() else { return [] }
        let looksLikeNine = maxNumber <= 9 && holes.count >= 5
        let target = looksLikeNine ? 9 : max(maxNumber, 18)

        var byNumber: [Int: CourseHoleData] = [:]
        for hole in holes { byNumber[hole.holeNumber] = hole }

        return (1...target).map { n in
            byNumber[n] ?? CourseHoleData(holeNumber: n, par: 4)
        }
    }

    /// Escape user input for use inside an Overpass QL regex match (~"...").
    /// Without this, searching for "TPC (Stadium)" produces an invalid regex
    /// and the whole query 400s.
    static func escapeOverpassRegex(_ str: String) -> String {
        var out = ""
        for ch in str {
            if #"\^$.|?*+()[]{}""#.contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    // MARK: - Geometry helpers

    static func vertices(_ geometry: [[String: Any]]) -> [GpsPoint] {
        geometry.compactMap { point in
            guard let lat = point["lat"] as? Double, let lng = point["lon"] as? Double else { return nil }
            return GpsPoint(lat: lat, lng: lng)
        }
    }

    /// Length of a way's polyline in yards (used as the yardage fallback).
    static func pathYards(_ geometry: [[String: Any]]) -> Double {
        let points = vertices(geometry)
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].lat, longitude: points[i - 1].lng)
            let b = CLLocation(latitude: points[i].lat, longitude: points[i].lng)
            total += a.distance(from: b)
        }
        return total / 0.9144
    }

    static func centroid(of way: [String: Any]) -> GpsPoint? {
        var points = vertices(way["geometry"] as? [[String: Any]] ?? [])
        guard !points.isEmpty else { return nil }
        // Closed polygons repeat the first vertex at the end — drop the
        // duplicate so it doesn't bias the centroid.
        if points.count > 1, points.first == points.last {
            points.removeLast()
        }
        let lat = points.reduce(0.0) { $0 + $1.lat } / Double(points.count)
        let lng = points.reduce(0.0) { $0 + $1.lng } / Double(points.count)
        return GpsPoint(lat: lat, lng: lng)
    }

    static func nearestFeature(_ features: [[String: Any]], to point: GpsPoint?, withinYards limit: Int) -> [String: Any]? {
        guard let point else { return nil }
        var nearest: [String: Any]?
        var nearestDist = Int.max

        for feature in features {
            if let center = centroid(of: feature) {
                let dist = distanceYards(center, point)
                if dist < nearestDist {
                    nearestDist = dist
                    nearest = feature
                }
            }
        }
        return nearestDist < limit ? nearest : nil
    }

    private static func distanceYards(_ a: GpsPoint, _ b: GpsPoint) -> Int {
        LocationService.distanceYards(from: a.coordinate, to: b.coordinate)
    }

    // MARK: - Network

    private func overpassRequest(query: String) async throws -> Data {
        var request = URLRequest(url: URL(string: overpassURL)!)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CourseSearchError.apiError
        }
        return data
    }
}

import Foundation
import CoreLocation

struct CourseSearchResult: Identifiable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let location: GpsPoint?
}

enum CourseSearchError: Error {
    case apiError
}

/// Free course search and hole data via OpenStreetMap Overpass API.
/// No API key needed.
final class OSMCourseService {
    private let overpassURL = "https://overpass-api.de/api/interpreter"

    /// Search for golf courses by name
    func searchByName(_ name: String) async throws -> [CourseSearchResult] {
        let query = """
        [out:json][timeout:15];
        way["leisure"="golf_course"]["name"~"\(escapeOverpass(name))",i];
        out center tags;
        relation["leisure"="golf_course"]["name"~"\(escapeOverpass(name))",i];
        out center tags;
        """
        let data = try await overpassRequest(query: query)
        return parseCourseResults(data: data)
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
        return parseCourseResults(data: data)
    }

    /// Fetch full hole details for a course (par, yardage, GPS for tees/greens/bunkers/water)
    func fetchCourseHoles(courseName: String, lat: Double, lng: Double) async throws -> [CourseHoleData] {
        // Get all golf features within 2km of the course center
        let query = """
        [out:json][timeout:25];
        (
          way["golf"="hole"](around:2000,\(lat),\(lng));
          way["golf"="tee"](around:2000,\(lat),\(lng));
          way["golf"="green"](around:2000,\(lat),\(lng));
          way["golf"="bunker"](around:2000,\(lat),\(lng));
          way["golf"="water_hazard"](around:2000,\(lat),\(lng));
          way["golf"="lateral_water_hazard"](around:2000,\(lat),\(lng));
        );
        out body geom;
        """
        let data = try await overpassRequest(query: query)
        return parseHoleData(data: data, courseLat: lat, courseLng: lng)
    }

    // MARK: - Parsing

    private func parseCourseResults(data: Data) -> [CourseSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }

        return elements.compactMap { elem in
            let tags = elem["tags"] as? [String: String] ?? [:]
            guard let name = tags["name"] else { return nil }

            let id = "\(elem["id"] ?? 0)"

            // Get center coordinates
            var lat: Double?
            var lng: Double?
            if let center = elem["center"] as? [String: Any] {
                lat = center["lat"] as? Double
                lng = center["lon"] as? Double
            }

            let city = tags["addr:city"]
            let state = tags["addr:state"]

            return CourseSearchResult(
                id: id,
                name: name,
                city: city,
                state: state,
                location: (lat != nil && lng != nil) ? GpsPoint(lat: lat!, lng: lng!) : nil
            )
        }
    }

    private func parseHoleData(data: Data, courseLat: Double, courseLng: Double) -> [CourseHoleData] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }
        let courseCenter = CLLocationCoordinate2D(latitude: courseLat, longitude: courseLng)

        // Separate elements by type
        var holeWays: [[String: Any]] = []
        var teeWays: [[String: Any]] = []
        var greenWays: [[String: Any]] = []
        var bunkerWays: [[String: Any]] = []
        var waterWays: [[String: Any]] = []

        for elem in elements {
            let tags = elem["tags"] as? [String: String] ?? [:]
            let golf = tags["golf"] ?? ""

            switch golf {
            case "hole": holeWays.append(elem)
            case "tee": teeWays.append(elem)
            case "green": greenWays.append(elem)
            case "bunker": bunkerWays.append(elem)
            case "water_hazard", "lateral_water_hazard": waterWays.append(elem)
            default: break
            }
        }

        // Neighboring courses sit within the search radius in dense golf areas
        // (metro Phoenix especially), so several ways can claim the same hole ref.
        // Keep the candidate nearest to the course center for each hole number.
        var bestHoleWay: [Int: (way: [String: Any], dist: Int)] = [:]
        for holeWay in holeWays {
            let tags = holeWay["tags"] as? [String: String] ?? [:]
            guard let refStr = tags["ref"],
                  let holeNumber = Int(refStr.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)),
                  (1...18).contains(holeNumber) else { continue }
            guard let center = centroid(of: holeWay) else { continue }
            let dist = LocationService.distanceYards(from: courseCenter, to: center.coordinate)
            if let existing = bestHoleWay[holeNumber], existing.dist <= dist { continue }
            bestHoleWay[holeNumber] = (holeWay, dist)
        }

        // Parse holes
        var holes: [CourseHoleData] = []

        for (holeNumber, entry) in bestHoleWay {
            let holeWay = entry.way
            let tags = holeWay["tags"] as? [String: String] ?? [:]
            let geometry = holeWay["geometry"] as? [[String: Any]] ?? []

            let par = Int(tags["par"] ?? "") ?? 4
            var yardage: Int?
            if let distStr = tags["dist"] ?? tags["distance"] {
                // OSM stores distance in meters typically
                if let meters = Double(distStr) {
                    yardage = Int(meters * 1.09361)  // meters to yards
                }
            }

            let handicapIndex = Int(tags["handicap"] ?? "")

            // The golf=hole way runs tee → green (possibly with dogleg points)
            var gps = HoleGps()
            let points: [GpsPoint] = geometry.compactMap { pt in
                guard let lat = pt["lat"] as? Double, let lng = pt["lon"] as? Double else { return nil }
                return GpsPoint(lat: lat, lng: lng)
            }

            gps.tee = points.first
            gps.greenCenter = points.last
            if points.count > 2 {
                gps.fairwayCenter = points[points.count / 2]
            }

            // No dist tag? Measure the hole way itself (follows the dogleg,
            // unlike straight tee→green distance).
            if yardage == nil, points.count >= 2 {
                var total = 0
                for i in 1..<points.count {
                    total += LocationService.distanceYards(from: points[i-1].coordinate, to: points[i].coordinate)
                }
                if total > 50 { yardage = total }
            }

            // Front/back of green from the green polygon: OSM greens are closed
            // rings (first vertex == last), so take the vertices nearest to and
            // farthest from the tee instead of first/last.
            if let greenWay = findNearestFeature(greenWays, to: gps.greenCenter),
               let tee = gps.tee {
                let greenGeom = greenWay["geometry"] as? [[String: Any]] ?? []
                let vertices: [GpsPoint] = greenGeom.compactMap { pt in
                    guard let lat = pt["lat"] as? Double, let lng = pt["lon"] as? Double else { return nil }
                    return GpsPoint(lat: lat, lng: lng)
                }
                if vertices.count >= 3 {
                    let byDist = vertices.map { v in
                        (point: v, dist: LocationService.distanceYards(from: tee.coordinate, to: v.coordinate))
                    }
                    gps.greenFront = byDist.min(by: { $0.dist < $1.dist })?.point
                    gps.greenBack = byDist.max(by: { $0.dist < $1.dist })?.point
                    // The polygon centroid is a better pin proxy than the way's last point
                    if let center = centroid(of: greenWay) {
                        gps.greenCenter = center
                    }
                }
            }

            // Find nearby bunkers
            var hazards: [HoleHazard] = []
            let holeCenter = gps.greenCenter ?? gps.tee

            for bunkerWay in bunkerWays {
                if let center = centroid(of: bunkerWay), let hc = holeCenter {
                    let dist = LocationService.distanceYards(from: hc.coordinate, to: center.coordinate)
                    if dist < 200 {
                        hazards.append(HoleHazard(type: "bunker", position: center, label: "Bunker"))
                    }
                }
            }

            for waterWay in waterWays {
                if let center = centroid(of: waterWay), let hc = holeCenter {
                    let dist = LocationService.distanceYards(from: hc.coordinate, to: center.coordinate)
                    if dist < 300 {
                        hazards.append(HoleHazard(type: "water", position: center, label: "Water"))
                    }
                }
            }

            if !hazards.isEmpty { gps.hazards = hazards }

            let hasGps = gps.tee != nil || gps.greenCenter != nil
            holes.append(CourseHoleData(
                holeNumber: holeNumber,
                par: par,
                yardage: yardage,
                handicapIndex: handicapIndex,
                gps: hasGps ? gps : nil
            ))
        }

        return holes.sorted { $0.holeNumber < $1.holeNumber }
    }

    // MARK: - Helpers

    private func centroid(of way: [String: Any]) -> GpsPoint? {
        let geometry = way["geometry"] as? [[String: Any]] ?? []
        guard !geometry.isEmpty else { return nil }

        var totalLat = 0.0, totalLng = 0.0
        for point in geometry {
            totalLat += point["lat"] as? Double ?? 0
            totalLng += point["lon"] as? Double ?? 0
        }
        return GpsPoint(lat: totalLat / Double(geometry.count), lng: totalLng / Double(geometry.count))
    }

    private func findNearestFeature(_ features: [[String: Any]], to point: GpsPoint?) -> [String: Any]? {
        guard let point else { return nil }
        var nearest: [String: Any]?
        var nearestDist = Int.max

        for feature in features {
            if let center = centroid(of: feature) {
                let dist = LocationService.distanceYards(from: point.coordinate, to: center.coordinate)
                if dist < nearestDist {
                    nearestDist = dist
                    nearest = feature
                }
            }
        }
        return nearestDist < 100 ? nearest : nil  // only match within 100 yards
    }

    private func overpassRequest(query: String) async throws -> Data {
        var request = URLRequest(url: URL(string: overpassURL)!)
        request.httpMethod = "POST"
        // Percent-encode: course names with &, +, or quotes would corrupt a raw body
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        request.httpBody = "data=\(encoded)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CourseSearchError.apiError
        }
        return data
    }

    private func escapeOverpass(_ str: String) -> String {
        str.replacingOccurrences(of: "\"", with: "\\\"")
           .replacingOccurrences(of: "'", with: "\\'")
    }
}

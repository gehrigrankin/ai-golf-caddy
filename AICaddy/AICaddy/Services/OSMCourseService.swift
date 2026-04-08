import Foundation
import CoreLocation

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
        return parseHoleData(data: data)
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

    private func parseHoleData(data: Data) -> [CourseHoleData] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return [] }

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

        // Parse holes
        var holes: [CourseHoleData] = []

        for holeWay in holeWays {
            let tags = holeWay["tags"] as? [String: String] ?? [:]
            let geometry = holeWay["geometry"] as? [[String: Any]] ?? []

            guard let refStr = tags["ref"], let holeNumber = Int(refStr) else { continue }

            let par = Int(tags["par"] ?? "") ?? 4
            let yardage: Int?
            if let distStr = tags["dist"] ?? tags["distance"] {
                // OSM stores distance in meters typically
                if let meters = Double(distStr) {
                    yardage = Int(meters * 1.09361)  // meters to yards
                } else {
                    yardage = nil
                }
            } else {
                yardage = nil
            }
            let handicapIndex = Int(tags["handicap"] ?? "")

            // Extract tee (first point of hole way) and green center (last point)
            var gps = HoleGps()

            if let first = geometry.first,
               let lat = first["lat"] as? Double, let lng = first["lon"] as? Double {
                gps.tee = GpsPoint(lat: lat, lng: lng)
            }

            if let last = geometry.last,
               let lat = last["lat"] as? Double, let lng = last["lon"] as? Double {
                gps.greenCenter = GpsPoint(lat: lat, lng: lng)
            }

            // Find matching green way for front/back of green
            if let greenWay = findNearestFeature(greenWays, to: gps.greenCenter) {
                let greenGeom = greenWay["geometry"] as? [[String: Any]] ?? []
                if let greenFirst = greenGeom.first, let greenLast = greenGeom.last {
                    let frontLat = greenFirst["lat"] as? Double ?? 0
                    let frontLng = greenFirst["lon"] as? Double ?? 0
                    let backLat = greenLast["lat"] as? Double ?? 0
                    let backLng = greenLast["lon"] as? Double ?? 0

                    // Determine which is front/back based on distance to tee
                    if let tee = gps.tee {
                        let distToFirst = LocationService.distanceYards(
                            from: tee.coordinate,
                            to: CLLocationCoordinate2D(latitude: frontLat, longitude: frontLng)
                        )
                        let distToLast = LocationService.distanceYards(
                            from: tee.coordinate,
                            to: CLLocationCoordinate2D(latitude: backLat, longitude: backLng)
                        )
                        if distToFirst < distToLast {
                            gps.greenFront = GpsPoint(lat: frontLat, lng: frontLng)
                            gps.greenBack = GpsPoint(lat: backLat, lng: backLng)
                        } else {
                            gps.greenFront = GpsPoint(lat: backLat, lng: backLng)
                            gps.greenBack = GpsPoint(lat: frontLat, lng: frontLng)
                        }
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
        request.httpBody = "data=\(query)".data(using: .utf8)
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

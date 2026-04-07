import Foundation
import CoreLocation

struct CourseSearchResult: Identifiable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let location: GpsPoint?
}

/// Searches for golf courses via the Golfbert API (RapidAPI)
final class CourseSearchService {
    private let apiKey: String?
    private let host = "golfbert.p.rapidapi.com"

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.object(forInfoDictionaryKey: "GOLFBERT_API_KEY") as? String
    }

    var isConfigured: Bool { apiKey != nil && !apiKey!.isEmpty }

    func searchByName(_ name: String) async throws -> [CourseSearchResult] {
        guard let apiKey else { throw CourseSearchError.notConfigured }
        let url = URL(string: "https://\(host)/courses?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")!
        return try await fetchCourses(url: url, apiKey: apiKey)
    }

    func searchNearby(lat: Double, lng: Double, radius: Int = 30) async throws -> [CourseSearchResult] {
        guard let apiKey else { throw CourseSearchError.notConfigured }
        let url = URL(string: "https://\(host)/courses?lat=\(lat)&lng=\(lng)&radius=\(radius)")!
        return try await fetchCourses(url: url, apiKey: apiKey)
    }

    func fetchCourseDetails(id: String) async throws -> (tees: [CourseTee], name: String, city: String?, state: String?, location: GpsPoint?) {
        guard let apiKey else { throw CourseSearchError.notConfigured }

        // Fetch course info and holes in parallel
        async let courseData = golfbertFetch("/courses/\(id)", apiKey: apiKey)
        async let holesData = golfbertFetch("/courses/\(id)/holes", apiKey: apiKey)

        let course = try await courseData
        let holesResponse = try await holesData

        let holesArray = (holesResponse["holes"] as? [[String: Any]]) ?? []

        // Fetch GPS data for each hole
        var holeDataList: [CourseHoleData] = []
        for hole in holesArray {
            let holeId = hole["id"]
            let holeNumber = (hole["number"] as? Int) ?? (hole["hole_number"] as? Int) ?? 0
            let par = (hole["par"] as? Int) ?? 4
            let yardage = (hole["yards"] as? Int) ?? (hole["yardage"] as? Int)

            var gps: HoleGps?
            if let hId = holeId {
                gps = try? await fetchHoleGps(holeId: "\(hId)", apiKey: apiKey)
            }

            holeDataList.append(CourseHoleData(
                holeNumber: holeNumber, par: par, yardage: yardage, gps: gps
            ))
        }

        holeDataList.sort { $0.holeNumber < $1.holeNumber }

        // Build tees
        let teesArray = (course["teeboxes"] as? [[String: Any]]) ?? (course["tees"] as? [[String: Any]]) ?? []
        var tees: [CourseTee] = teesArray.map { t in
            CourseTee(
                name: (t["name"] as? String) ?? "Default",
                rating: t["rating"] as? Double,
                slope: t["slope"] as? Int,
                holes: holeDataList
            )
        }
        if tees.isEmpty {
            tees = [CourseTee(name: "Default", holes: holeDataList)]
        }

        let name = (course["name"] as? String) ?? "Unknown"
        let city = course["city"] as? String
        let state = (course["state"] as? String) ?? (course["region"] as? String)
        let location: GpsPoint?
        if let lat = course["latitude"] as? Double, let lng = course["longitude"] as? Double {
            location = GpsPoint(lat: lat, lng: lng)
        } else {
            location = nil
        }

        return (tees, name, city, state, location)
    }

    // MARK: - Private

    private func fetchCourses(url: URL, apiKey: String) async throws -> [CourseSearchResult] {
        let data = try await golfbertRequest(url: url, apiKey: apiKey)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let courses = (json?["courses"] as? [[String: Any]]) ?? []

        return courses.compactMap { c in
            guard let id = c["id"] else { return nil }
            let location: GpsPoint?
            if let lat = c["latitude"] as? Double, let lng = c["longitude"] as? Double {
                location = GpsPoint(lat: lat, lng: lng)
            } else {
                location = nil
            }
            return CourseSearchResult(
                id: "\(id)",
                name: (c["name"] as? String) ?? "Unknown",
                city: c["city"] as? String,
                state: (c["state"] as? String) ?? (c["region"] as? String),
                location: location
            )
        }
    }

    private func fetchHoleGps(holeId: String, apiKey: String) async throws -> HoleGps? {
        let data = try await golfbertFetch("/holes/\(holeId)/gpsdata", apiKey: apiKey)
        let points = (data["gps_points"] as? [[String: Any]]) ?? []

        var gps = HoleGps()
        var hazards: [HoleHazard] = []

        for point in points {
            guard let lat = (point["latitude"] as? Double) ?? (point["lat"] as? Double),
                  let lng = (point["longitude"] as? Double) ?? (point["lng"] as? Double)
            else { continue }

            let coord = GpsPoint(lat: lat, lng: lng)
            let type = ((point["type"] as? String) ?? (point["label"] as? String) ?? "").lowercased()

            if type.contains("tee") { gps.tee = coord }
            else if type.contains("green") && type.contains("center") { gps.greenCenter = coord }
            else if type.contains("green") && type.contains("front") { gps.greenFront = coord }
            else if type.contains("green") && type.contains("back") { gps.greenBack = coord }
            else if type.contains("fairway") || type.contains("dogleg") { gps.fairwayCenter = coord }
            else if type.contains("bunker") || type.contains("sand") {
                hazards.append(HoleHazard(type: "bunker", position: coord, label: point["label"] as? String))
            } else if type.contains("water") || type.contains("hazard") || type.contains("lake") {
                hazards.append(HoleHazard(type: "water", position: coord, label: point["label"] as? String))
            }
        }

        if !hazards.isEmpty { gps.hazards = hazards }

        let hasData = gps.tee != nil || gps.greenCenter != nil
        return hasData ? gps : nil
    }

    private func golfbertFetch(_ path: String, apiKey: String) async throws -> [String: Any] {
        let url = URL(string: "https://\(host)\(path)")!
        let data = try await golfbertRequest(url: url, apiKey: apiKey)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CourseSearchError.invalidResponse
        }
        return json
    }

    private func golfbertRequest(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(host, forHTTPHeaderField: "x-rapidapi-host")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CourseSearchError.apiError
        }
        return data
    }
}

enum CourseSearchError: LocalizedError {
    case notConfigured
    case apiError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Golf course API not configured"
        case .apiError: return "Course search failed"
        case .invalidResponse: return "Invalid response from course API"
        }
    }
}

import Foundation
import SwiftData

/// Stores loaded course GPS data locally for offline use on the course
@Observable
final class OfflineCacheService {
    var cachedCourses: [String] = []  // course IDs
    var error: String?

    private let cacheDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDir = docs.appendingPathComponent("CourseCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadCachedList()
    }

    /// Save an already-loaded course (e.g. from OSM search) for offline use.
    func cache(course: Course) {
        let cacheData = CachedCourse(
            id: course.id,
            name: course.name,
            city: course.city,
            state: course.state,
            location: course.location,
            tees: course.tees,
            downloadedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(cacheData)
            let fileURL = cacheDir.appendingPathComponent("\(course.id).json")
            try data.write(to: fileURL)
            if !cachedCourses.contains(course.id) {
                cachedCourses.append(course.id)
            }
            saveCachedList()
            error = nil
        } catch {
            self.error = "Caching failed: \(error.localizedDescription)"
        }
    }

    /// Load cached course data (works offline)
    func loadCachedCourse(id: String) -> CachedCourse? {
        let fileURL = cacheDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedCourse.self, from: data)
    }

    /// Delete cached course
    func deleteCachedCourse(id: String) {
        let fileURL = cacheDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: fileURL)
        cachedCourses.removeAll { $0 == id }
        saveCachedList()
    }

    /// List all cached courses with their metadata
    func listCachedCourses() -> [CachedCourse] {
        cachedCourses.compactMap { loadCachedCourse(id: $0) }
    }

    private func loadCachedList() {
        let listURL = cacheDir.appendingPathComponent("cached_ids.json")
        if let data = try? Data(contentsOf: listURL),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            cachedCourses = ids
        }
    }

    private func saveCachedList() {
        let listURL = cacheDir.appendingPathComponent("cached_ids.json")
        if let data = try? JSONEncoder().encode(cachedCourses) {
            try? data.write(to: listURL)
        }
    }
}

struct CachedCourse: Codable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let location: GpsPoint?
    let tees: [CourseTee]
    let downloadedAt: Date
}

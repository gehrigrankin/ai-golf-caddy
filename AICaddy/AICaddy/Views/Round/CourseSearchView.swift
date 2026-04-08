import SwiftUI
import CoreLocation

struct CourseSearchView: View {
    let courseSearch: CourseSearchService
    let locationService: LocationService
    let onCourseLoaded: (Course) -> Void
    let onSkip: () -> Void

    private let osmService = OSMCourseService()

    @State private var query = ""
    @State private var results: [CourseSearchResult] = []
    @State private var searching = false
    @State private var loadingId: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Find Your Course")
                    .font(.title3.bold())
                Text("Search to auto-load hole data and GPS maps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Search by name
            HStack(spacing: 8) {
                TextField("Course name...", text: $query)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.search)
                    .onSubmit { searchByName() }

                Button { searchByName() } label: {
                    Text(searching ? "..." : "Search")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Search nearby
            Button {
                searchNearby()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text(searching ? "Finding courses..." : "Find courses near me")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(searching)

            // Results
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(results.count) course\(results.count == 1 ? "" : "s") found")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(results) { result in
                        Button {
                            loadCourse(result)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.subheadline.bold())
                                    if let city = result.city, let state = result.state {
                                        Text("\(city), \(state)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if loadingId == result.id {
                                    ProgressView().tint(.green)
                                }
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(loadingId != nil)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("Set up course manually") {
                onSkip()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func searchByName() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        error = nil
        results = []

        Task {
            do {
                let found = try await osmService.searchByName(query)
                await MainActor.run {
                    results = found
                    if found.isEmpty { error = "No courses found. Try a different name." }
                    searching = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Search failed. Check your connection."
                    searching = false
                }
            }
        }
    }

    private func searchNearby() {
        searching = true
        error = nil
        results = []

        guard let loc = locationService.location else {
            locationService.requestPermission()
            error = "Enable location access to search nearby."
            searching = false
            return
        }

        Task {
            do {
                let found = try await osmService.searchNearby(lat: loc.latitude, lng: loc.longitude)
                await MainActor.run {
                    results = found
                    if found.isEmpty { error = "No courses found nearby." }
                    searching = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Search failed. Check your connection."
                    searching = false
                }
            }
        }
    }

    private func loadCourse(_ result: CourseSearchResult) {
        guard let location = result.location else {
            // No GPS for this course — just create a shell course
            let course = Course(id: result.id, name: result.name, city: result.city, state: result.state)
            onCourseLoaded(course)
            return
        }

        loadingId = result.id
        error = nil

        Task {
            do {
                let holes = try await osmService.fetchCourseHoles(
                    courseName: result.name,
                    lat: location.lat,
                    lng: location.lng
                )
                let tee = CourseTee(name: "Default", holes: holes.isEmpty ? defaultHoles() : holes)
                let course = Course(
                    id: result.id,
                    name: result.name,
                    city: result.city,
                    state: result.state,
                    location: location,
                    tees: [tee]
                )
                await MainActor.run {
                    loadingId = nil
                    onCourseLoaded(course)
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load hole data. Try manual setup."
                    loadingId = nil
                }
            }
        }
    }

    private func defaultHoles() -> [CourseHoleData] {
        let defaultPars = [4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5]
        return defaultPars.enumerated().map { i, par in
            CourseHoleData(holeNumber: i + 1, par: par)
        }
    }
}

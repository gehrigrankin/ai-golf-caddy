import SwiftUI
import SwiftData

@main
struct AICaddyApp: App {
    @State private var locationService = LocationService()
    @State private var speechService = SpeechService()

    private let shotParser = ShotParserService()
    private let courseSearch = CourseSearchService()

    var body: some Scene {
        WindowGroup {
            HomeView(
                locationService: locationService,
                speechService: speechService,
                shotParser: shotParser,
                courseSearch: courseSearch
            )
            .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Course.self, Round.self])
    }
}

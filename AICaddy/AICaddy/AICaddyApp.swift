import SwiftUI
import SwiftData

@main
struct AICaddyApp: App {
    @State private var locationService = LocationService()
    @State private var speechService = SpeechService()
    @State private var clubRecommender = ClubRecommendationService()

    private let shotParser = ShotParserService()

    var body: some Scene {
        WindowGroup {
            HomeView(
                locationService: locationService,
                speechService: speechService,
                shotParser: shotParser,
                clubRecommender: clubRecommender
            )
            .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Course.self, Round.self, GolfBag.self, EquipmentLog.self])
    }
}

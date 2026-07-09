import SwiftUI

struct SettingsView: View {
    @AppStorage("autoAdvanceEnabled") private var autoAdvanceEnabled = true
    @AppStorage("showWind") private var showWind = true

    var body: some View {
        List {
            Section("On the Course") {
                Toggle(isOn: $autoAdvanceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-advance holes")
                        Text("Suggest the next hole when you walk to its tee box")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showWind) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wind & plays-like distances")
                        Text("Adjust yardages for wind and temperature. Tap the wind chip on a hole to set wind manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Voice Input") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Works offline")
                        .font(.subheadline)
                    Text("Speech recognition runs on-device when your iPhone supports it, so voice scoring works with no cell signal. Say things like \"driver 250 fairway\", \"par\", or \"2 putts\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("About") {
                LabeledContent("Course data", value: "OpenStreetMap")
                LabeledContent("Weather", value: "Apple WeatherKit")
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI features")
                        .font(.subheadline)
                    Text("Shot parsing and post-round coaching use Claude when an API key is configured, and fall back to fast on-device parsing otherwise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Settings")
    }
}

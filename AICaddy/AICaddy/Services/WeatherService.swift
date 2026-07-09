import Foundation
import CoreLocation
import WeatherKit

/// Fetches wind and weather data for on-course adjustments
@Observable
final class WeatherService {
    var windSpeed: Double?        // mph
    var windDirection: Double?    // degrees, 0 = north; direction wind blows FROM
    var windDirectionLabel: String?
    var temperature: Int?         // Fahrenheit
    var conditions: String?
    var lastUpdated: Date?
    var error: String?
    var isManual = false          // user entered wind by hand (no WeatherKit needed)

    var isStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 15 * 60
    }

    var hasWind: Bool { windSpeed != nil && windDirection != nil }

    /// Manual wind entry — the on-course fallback when WeatherKit isn't available
    /// (no entitlement, no signal). You can feel the wind; just tell the caddy.
    func setManualWind(speedMph: Double, directionDegrees: Double) {
        windSpeed = speedMph
        windDirection = directionDegrees
        windDirectionLabel = Self.compassDirection(directionDegrees)
        lastUpdated = Date()
        isManual = true
        error = nil
    }

    func clearManualWind() {
        guard isManual else { return }
        windSpeed = nil
        windDirection = nil
        windDirectionLabel = nil
        isManual = false
    }

    /// Adjusted distance accounting for wind
    /// Headwind adds ~1% per mph, tailwind subtracts ~0.5% per mph
    func adjustedDistance(yards: Int, shotBearing: Double) -> Int {
        guard let windSpeed, let windDirection else { return yards }

        // Calculate wind component along shot direction
        let angleDiff = (windDirection - shotBearing) * .pi / 180
        let headwindComponent = cos(angleDiff) * windSpeed  // positive = headwind
        let crosswindComponent = abs(sin(angleDiff) * windSpeed)

        // Headwind: ~1 yard per mph, Tailwind: ~0.5 yard per mph
        var adjustment = 0.0
        if headwindComponent > 0 {
            adjustment = headwindComponent * 1.0  // headwind adds distance needed
        } else {
            adjustment = headwindComponent * 0.5  // tailwind reduces distance needed
        }

        // Crosswind has minor distance effect
        adjustment += crosswindComponent * 0.2

        return yards + Int(adjustment.rounded())
    }

    /// Wind direction as compass label
    static func compassDirection(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[index % 16]
    }

    /// One-line summary for the wind chip, e.g. "12 mph SW"
    var windSummary: String? {
        guard let windSpeed, let windDirectionLabel else { return nil }
        return "\(Int(windSpeed.rounded())) mph \(windDirectionLabel)"
    }

    /// Combined wind + temperature "plays like" distance along a shot bearing.
    func playsLikeDistance(yards: Int, shotBearing: Double) -> Int {
        let windAdjusted = adjustedDistance(yards: yards, shotBearing: shotBearing)
        let delta = windAdjusted - yards
        return temperatureAdjustment(yards: yards) + delta
    }

    func fetchWeather(at location: CLLocationCoordinate2D) async {
        if isManual { return }  // don't clobber what the user told us
        do {
            let weatherService = WeatherKit.WeatherService.shared
            let weather = try await weatherService.weather(for: CLLocation(latitude: location.latitude, longitude: location.longitude))

            await MainActor.run {
                let current = weather.currentWeather
                self.windSpeed = current.wind.speed.converted(to: .milesPerHour).value
                self.windDirection = current.wind.direction.converted(to: .degrees).value
                self.windDirectionLabel = Self.compassDirection(self.windDirection ?? 0)
                self.temperature = Int(current.temperature.converted(to: .fahrenheit).value)
                self.conditions = current.condition.description
                self.lastUpdated = Date()
                self.error = nil
            }
        } catch {
            await MainActor.run {
                self.error = "Weather unavailable"
            }
        }
    }

    /// Temperature-based "plays like" adjustment.
    /// Cold air is denser: the ball flies ~2y shorter per 10°F below 70°F, so the
    /// shot PLAYS LONGER (add yards). Hot air: ball flies ~1y farther per 10°F
    /// above 70°F, so it PLAYS SHORTER (subtract yards).
    func temperatureAdjustment(yards: Int) -> Int {
        guard let temp = temperature else { return yards }
        let diff = Double(temp - 70)
        if diff < 0 {
            return yards - Int((diff / 10.0 * 2.0).rounded())  // cold → plays longer
        } else {
            return yards - Int((diff / 10.0 * 1.0).rounded())  // hot → plays shorter
        }
    }
}

import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var location: CLLocationCoordinate2D?
    var accuracy: Double?
    var heading: Double?
    var error: String?
    var isTracking = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 2  // update every 2 meters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    // MARK: - Distance calculation

    /// Haversine distance in yards between two coordinates
    static func distanceYards(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Int {
        let R = 6_371_000.0 / 0.9144  // Earth radius in yards

        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180

        let sinLat = sin(dLat / 2)
        let sinLng = sin(dLng / 2)

        let h = sinLat * sinLat +
            cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLng * sinLng

        return Int(2 * R * asin(sqrt(h)))
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        location = loc.coordinate
        accuracy = loc.horizontalAccuracy
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error.localizedDescription
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.error = nil
        case .denied, .restricted:
            self.error = "Location access denied"
        default:
            break
        }
    }
}

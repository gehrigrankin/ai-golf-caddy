import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - Main View

struct HoleMapView: View {
    let holeGps: HoleGps?
    let holeNumber: Int
    let par: Int
    let userLocation: CLLocationCoordinate2D?
    var playsLikeCenter: Int?

    @State private var dragTarget: CLLocationCoordinate2D?
    @State private var isFullScreen = false
    @State private var showDistances = true
    @State private var followUser = false

    // Distances
    private var distToFront: Int? {
        guard let loc = userLocation, let pt = holeGps?.greenFront else { return nil }
        return LocationService.distanceYards(from: loc, to: pt.coordinate)
    }
    private var distToCenter: Int? {
        guard let loc = userLocation, let pt = holeGps?.greenCenter else { return nil }
        return LocationService.distanceYards(from: loc, to: pt.coordinate)
    }
    private var distToBack: Int? {
        guard let loc = userLocation, let pt = holeGps?.greenBack else { return nil }
        return LocationService.distanceYards(from: loc, to: pt.coordinate)
    }
    private var distToTarget: Int? {
        guard let loc = userLocation, let target = dragTarget else { return nil }
        return LocationService.distanceYards(from: loc, to: target)
    }
    private var targetToGreen: Int? {
        guard let target = dragTarget, let green = holeGps?.greenCenter else { return nil }
        return LocationService.distanceYards(from: target, to: green.coordinate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Distance bar — always visible, tappable to expand
            if showDistances {
                distanceBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Map
            ZStack(alignment: .topTrailing) {
                NativeMapView(
                    holeGps: holeGps,
                    userLocation: userLocation,
                    dragTarget: $dragTarget,
                    followUser: followUser
                )
                .frame(height: isFullScreen ? UIScreen.main.bounds.height * 0.65 : 300)
                .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 14))

                // Floating controls
                VStack(spacing: 8) {
                    // Expand/collapse
                    MapButton(icon: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        withAnimation(.spring(duration: 0.3)) { isFullScreen.toggle() }
                    }

                    // Center on user
                    MapButton(icon: followUser ? "location.fill" : "location") {
                        followUser.toggle()
                    }

                    // Center on hole (fit tee to green)
                    MapButton(icon: "flag.fill") {
                        followUser = false
                        // The NativeMapView handles reframing
                        NotificationCenter.default.post(name: .fitHole, object: nil)
                    }

                    // Toggle distance bar
                    MapButton(icon: showDistances ? "eye.fill" : "eye.slash") {
                        withAnimation { showDistances.toggle() }
                    }
                }
                .padding(10)
            }

            // Target info bar
            if dragTarget != nil {
                targetBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Hint
            if dragTarget == nil {
                Text("Tap & hold anywhere to measure distance")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: dragTarget != nil)
        .animation(.easeInOut(duration: 0.2), value: showDistances)
    }

    // MARK: - Distance Bar

    private var distanceBar: some View {
        HStack(spacing: 0) {
            if let d = distToFront {
                DistancePill(label: "FRONT", yards: d, color: .green)
            }
            if let d = distToCenter {
                DistancePill(
                    label: "PIN", yards: d, color: .white,
                    subLabel: playsLikeCenter.map { "plays \($0)" }
                )
                .scaleEffect(1.1)  // emphasize center distance
            }
            if let d = distToBack {
                DistancePill(label: "BACK", yards: d, color: .red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Target Bar

    private var targetBar: some View {
        HStack(spacing: 16) {
            if let d = distToTarget {
                VStack(spacing: 0) {
                    Text("\(d)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("TO TARGET")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }

            if let d = targetToGreen {
                VStack(spacing: 0) {
                    Text("\(d)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.yellow)
                    Text("TARGET→PIN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow.opacity(0.7))
                }
            }

            Spacer()

            Button {
                withAnimation { dragTarget = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Floating Map Button

private struct MapButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
    }
}

// MARK: - Distance Pill

struct DistancePill: View {
    let label: String
    let yards: Int
    let color: Color
    var subLabel: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color.opacity(0.7))
            Text("\(yards)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let subLabel {
                Text(subLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Notification for reframing

extension Notification.Name {
    static let fitHole = Notification.Name("fitHoleToScreen")
}

// MARK: - Native MKMapView Wrapper (the real deal)

struct NativeMapView: UIViewRepresentable {
    let holeGps: HoleGps?
    let userLocation: CLLocationCoordinate2D?
    @Binding var dragTarget: CLLocationCoordinate2D?
    let followUser: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satellite
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.pointOfInterestFilter = .excludingAll

        // Smooth momentum scrolling
        mapView.isUserInteractionEnabled = true

        // Long press to place target
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        mapView.addGestureRecognizer(longPress)

        // Double tap to zoom (ensure it doesn't conflict)
        for gesture in mapView.gestureRecognizers ?? [] {
            if let doubleTap = gesture as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 {
                longPress.require(toFail: doubleTap)
            }
        }

        // Listen for fit-hole notification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.fitHole),
            name: .fitHole,
            object: nil
        )
        context.coordinator.mapView = mapView

        // Initial framing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            context.coordinator.fitHole()
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAnnotations(on: mapView)
        context.coordinator.updateOverlays(on: mapView)

        if followUser, let loc = userLocation {
            let region = MKCoordinateRegion(
                center: loc,
                latitudinalMeters: 150,
                longitudinalMeters: 150
            )
            mapView.setRegion(region, animated: true)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        weak var mapView: MKMapView?
        private var targetAnnotation: MKPointAnnotation?
        private var isDraggingTarget = false

        init(parent: NativeMapView) {
            self.parent = parent
        }

        // MARK: Long press → place/move target

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            switch gesture.state {
            case .began:
                // Place or start dragging the target
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.dragTarget = coordinate
                isDraggingTarget = true

            case .changed:
                // Continuously update target position as finger moves
                if isDraggingTarget {
                    parent.dragTarget = coordinate
                }

            case .ended, .cancelled:
                isDraggingTarget = false
                if let coord = parent.dragTarget {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    parent.dragTarget = coord
                }

            default:
                break
            }
        }

        // MARK: Fit hole tee-to-green

        @objc func fitHole() {
            guard let mapView, let gps = parent.holeGps else { return }

            var coords: [CLLocationCoordinate2D] = []
            if let tee = gps.tee { coords.append(tee.coordinate) }
            if let green = gps.greenCenter { coords.append(green.coordinate) }
            if let loc = parent.userLocation { coords.append(loc) }
            gps.hazards?.forEach { coords.append($0.position.coordinate) }

            guard coords.count >= 2 else { return }

            let rect = coords.dropFirst().reduce(MKMapRect(origin: MKMapPoint(coords[0]), size: .init())) { rect, coord in
                let point = MKMapPoint(coord)
                return rect.union(MKMapRect(origin: point, size: .init()))
            }

            let padding = UIEdgeInsets(top: 50, left: 40, bottom: 50, right: 40)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

        // MARK: Annotations

        func updateAnnotations(on mapView: MKMapView) {
            mapView.removeAnnotations(mapView.annotations)

            // User location (custom, not MKUserLocation)
            if let loc = parent.userLocation {
                let ann = GolfAnnotation(coordinate: loc, type: .user)
                mapView.addAnnotation(ann)
            }

            guard let gps = parent.holeGps else { return }

            // Tee
            if let tee = gps.tee {
                mapView.addAnnotation(GolfAnnotation(coordinate: tee.coordinate, type: .tee))
            }

            // Green
            if let green = gps.greenCenter {
                let ann = GolfAnnotation(coordinate: green.coordinate, type: .greenCenter)
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: green.coordinate)
                }
                mapView.addAnnotation(ann)
            }
            if let front = gps.greenFront {
                mapView.addAnnotation(GolfAnnotation(coordinate: front.coordinate, type: .greenFront))
            }
            if let back = gps.greenBack {
                mapView.addAnnotation(GolfAnnotation(coordinate: back.coordinate, type: .greenBack))
            }

            // Hazards
            for hazard in gps.hazards ?? [] {
                let ann = GolfAnnotation(coordinate: hazard.position.coordinate,
                                        type: hazard.type == "water" ? .water : .bunker)
                ann.title = hazard.label
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: hazard.position.coordinate)
                }
                mapView.addAnnotation(ann)
            }

            // Drag target
            if let target = parent.dragTarget {
                let ann = GolfAnnotation(coordinate: target, type: .target)
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: target)
                }
                ann.secondaryDistance = gps.greenCenter.map {
                    LocationService.distanceYards(from: target, to: $0.coordinate)
                }
                mapView.addAnnotation(ann)
            }
        }

        // MARK: Overlays (lines)

        func updateOverlays(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)

            guard let loc = parent.userLocation else { return }

            // Line: user → green
            if let green = parent.holeGps?.greenCenter {
                let coords = [loc, green.coordinate]
                let line = GolfPolyline(coordinates: coords, count: coords.count)
                line.lineType = .userToGreen
                mapView.addOverlay(line)
            }

            // Line: user → target
            if let target = parent.dragTarget {
                let coords = [loc, target]
                let line = GolfPolyline(coordinates: coords, count: coords.count)
                line.lineType = .userToTarget
                mapView.addOverlay(line)

                // Line: target → green
                if let green = parent.holeGps?.greenCenter {
                    let coords2 = [target, green.coordinate]
                    let line2 = GolfPolyline(coordinates: coords2, count: coords2.count)
                    line2.lineType = .targetToGreen
                    mapView.addOverlay(line2)
                }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let golfAnn = annotation as? GolfAnnotation else { return nil }

            let id = golfAnn.type.rawValue
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)

            view.annotation = annotation
            view.canShowCallout = false

            switch golfAnn.type {
            case .user:
                let size: CGFloat = 18
                let outer = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
                let pulse = UIView(frame: CGRect(x: 2, y: 2, width: 40, height: 40))
                pulse.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
                pulse.layer.cornerRadius = 20
                outer.addSubview(pulse)
                let dot = UIView(frame: CGRect(x: (44 - size) / 2, y: (44 - size) / 2, width: size, height: size))
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = size / 2
                dot.layer.borderWidth = 2.5
                dot.layer.borderColor = UIColor.white.cgColor
                dot.layer.shadowColor = UIColor.black.cgColor
                dot.layer.shadowOffset = CGSize(width: 0, height: 1)
                dot.layer.shadowRadius = 3
                dot.layer.shadowOpacity = 0.4
                outer.addSubview(dot)
                view.addSubview(outer)
                view.frame = outer.frame
                view.centerOffset = CGPoint(x: 0, y: 0)

            case .tee:
                view.image = nil
                let label = PaddedLabel(text: "TEE", bgColor: .white, textColor: .black, fontSize: 8)
                view.addSubview(label)
                view.frame = label.frame

            case .greenCenter:
                let container = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 44))

                // Green circle with flag
                let circle = UIView(frame: CGRect(x: 20, y: 0, width: 22, height: 22))
                circle.backgroundColor = UIColor.systemGreen
                circle.layer.cornerRadius = 11
                circle.layer.borderWidth = 2.5
                circle.layer.borderColor = UIColor.white.cgColor
                circle.layer.shadowColor = UIColor.black.cgColor
                circle.layer.shadowOffset = CGSize(width: 0, height: 2)
                circle.layer.shadowRadius = 4
                circle.layer.shadowOpacity = 0.5
                container.addSubview(circle)

                // Flag pin
                let pin = UIView(frame: CGRect(x: 30, y: 2, width: 1.5, height: 10))
                pin.backgroundColor = .white
                container.addSubview(pin)

                // Distance label
                if let dist = golfAnn.distance {
                    let label = PaddedLabel(text: "\(dist)y", bgColor: .black.withAlphaComponent(0.75), textColor: .white, fontSize: 11, bold: true)
                    label.frame.origin = CGPoint(x: (60 - label.frame.width) / 2, y: 25)
                    container.addSubview(label)
                }

                view.addSubview(container)
                view.frame = container.frame
                view.centerOffset = CGPoint(x: 0, y: -22)

            case .greenFront:
                let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
                dot.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.8)
                dot.layer.cornerRadius = 5
                dot.layer.borderWidth = 1
                dot.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
                view.addSubview(dot)
                view.frame = dot.frame

            case .greenBack:
                let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
                dot.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
                dot.layer.cornerRadius = 5
                dot.layer.borderWidth = 1
                dot.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
                view.addSubview(dot)
                view.frame = dot.frame

            case .bunker:
                let container = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 30))
                let dot = UIView(frame: CGRect(x: 19, y: 0, width: 12, height: 12))
                dot.backgroundColor = .systemYellow
                dot.layer.cornerRadius = 6
                dot.layer.borderWidth = 1
                dot.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
                container.addSubview(dot)
                if let dist = golfAnn.distance {
                    let label = PaddedLabel(text: "\(dist)y", bgColor: .black.withAlphaComponent(0.6), textColor: .white, fontSize: 9)
                    label.frame.origin = CGPoint(x: (50 - label.frame.width) / 2, y: 14)
                    container.addSubview(label)
                }
                view.addSubview(container)
                view.frame = container.frame

            case .water:
                let container = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 30))
                let dot = UIView(frame: CGRect(x: 19, y: 0, width: 12, height: 12))
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = 6
                dot.layer.borderWidth = 1
                dot.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
                container.addSubview(dot)
                if let dist = golfAnn.distance {
                    let label = PaddedLabel(text: "\(dist)y", bgColor: .black.withAlphaComponent(0.6), textColor: .systemBlue, fontSize: 9)
                    label.frame.origin = CGPoint(x: (50 - label.frame.width) / 2, y: 14)
                    container.addSubview(label)
                }
                view.addSubview(container)
                view.frame = container.frame

            case .target:
                let size: CGFloat = 36
                let container = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 60))

                // Crosshair
                let crosshair = UIView(frame: CGRect(x: (80 - size) / 2, y: 0, width: size, height: size))
                crosshair.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
                crosshair.layer.cornerRadius = size / 2
                crosshair.layer.borderWidth = 2.5
                crosshair.layer.borderColor = UIColor.systemOrange.cgColor

                let vLine = UIView(frame: CGRect(x: size / 2 - 0.75, y: 4, width: 1.5, height: size - 8))
                vLine.backgroundColor = .systemOrange
                crosshair.addSubview(vLine)

                let hLine = UIView(frame: CGRect(x: 4, y: size / 2 - 0.75, width: size - 8, height: 1.5))
                hLine.backgroundColor = .systemOrange
                crosshair.addSubview(hLine)

                let centerDot = UIView(frame: CGRect(x: size / 2 - 3, y: size / 2 - 3, width: 6, height: 6))
                centerDot.backgroundColor = .systemOrange
                centerDot.layer.cornerRadius = 3
                crosshair.addSubview(centerDot)

                container.addSubview(crosshair)

                // Distance labels
                var labelText = ""
                if let d = golfAnn.distance { labelText += "\(d)y" }
                if let d2 = golfAnn.secondaryDistance { labelText += "  →\(d2)y" }
                if !labelText.isEmpty {
                    let label = PaddedLabel(text: labelText, bgColor: .black.withAlphaComponent(0.85), textColor: .systemOrange, fontSize: 10, bold: true)
                    label.frame.origin = CGPoint(x: (80 - label.frame.width) / 2, y: size + 3)
                    container.addSubview(label)
                }

                view.addSubview(container)
                view.frame = container.frame
                view.centerOffset = CGPoint(x: 0, y: -size / 2)
            }

            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? GolfPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)

            switch polyline.lineType {
            case .userToGreen:
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.5)
                renderer.lineWidth = 2
                renderer.lineDashPattern = [8, 5]
            case .userToTarget:
                renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.8)
                renderer.lineWidth = 2.5
            case .targetToGreen:
                renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.4)
                renderer.lineWidth = 1.5
                renderer.lineDashPattern = [5, 4]
            case .none:
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.3)
                renderer.lineWidth = 1
            }

            return renderer
        }
    }
}

// MARK: - Custom Annotation

class GolfAnnotation: MKPointAnnotation {
    enum AnnotationType: String {
        case user, tee, greenCenter, greenFront, greenBack, bunker, water, target
    }

    let type: AnnotationType
    var distance: Int?
    var secondaryDistance: Int?

    init(coordinate: CLLocationCoordinate2D, type: AnnotationType) {
        self.type = type
        super.init()
        self.coordinate = coordinate
    }
}

// MARK: - Custom Polyline

class GolfPolyline: MKPolyline {
    enum LineType { case userToGreen, userToTarget, targetToGreen, none }
    var lineType: LineType = .none
}

// MARK: - Padded Label Helper

private class PaddedLabel: UIView {
    init(text: String, bgColor: UIColor, textColor: UIColor, fontSize: CGFloat, bold: Bool = false) {
        super.init(frame: .zero)

        let label = UILabel()
        label.text = text
        label.textColor = textColor
        label.font = bold ? .boldSystemFont(ofSize: fontSize) : .systemFont(ofSize: fontSize, weight: .medium)
        label.sizeToFit()

        let padding: CGFloat = 5
        self.frame = CGRect(x: 0, y: 0, width: label.frame.width + padding * 2, height: label.frame.height + padding)
        self.backgroundColor = bgColor
        self.layer.cornerRadius = (label.frame.height + padding) / 2
        self.clipsToBounds = true

        label.frame.origin = CGPoint(x: padding, y: padding / 2)
        self.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }
}

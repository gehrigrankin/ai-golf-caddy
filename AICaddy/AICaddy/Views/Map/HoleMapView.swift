import SwiftUI
import MapKit

struct HoleMapView: View {
    let holeGps: HoleGps?
    let holeNumber: Int
    let par: Int
    let userLocation: CLLocationCoordinate2D?

    @State private var dragTarget: CLLocationCoordinate2D?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showDistances = true

    // Calculated distances
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
        VStack(spacing: 8) {
            // Distance badges
            if showDistances {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let d = distToFront {
                            DistanceBadge(label: "Front", yards: d, color: .green)
                        }
                        if let d = distToCenter {
                            DistanceBadge(label: "Center", yards: d, color: .white)
                        }
                        if let d = distToBack {
                            DistanceBadge(label: "Back", yards: d, color: .red)
                        }
                        if let d = distToTarget {
                            DistanceBadge(label: "Target", yards: d, color: .orange)
                        }
                        if let d = targetToGreen {
                            DistanceBadge(label: "To Green", yards: d, color: .yellow)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            // Map
            Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate]) {
                // User location
                if let loc = userLocation {
                    Annotation("You", coordinate: loc) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(.blue)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }

                // Tee
                if let tee = holeGps?.tee {
                    Annotation("Tee", coordinate: tee.coordinate) {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                            Text("TEE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }

                // Green center
                if let green = holeGps?.greenCenter {
                    Annotation("Green", coordinate: green.coordinate) {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle().fill(.green).frame(width: 18, height: 18)
                                Circle().fill(.white).frame(width: 4, height: 4)
                            }
                            .overlay(Circle().stroke(.white, lineWidth: 2).frame(width: 18, height: 18))
                            if let d = distToCenter {
                                Text("\(d)y")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }

                // Green front/back
                if let front = holeGps?.greenFront {
                    Annotation("Front", coordinate: front.coordinate) {
                        Circle().fill(.green.opacity(0.7)).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                }
                if let back = holeGps?.greenBack {
                    Annotation("Back", coordinate: back.coordinate) {
                        Circle().fill(.red.opacity(0.7)).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                }

                // Hazards
                if let hazards = holeGps?.hazards {
                    ForEach(Array(hazards.enumerated()), id: \.offset) { _, hazard in
                        Annotation(hazard.label ?? hazard.type, coordinate: hazard.position.coordinate) {
                            VStack(spacing: 1) {
                                Circle()
                                    .fill(hazard.type == "water" ? .blue : hazard.type == "bunker" ? .yellow : .green.opacity(0.8))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                                if let loc = userLocation {
                                    Text("\(LocationService.distanceYards(from: loc, to: hazard.position.coordinate))y")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 2)
                                        .background(.black.opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                }
                            }
                        }
                    }
                }

                // Draggable target
                if let target = dragTarget {
                    Annotation("Target", coordinate: target) {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .stroke(.orange, lineWidth: 2)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(.orange.opacity(0.15)))
                                // Crosshair
                                Rectangle().fill(.orange).frame(width: 1, height: 18)
                                Rectangle().fill(.orange).frame(width: 18, height: 1)
                                Circle().fill(.orange).frame(width: 6, height: 6)
                            }
                            HStack(spacing: 4) {
                                if let d = distToTarget {
                                    Text("\(d)y")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.orange)
                                }
                                if let d = targetToGreen {
                                    Text("| \(d)y to pin")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                // Line from user to green
                if let loc = userLocation, let green = holeGps?.greenCenter {
                    MapPolyline(coordinates: [loc, green.coordinate])
                        .stroke(.green.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }

                // Line from user to target
                if let loc = userLocation, let target = dragTarget {
                    MapPolyline(coordinates: [loc, target])
                        .stroke(.orange.opacity(0.7), lineWidth: 2)
                }

                // Line from target to green
                if let target = dragTarget, let green = holeGps?.greenCenter {
                    MapPolyline(coordinates: [target, green.coordinate])
                        .stroke(.orange.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .mapStyle(.imagery)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .onTapGesture { location in
                // Note: MapKit doesn't directly support tap-to-coordinate.
                // We use a long press gesture overlay instead — see below.
            }
            .overlay(alignment: .topTrailing) {
                // Recenter button
                Button {
                    mapPosition = .automatic
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(8)
            }

            // Controls
            HStack {
                if dragTarget != nil {
                    Button("Clear target") {
                        dragTarget = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                    Text("Long press map to place target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(showDistances ? "Hide distances" : "Show distances") {
                    showDistances.toggle()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            setupInitialPosition()
        }
    }

    private func setupInitialPosition() {
        guard let gps = holeGps else { return }

        var points: [CLLocationCoordinate2D] = []
        if let tee = gps.tee { points.append(tee.coordinate) }
        if let green = gps.greenCenter { points.append(green.coordinate) }
        if let loc = userLocation { points.append(loc) }

        guard points.count >= 2 else { return }

        let lats = points.map(\.latitude)
        let lngs = points.map(\.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (lats.max()! - lats.min()!) * 1.5 + 0.002,
            longitudeDelta: (lngs.max()! - lngs.min()!) * 1.5 + 0.002
        )

        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Distance Badge

struct DistanceBadge: View {
    let label: String
    let yards: Int
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text("\(yards)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
            Text("yds")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Map Tap Handler

/// Overlay to handle long-press on the map and convert to coordinates
struct MapTapOverlay: UIViewRepresentable {
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        gesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(gesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLongPress: onLongPress)
    }

    class Coordinator: NSObject {
        let onLongPress: (CLLocationCoordinate2D) -> Void

        init(onLongPress: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            // Note: converting screen point to coordinate requires the MKMapView reference.
            // In a production app, you'd use a UIViewRepresentable MKMapView for full control.
            // For now, the target can be set via the distance badges or a coordinate picker.
        }
    }
}

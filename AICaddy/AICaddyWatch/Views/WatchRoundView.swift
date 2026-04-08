import SwiftUI

/// Main Apple Watch view — quick score input from your wrist
struct WatchRoundView: View {
    let connectivity: WatchConnectivityManager

    var body: some View {
        if connectivity.isRoundActive {
            ActiveRoundWatch(connectivity: connectivity)
        } else {
            WaitingView(connectivity: connectivity)
        }
    }
}

struct ActiveRoundWatch: View {
    let connectivity: WatchConnectivityManager

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Hole header
                Text("Hole \(connectivity.currentHole)")
                    .font(.title2.bold())
                Text("Par \(connectivity.currentPar)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Distance to green
                if let dist = connectivity.distToGreen {
                    Text("\(dist)y")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.green)
                    Text("to green")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Running score
                HStack {
                    Text("\(connectivity.totalScore)")
                        .font(.headline)
                    Text(connectivity.scoreToPar == 0 ? "E" :
                            (connectivity.scoreToPar > 0 ? "+\(connectivity.scoreToPar)" : "\(connectivity.scoreToPar)"))
                        .font(.caption)
                        .foregroundStyle(connectivity.scoreToPar <= 0 ? .green : .red)
                }

                Divider()

                // Quick score buttons
                Text("Score").font(.caption2).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    QuickWatchButton(label: "Birdie", value: connectivity.currentPar - 1, color: .red) {
                        connectivity.sendScore("birdie")
                    }
                    QuickWatchButton(label: "Par", value: connectivity.currentPar, color: .green) {
                        connectivity.sendScore("par")
                    }
                }

                HStack(spacing: 6) {
                    QuickWatchButton(label: "Bogey", value: connectivity.currentPar + 1, color: .cyan) {
                        connectivity.sendScore("bogey")
                    }
                    QuickWatchButton(label: "Dbl", value: connectivity.currentPar + 2, color: .blue) {
                        connectivity.sendScore("double bogey")
                    }
                }

                // Custom score
                HStack(spacing: 4) {
                    ForEach(max(1, connectivity.currentPar - 2)...connectivity.currentPar + 4, id: \.self) { score in
                        Button {
                            connectivity.sendScore("\(score)")
                        } label: {
                            Text("\(score)")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(Color.gray.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Putts quick entry
                Divider()
                Text("Putts").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { p in
                        Button {
                            connectivity.sendScore("\(p) putts")
                        } label: {
                            Text("\(p)")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 32, height: 28)
                                .background(Color.gray.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct QuickWatchButton: View {
    let label: String
    let value: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct WaitingView: View {
    let connectivity: WatchConnectivityManager

    var body: some View {
        VStack(spacing: 8) {
            Text("⛳").font(.largeTitle)
            Text("AI Caddy")
                .font(.headline)
            Text("Start a round on your\niPhone to begin")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !connectivity.isReachable {
                Text("iPhone not connected")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Button("Sync") {
                connectivity.requestSync()
            }
            .font(.caption)
            .padding(.top, 4)
        }
    }
}

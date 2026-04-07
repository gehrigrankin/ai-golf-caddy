import SwiftUI

struct ScorecardView: View {
    let holes: [HoleScore]
    let courseName: String
    let teeName: String
    var onHoleTap: ((Int) -> Void)?

    private var front: [HoleScore] { holes.filter { $0.holeNumber <= 9 } }
    private var back: [HoleScore] { holes.filter { $0.holeNumber > 9 } }

    private var frontPar: Int { front.reduce(0) { $0 + $1.par } }
    private var backPar: Int { back.reduce(0) { $0 + $1.par } }
    private var frontScore: Int { front.reduce(0) { $0 + $1.strokes } }
    private var backScore: Int { back.reduce(0) { $0 + $1.strokes } }
    private var totalScore: Int { frontScore + backScore }
    private var totalPar: Int { frontPar + backPar }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                if totalScore > 0 {
                    Text("\(totalScore)")
                        .font(.title2.bold())
                    ScoreText(scoreToPar: totalScore - totalPar)
                        .font(.subheadline.bold())
                }
                Spacer()
                Text("\(courseName) · \(teeName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Front 9
            NineHoleGrid(
                label: "Out",
                holes: front,
                totalPar: frontPar,
                totalScore: frontScore,
                onHoleTap: onHoleTap
            )

            // Back 9
            NineHoleGrid(
                label: "In",
                holes: back,
                totalPar: backPar,
                totalScore: backScore,
                onHoleTap: onHoleTap
            )
        }
    }
}

struct NineHoleGrid: View {
    let label: String
    let holes: [HoleScore]
    let totalPar: Int
    let totalScore: Int
    var onHoleTap: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 2) {
            // Hole numbers
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                ForEach(holes) { hole in
                    Text("\(hole.holeNumber)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                Text("Tot")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }

            // Par
            HStack(spacing: 0) {
                Text("Par")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                ForEach(holes) { hole in
                    Text("\(hole.par)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                Text("\(totalPar)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }

            // Scores
            HStack(spacing: 0) {
                Text("Score")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                ForEach(holes) { hole in
                    Button {
                        onHoleTap?(hole.holeNumber)
                    } label: {
                        ScoreCircle(strokes: hole.strokes, par: hole.par, size: 26)
                    }
                    .frame(maxWidth: .infinity)
                }
                Text(totalScore > 0 ? "\(totalScore)" : "-")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32)
            }

            // Putts
            HStack(spacing: 0) {
                Text("Putt")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .leading)
                ForEach(holes) { hole in
                    Text(hole.putts.map { "\($0)" } ?? "-")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                Text("\(holes.compactMap(\.putts).reduce(0, +))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32)
            }

            // GIR
            HStack(spacing: 0) {
                Text("GIR")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .leading)
                ForEach(holes) { hole in
                    Text(hole.greenInRegulation == true ? "●" : hole.greenInRegulation == false ? "○" : "-")
                        .font(.system(size: 9))
                        .foregroundStyle(hole.greenInRegulation == true ? .green : .tertiary)
                        .frame(maxWidth: .infinity)
                }
                let girCount = holes.filter { $0.greenInRegulation == true }.count
                let girTotal = holes.filter { $0.greenInRegulation != nil }.count
                Text("\(girCount)/\(girTotal)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32)
            }
        }
        .padding(8)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

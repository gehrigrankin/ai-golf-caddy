import Foundation

/// Parsed result from voice/text input
struct ParsedShotInput {
    var shots: [Shot]
    var putts: Int?
    var totalStrokes: Int?
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
    var confidence: Double
}

/// Parses natural language shot descriptions into structured data.
/// Uses Claude API when available, falls back to local regex parsing.
final class ShotParserService {
    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String
    }

    func parse(
        input: String,
        holeNumber: Int,
        par: Int,
        yardage: Int?,
        currentShotNumber: Int
    ) async -> ParsedShotInput {
        // Try Claude API first
        if let apiKey, !apiKey.isEmpty {
            if let result = await parseWithClaude(
                input: input, apiKey: apiKey,
                holeNumber: holeNumber, par: par,
                yardage: yardage, currentShotNumber: currentShotNumber
            ) {
                return result
            }
        }

        // Fall back to local parser
        return localParse(input: input, par: par, currentShotNumber: currentShotNumber)
    }

    // MARK: - Claude API

    private func parseWithClaude(
        input: String, apiKey: String,
        holeNumber: Int, par: Int, yardage: Int?, currentShotNumber: Int
    ) async -> ParsedShotInput? {
        let systemPrompt = """
        You are a golf shot parser. Given a golfer's spoken description, extract structured data.
        Return ONLY valid JSON:
        {
          "shots": [{"shotNumber": N, "club": "string|null", "distanceYards": N|null, "result": "string|null", "isPenalty": bool, "isPutt": bool}],
          "putts": N|null, "totalStrokes": N|null, "fairwayHit": bool|null,
          "greenInRegulation": bool|null, "confidence": 0.0-1.0
        }
        Club values: driver, 3-wood, 5-wood, 7-wood, 2-hybrid through 5-hybrid, 2-iron through 9-iron, pw, gw, sw, lw, putter.
        Result values: fairway, rough, deep-rough, bunker, water, ob, green, fringe, trees, recovery, holed.
        If just a number like "4", that's totalStrokes. "par","bogey","birdie","eagle","double","triple" are relative to par.
        """

        let userMsg = "Hole \(holeNumber), Par \(par)\(yardage.map { ", \($0) yards" } ?? ""). Shot #\(currentShotNumber). Golfer says: \"\(input)\""

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 512,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMsg]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String,
              let jsonRange = text.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression),
              let parsed = try? JSONSerialization.jsonObject(with: Data(text[jsonRange].utf8)) as? [String: Any]
        else { return nil }

        return convertAPIResponse(parsed, currentShotNumber: currentShotNumber)
    }

    private func convertAPIResponse(_ json: [String: Any], currentShotNumber: Int) -> ParsedShotInput {
        var result = ParsedShotInput(shots: [], confidence: json["confidence"] as? Double ?? 0.7)

        result.totalStrokes = json["totalStrokes"] as? Int
        result.putts = json["putts"] as? Int
        result.fairwayHit = json["fairwayHit"] as? Bool
        result.greenInRegulation = json["greenInRegulation"] as? Bool

        if let shotsArr = json["shots"] as? [[String: Any]] {
            for (i, s) in shotsArr.enumerated() {
                let club = (s["club"] as? String).flatMap { Club(rawValue: $0) }
                let result = (s["result"] as? String).flatMap { ShotResult(rawValue: $0) }
                let shot = Shot(
                    shotNumber: s["shotNumber"] as? Int ?? currentShotNumber + i,
                    club: club,
                    distanceYards: s["distanceYards"] as? Int,
                    result: result,
                    isPenalty: s["isPenalty"] as? Bool ?? false,
                    isPutt: s["isPutt"] as? Bool ?? false
                )
                result.shots.append(shot)
            }
        }

        return result
    }

    // MARK: - Local Parser

    private static let clubAliases: [(String, Club)] = [
        ("driver", .driver),
        ("3 wood", .wood3), ("3wood", .wood3), ("three wood", .wood3),
        ("5 wood", .wood5), ("5wood", .wood5), ("five wood", .wood5),
        ("7 wood", .wood7), ("7wood", .wood7),
        ("2 hybrid", .hybrid2), ("3 hybrid", .hybrid3),
        ("4 hybrid", .hybrid4), ("5 hybrid", .hybrid5),
        ("2 iron", .iron2), ("3 iron", .iron3), ("4 iron", .iron4),
        ("5 iron", .iron5), ("6 iron", .iron6), ("7 iron", .iron7),
        ("8 iron", .iron8), ("9 iron", .iron9),
        ("pitching wedge", .pw), ("pw", .pw),
        ("gap wedge", .gw), ("gw", .gw),
        ("sand wedge", .sw), ("sw", .sw),
        ("lob wedge", .lw), ("lw", .lw),
        ("putter", .putter), ("putt", .putter),
    ]

    private static let resultAliases: [(String, ShotResult)] = [
        ("fairway", .fairway), ("in the fairway", .fairway),
        ("rough", .rough), ("deep rough", .deepRough),
        ("bunker", .bunker), ("sand", .bunker), ("trap", .bunker),
        ("water", .water), ("hazard", .water),
        ("ob", .ob), ("out of bounds", .ob),
        ("green", .green), ("on the green", .green), ("on green", .green), ("pin high", .green),
        ("fringe", .fringe), ("trees", .trees),
        ("holed", .holed), ("hole in one", .holed),
    ]

    func localParse(input: String, par: Int, currentShotNumber: Int) -> ParsedShotInput {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ParsedShotInput(shots: [], confidence: 0.6)

        // Simple score: "4", "par", "bogey", "birdie 2 putts"
        if let simple = parseSimpleScore(lower, par: par) {
            result.totalStrokes = simple.strokes
            result.putts = simple.putts
            result.confidence = 0.8
            return result
        }

        // Putts only: "2 putts"
        if let match = lower.range(of: #"(\d)\s*putts?"#, options: .regularExpression),
           lower.count < 15 {
            let digit = lower[match].first { $0.isNumber }
            if let d = digit { result.putts = Int(String(d)) }
            result.confidence = 0.9
            return result
        }

        // Parse individual shots
        let segments = lower.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: " then ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var shotNum = currentShotNumber
        for seg in segments {
            if let shot = parseShotSegment(seg, shotNumber: shotNum) {
                result.shots.append(shot)
                shotNum += 1
            }
        }

        if lower.contains("fairway") { result.fairwayHit = true }
        if lower.contains("missed fairway") || lower.contains("miss fairway") { result.fairwayHit = false }

        result.confidence = result.shots.isEmpty ? 0.4 : 0.7
        return result
    }

    private func parseShotSegment(_ seg: String, shotNumber: Int) -> Shot? {
        var club: Club?
        var dist: Int?
        var shotResult: ShotResult?
        var matched = false

        for (alias, c) in Self.clubAliases {
            if seg.contains(alias) { club = c; matched = true; break }
        }

        if let match = seg.range(of: #"(\d{2,3})\s*(?:yards?|yds?)?"#, options: .regularExpression) {
            let numStr = seg[match].filter(\.isNumber)
            dist = Int(numStr)
            matched = true
        }

        for (alias, r) in Self.resultAliases {
            if seg.contains(alias) { shotResult = r; matched = true; break }
        }

        guard matched else { return nil }

        let isPenalty = seg.contains("penalty") || seg.contains("water") || seg.contains("ob") || seg.contains("out of bounds")

        return Shot(
            shotNumber: shotNumber,
            club: club,
            distanceYards: dist,
            result: shotResult,
            isPenalty: isPenalty,
            isPutt: club == .putter
        )
    }

    private func parseSimpleScore(_ input: String, par: Int) -> (strokes: Int, putts: Int?)? {
        var putts: Int?
        if let match = input.range(of: #"(\d)\s*putts?"#, options: .regularExpression) {
            let digit = input[match].first { $0.isNumber }
            putts = digit.flatMap { Int(String($0)) }
        }

        let scorePart = input.replacingOccurrences(of: #"\d\s*putts?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let strokes: Int?
        switch scorePart {
        case "ace", "hole in one": strokes = 1
        case "albatross", "double eagle": strokes = par - 3
        case "eagle": strokes = par - 2
        case "birdie": strokes = par - 1
        case "par": strokes = par
        case "bogey": strokes = par + 1
        case "double", "double bogey": strokes = par + 2
        case "triple", "triple bogey": strokes = par + 3
        default:
            if let n = Int(scorePart), (1...15).contains(n) { strokes = n }
            else { strokes = nil }
        }

        guard let s = strokes else { return nil }
        return (s, putts)
    }
}

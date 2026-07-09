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
        // Unambiguous inputs ("par", "5", "2 putts", quick-score buttons) parse
        // locally and instantly — no reason to wait on a network round-trip.
        let local = localParse(input: input, par: par, currentShotNumber: currentShotNumber)
        if local.confidence >= 0.8 {
            return local
        }

        // Try Claude API for the messy stuff
        if let apiKey, !apiKey.isEmpty {
            if let result = await parseWithClaude(
                input: input, apiKey: apiKey,
                holeNumber: holeNumber, par: par,
                yardage: yardage, currentShotNumber: currentShotNumber
            ) {
                return result
            }
        }

        // Fall back to the local parse
        return local
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
        "2 putts" means two separate putt shots.
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
        request.timeoutInterval = 6  // fall back to local parser quickly on a bad connection

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
                let shotResult = (s["result"] as? String).flatMap { ShotResult(rawValue: $0) }
                let shot = Shot(
                    shotNumber: s["shotNumber"] as? Int ?? currentShotNumber + i,
                    club: club,
                    distanceYards: s["distanceYards"] as? Int,
                    result: shotResult,
                    isPenalty: s["isPenalty"] as? Bool ?? false,
                    isPutt: s["isPutt"] as? Bool ?? false
                )
                result.shots.append(shot)
            }
        }

        return result
    }

    // MARK: - Local Parser

    // Aliases are matched on word boundaries, longest alias first, so
    // "sand wedge" wins over "sand", and "260" can never match the "60" of a lob wedge.
    private static let clubAliases: [(String, Club)] = [
        // Wedges — spoken degree forms first (longest match wins)
        ("pitching wedge", .pw), ("gap wedge", .gw), ("sand wedge", .sw), ("lob wedge", .lw),
        ("52 degree", .gw), ("fifty two degree", .gw),
        ("56 degree", .sw), ("fifty six degree", .sw),
        ("58 degree", .lw), ("fifty eight degree", .lw),
        ("60 degree", .lw), ("sixty degree", .lw),
        // Woods
        ("3 wood", .wood3), ("3wood", .wood3), ("three wood", .wood3),
        ("5 wood", .wood5), ("5wood", .wood5), ("five wood", .wood5),
        ("7 wood", .wood7), ("7wood", .wood7), ("seven wood", .wood7),
        // Hybrids
        ("2 hybrid", .hybrid2), ("two hybrid", .hybrid2),
        ("3 hybrid", .hybrid3), ("three hybrid", .hybrid3),
        ("4 hybrid", .hybrid4), ("four hybrid", .hybrid4),
        ("5 hybrid", .hybrid5), ("five hybrid", .hybrid5),
        ("hybrid", .hybrid4), ("rescue", .hybrid4),
        // Irons
        ("2 iron", .iron2), ("two iron", .iron2),
        ("3 iron", .iron3), ("three iron", .iron3),
        ("4 iron", .iron4), ("four iron", .iron4),
        ("5 iron", .iron5), ("five iron", .iron5),
        ("6 iron", .iron6), ("six iron", .iron6),
        ("7 iron", .iron7), ("seven iron", .iron7),
        ("8 iron", .iron8), ("eight iron", .iron8),
        ("9 iron", .iron9), ("nine iron", .iron9),
        // Driver
        ("driver", .driver), ("big dog", .driver), ("big stick", .driver), ("drive", .driver),
        // Short wedge forms
        ("pitch", .pw), ("pw", .pw), ("gw", .gw), ("sw", .sw), ("lw", .lw), ("lob", .lw),
        // Putter
        ("putter", .putter), ("putted", .putter), ("putting", .putter), ("putt", .putter),
    ]

    private static let resultAliases: [(String, ShotResult)] = [
        // Fairway
        ("middle of the fairway", .fairway), ("split the fairway", .fairway),
        ("found the fairway", .fairway), ("in the fairway", .fairway),
        ("hit fairway", .fairway), ("fairway", .fairway),
        // Rough
        ("deep rough", .deepRough), ("thick rough", .deepRough), ("heavy rough", .deepRough),
        ("in the rough", .rough), ("left rough", .rough), ("right rough", .rough),
        ("first cut", .rough), ("light rough", .rough), ("rough", .rough),
        // Bunker
        ("greenside bunker", .bunker), ("fairway bunker", .bunker), ("sand trap", .bunker),
        ("in the sand", .bunker), ("bunker", .bunker), ("trap", .bunker),
        ("beach", .bunker), ("sand", .bunker),
        // Water
        ("in the water", .water), ("water", .water), ("hazard", .water), ("wet", .water),
        ("lake", .water), ("pond", .water), ("creek", .water), ("drink", .water),
        // OB
        ("out of bounds", .ob), ("o.b.", .ob), ("o b", .ob), ("ob", .ob),
        // Green
        ("on the dance floor", .green), ("green in regulation", .green),
        ("hit the green", .green), ("found the green", .green),
        ("on the green", .green), ("on green", .green), ("pin high", .green),
        ("green", .green), ("gir", .green),
        // Fringe
        ("just off the green", .fringe), ("on the fringe", .fringe),
        ("fringe", .fringe), ("collar", .fringe), ("apron", .fringe),
        // Trees
        ("in the trees", .trees), ("trees", .trees), ("woods", .trees),
        // Recovery
        ("punch out", .recovery), ("chip out", .recovery), ("punched out", .recovery),
        ("punch", .recovery), ("recovery", .recovery),
        // Holed
        ("hole in one", .holed), ("holed out", .holed), ("holed", .holed),
        ("jarred it", .holed), ("drained it", .holed), ("in the hole", .holed),
    ]

    func localParse(input: String, par: Int, currentShotNumber: Int) -> ParsedShotInput {
        let lower = normalize(input)
        var result = ParsedShotInput(shots: [], confidence: 0.6)

        // Simple score: "4", "par", "bogey", "birdie 2 putts"
        if let simple = parseSimpleScore(lower, par: par) {
            result.totalStrokes = simple.strokes
            result.putts = simple.putts
            result.confidence = 0.8
            return result
        }

        // Putts only: "2 putts", "one putt", "3 putt"
        if wholeInputIsPutts(lower) {
            let count = puttCount(in: lower) ?? 2
            result.putts = count
            result.shots = puttShots(count: count, startingAt: currentShotNumber)
            result.confidence = 0.9
            return result
        }

        // "chip and a putt" / "up and down" patterns
        if lower.contains("chip and a putt") || lower.contains("chip and putt") ||
           lower.contains("up and down") || lower.contains("up-and-down") {
            var chip = Shot(shotNumber: currentShotNumber, isPutt: false)
            chip.result = .green
            var putt = Shot(shotNumber: currentShotNumber + 1, club: .putter, isPutt: true)
            putt.result = .holed
            result.shots = [chip, putt]
            result.putts = 1
            result.confidence = 0.85
            return result
        }

        // "chip and 2 putts" pattern
        if let match = lower.range(of: #"chip.*?(\d|one|two|three)\s*putts?"#, options: .regularExpression) {
            let matchStr = String(lower[match])
            let count = parseNumberWord(matchStr) ?? 2
            var chip = Shot(shotNumber: currentShotNumber, isPutt: false)
            chip.result = .green
            result.shots = [chip]
            result.shots.append(contentsOf: puttShots(count: count, startingAt: currentShotNumber + 1))
            result.putts = count
            result.confidence = 0.85
            return result
        }

        // Parse individual shots from comma/semicolon/then/and-separated segments
        let segments = lower.components(separatedBy: CharacterSet(charactersIn: ",;."))
            .flatMap { $0.components(separatedBy: " then ") }
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var shotNum = currentShotNumber
        for seg in segments {
            let shots = parseShotSegment(seg, shotNumber: shotNum)
            result.shots.append(contentsOf: shots)
            shotNum += shots.count
        }

        // Fairway detection
        if contains(lower, word: "fairway") { result.fairwayHit = true }
        if lower.contains("missed fairway") || lower.contains("miss fairway") ||
           lower.contains("missed the fairway") { result.fairwayHit = false }

        // GIR detection
        if contains(lower, word: "gir") || lower.contains("green in regulation") ||
           lower.contains("green in reg") { result.greenInRegulation = true }
        if lower.contains("missed the green") || lower.contains("missed green") { result.greenInRegulation = false }

        // Also extract putts mentioned anywhere in the input
        if result.putts == nil, let count = puttCount(in: lower) {
            result.putts = count
        }
        // Keep the shot log consistent with the putt count when both are present
        if let putts = result.putts {
            let puttShotCount = result.shots.filter(\.isPutt).count
            if puttShotCount < putts, !result.shots.isEmpty {
                let start = (result.shots.map(\.shotNumber).max() ?? currentShotNumber - 1) + 1
                result.shots.append(contentsOf: puttShots(count: putts - puttShotCount, startingAt: start))
            }
        }

        result.confidence = result.shots.isEmpty ? 0.4 : 0.7
        return result
    }

    // MARK: - Helpers

    /// Lowercase, normalize hyphens/apostrophes so "7-iron" and "7 iron" parse alike.
    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Word-boundary contains, so "ob" never matches inside "lob".
    private func contains(_ text: String, word: String) -> Bool {
        rangeOf(word: word, in: text) != nil
    }

    private func rangeOf(word: String, in text: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return text.range(of: "\\b\(escaped)\\b", options: .regularExpression)
    }

    /// Parse number words that speech recognition might return
    private func parseNumberWord(_ s: String) -> Int? {
        let words: [(String, Int)] = [("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5)]
        for (w, n) in words where contains(s, word: w) { return n }
        if let digit = s.first(where: \.isNumber) { return Int(String(digit)) }
        return nil
    }

    private func puttCount(in text: String) -> Int? {
        guard let match = text.range(of: #"(\d+|one|two|three|four|five)\s*putts?\b"#, options: .regularExpression) else {
            return nil
        }
        return parseNumberWord(String(text[match]))
    }

    /// True when the entire input is just a putt count ("2 putts", "three putt")
    private func wholeInputIsPutts(_ text: String) -> Bool {
        text.range(of: #"^(\d+|one|two|three|four|five)\s*putts?$"#, options: .regularExpression) != nil
    }

    /// Expand a putt count into individual putt shots; the last one holes out.
    private func puttShots(count: Int, startingAt shotNumber: Int) -> [Shot] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            var putt = Shot(shotNumber: shotNumber + i, club: .putter, isPutt: true)
            if i == count - 1 { putt.result = .holed }
            return putt
        }
    }

    private func parseShotSegment(_ seg: String, shotNumber: Int) -> [Shot] {
        // A pure putt segment ("2 putts") expands into that many putt shots
        if wholeInputIsPutts(seg) {
            return puttShots(count: puttCount(in: seg) ?? 1, startingAt: shotNumber)
        }

        var club: Club?
        var remainder = seg
        var matched = false

        // Club: first (longest) alias wins; strip it so its digits can't be
        // mistaken for a distance and "sand wedge" can't read as a bunker.
        for (alias, c) in Self.clubAliases {
            if let range = rangeOf(word: alias, in: remainder) {
                club = c
                matched = true
                remainder.removeSubrange(range)
                break
            }
        }

        // Distance: prefer an explicit "yards" number, else a standalone 2-3 digit
        // number that isn't a degree loft.
        var dist: Int?
        if let match = remainder.range(of: #"\b(\d{1,3})\s*(?:yards?|yds?)\b"#, options: .regularExpression) {
            dist = Int(remainder[match].filter(\.isNumber))
            remainder.removeSubrange(match)
            matched = true
        } else if let match = remainder.range(of: #"\b(\d{2,3})\b(?!\s*(?:degrees?|footer|feet|foot|ft))"#, options: .regularExpression) {
            dist = Int(remainder[match].filter(\.isNumber))
            remainder.removeSubrange(match)
            matched = true
        }

        // Result: where the ball ENDED — when several places are mentioned
        // ("punched out of the trees to the fairway"), the last mention wins.
        var shotResult: ShotResult?
        var bestPos = -1
        for (alias, r) in Self.resultAliases {
            if let range = rangeOf(word: alias, in: remainder) {
                let pos = remainder.distance(from: remainder.startIndex, to: range.lowerBound)
                if pos > bestPos {
                    bestPos = pos
                    shotResult = r
                }
                matched = true
            }
        }

        guard matched else { return [] }

        let isPenalty = contains(seg, word: "penalty")
            || shotResult == .water
            || shotResult == .ob

        let isPutt = club == .putter
        return [Shot(
            shotNumber: shotNumber,
            club: club,
            distanceYards: dist,
            result: shotResult,
            isPenalty: isPenalty,
            isPutt: isPutt
        )]
    }

    private func parseSimpleScore(_ input: String, par: Int) -> (strokes: Int, putts: Int?)? {
        let putts = puttCount(in: input)

        var scorePart = input.replacingOccurrences(of: #"(\d+|one|two|three|four|five)\s*putts?\b"#, with: "", options: .regularExpression)
        // Strip filler so "par with 2 putts" or "made a birdie" still parse
        for filler in ["with", "for", "made", "i had", "had", "got", "shot", " a ", " an "] {
            scorePart = scorePart.replacingOccurrences(of: filler, with: " ")
        }
        scorePart = scorePart.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let strokes: Int?
        switch scorePart {
        case "ace", "hole in one": strokes = 1
        case "albatross", "double eagle": strokes = par - 3
        case "eagle": strokes = par - 2
        case "birdie", "bird": strokes = par - 1
        case "par": strokes = par
        case "bogey", "bogie": strokes = par + 1
        case "double", "double bogey", "double bogie": strokes = par + 2
        case "triple", "triple bogey", "triple bogie": strokes = par + 3
        case "quad", "quadruple bogey": strokes = par + 4
        default:
            if let n = Int(scorePart), (1...15).contains(n) {
                strokes = n
            } else if scorePart.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil,
                      let n = wordScore(scorePart), (1...15).contains(n) {
                strokes = n
            } else {
                strokes = nil
            }
        }

        guard let s = strokes else { return nil }
        return (s, putts)
    }

    /// Speech sometimes returns bare number words ("four" instead of "4")
    private func wordScore(_ s: String) -> Int? {
        let map: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
        ]
        return map[s]
    }
}

# AICaddy Round Simulator

Simulates a human playing full rounds of golf with AICaddy — on Linux/CI, where
Swift and the iOS frameworks aren't available.

```
node parser-tests.js     # 73 table-driven tests of the voice/text shot parser
node simulate.js [N]     # play N rounds per course (default 2) and verify everything
```

## What it does

`caddy-core.js` is a **line-for-line JavaScript mirror** of the app's pure logic:

| JS function | Swift source |
|---|---|
| `distanceYards`, `bearingDegrees` | `Services/LocationService.swift` |
| `adjustedDistance`, `temperatureAdjustment`, `playsLikeDistance` | `Services/WeatherService.swift` |
| `localParse` + helpers | `Services/ShotParserService.swift` |
| `deriveHoleStats`, `calculateStats` | `Models/RoundStats.swift` |
| `makeRecommender`, `standardDistances` | `Services/ClubRecommendationService.swift` |
| `makeAutoAdvance` | `Services/AutoAdvanceService.swift` |
| `calculateHandicapIndex` | `Services/HandicapService.swift` |

**If you change the Swift, change the mirror** (and vice versa). The Xcode test
target `AICaddyTests/CaddyCoreTests.swift` covers the same cases natively.

`simulate.js` then plays seasons at three real East Valley locations
(Western Skies – Gilbert, Ocotillo – Chandler, Ken McDonald – Tempe) with
generated 18-hole routings, and behaves like a person:

- spoofed GPS walking shot-to-shot at walking pace, with ±2–3y GPS jitter
- real shot dispersion, wind physics, desert temperatures (62–105°F)
- speaks each shot in natural phrases ("big dog 260 middle of the fairway",
  "56 degree 80 yards on the green", "2 putts") fed through the same parser
  the app uses; some holes scored as end-of-hole summaries ("bogey 2 putts")
  and some through the Apple Watch quick-score path
- water balls, penalties, chips, and lag putts

Every hole cross-checks the app's recorded score, putts, FIR, and GIR against
ground truth; every walk checks that the distance readout shrinks; every
approach checks the club recommendation is the best available for the
plays-like number; auto-advance must fire at the next tee and stay quiet
mid-hole; the handicap index must compute after 3+ rounds.

A 30-round season runs ~33,000 assertions.

## Bugs this harness caught (all fixed in the app)

1. Temperature adjustment had inverted signs — hot days "played longer".
2. Penalty strokes weren't counted (`strokes = shots.count`).
3. Saying "2 putts" after entering a score overwrote the score with 2.
4. A layup finding the fairway set Fairway-In-Regulation for the hole.

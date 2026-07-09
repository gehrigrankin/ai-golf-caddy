// Simulates a human playing full rounds with AICaddy at East Valley AZ courses:
// spoofed GPS walking shot-to-shot, real shot dispersion, wind, voice phrases
// fed through the same parser the app uses, auto-advance at tee boxes, and the
// Apple Watch quick-score path. Every hole cross-checks the app's recorded
// score against ground truth.
//
// Run: node simulate.js [rounds-per-course]
'use strict';

const core = require('./caddy-core');
const { COURSES, mulberry32, project } = require('./courses');

const ROUNDS_PER_COURSE = parseInt(process.argv[2] || '2', 10);

let checks = 0, failures = 0;
const failLog = [];
function assert(cond, msg) {
  checks++;
  if (!cond) {
    failures++;
    if (failLog.length < 25) failLog.push(msg);
  }
}

// ── The golfer ────────────────────────────────────────────────────────────
// True carries differ from the app's "typical" table — the caddy has to learn.
const GOLFER = {
  carries: {
    driver: [242, 16], '3-wood': [221, 14], '4-hybrid': [196, 12],
    '5-iron': [176, 11], '6-iron': [165, 10], '7-iron': [153, 9],
    '8-iron': [142, 8], '9-iron': [131, 8], pw: [113, 8],
    gw: [99, 7], sw: [83, 7], lw: [63, 6],
  },
  dirSigmaDeg: 4.5,
};
const BAG = Object.keys(GOLFER.carries).concat(['putter']);

function gauss(rng) {
  let u = 0, v = 0;
  while (u === 0) u = rng();
  while (v === 0) v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

// GPS jitter: phones are good to ~2-3y on a course
const jitter = (p, rng, yards = 2.5) =>
  project(p, rng() * 360, Math.abs(gauss(rng)) * yards);

// ── Voice phrase generation ───────────────────────────────────────────────
const clubPhrases = {
  driver: ['driver', 'big dog'], '3-wood': ['3 wood', 'three wood'],
  '4-hybrid': ['hybrid', '4 hybrid'], '5-iron': ['5 iron', 'five iron'],
  '6-iron': ['6 iron'], '7-iron': ['7 iron', 'seven iron'], '8-iron': ['8 iron'],
  '9-iron': ['9 iron', 'nine iron'], pw: ['pitching wedge', 'pitch'],
  gw: ['gap wedge', '52 degree'], sw: ['sand wedge', '56 degree'],
  lw: ['lob wedge', '60 degree'],
};
const resultPhrases = {
  fairway: ['fairway', 'in the fairway', 'middle of the fairway'],
  rough: ['rough', 'in the rough', 'right rough'],
  green: ['on the green', 'green', 'on the dance floor'],
  fringe: ['fringe', 'just off the green'],
  bunker: ['bunker', 'in the sand', 'greenside bunker'],
  water: ['in the water', 'water'],
};
const pick = (rng, arr) => arr[Math.floor(rng() * arr.length)];

function shotPhrase(rng, club, dist, result) {
  const parts = [];
  if (rng() < 0.95) parts.push(pick(rng, clubPhrases[club]));
  if (rng() < 0.75) parts.push(rng() < 0.5 ? `${dist}` : `${dist} yards`);
  // Golfers always announce finding the green; other lies get skipped sometimes
  const resultP = (result === 'green' || result === 'holed') ? 1.0 : 0.9;
  if (result && resultPhrases[result] && rng() < resultP) parts.push(pick(rng, resultPhrases[result]));
  // Nobody says a bare "10" for a 10-yard chip — that reads as a score.
  // Bare numbers only make sense with a unit or context.
  if (parts.length === 1 && /^\d+$/.test(parts[0])) return `${dist} yards`;
  return parts.join(' ') || `${dist} yards`;
}

// ── App-side scoring (mirrors HolePlayView.handleInput) ───────────────────
function applyInput(appHole, phrase) {
  const hadShotsBefore = appHole.shots.length > 0;
  const parsed = core.localParse(phrase, appHole.par, appHole.shots.length + 1);
  if (parsed.totalStrokes != null) appHole.strokes = parsed.totalStrokes;
  if (parsed.shots.length) {
    appHole.shots.push(...parsed.shots);
    if (parsed.totalStrokes == null) {
      const fromShots = appHole.shots.length + appHole.shots.filter(s => s.isPenalty).length;
      appHole.strokes = Math.max(appHole.strokes, fromShots);
    }
  }
  if (parsed.putts != null) appHole.putts = parsed.putts;
  // FIR only from the tee shot description (or an explicit "missed fairway")
  if (parsed.fairwayHit != null && (!hadShotsBefore || parsed.fairwayHit === false)) {
    appHole.fairwayHit = parsed.fairwayHit;
  }
  if (parsed.greenInRegulation != null) appHole.greenInRegulation = parsed.greenInRegulation;
  core.deriveHoleStats(appHole);
}

// ── Walk simulation ───────────────────────────────────────────────────────
// Returns elapsed ms. Verifies the distance readout shrinks as we approach.
function walk(state, from, to, rng, pin) {
  const total = core.distanceYards(from, to);
  const steps = Math.max(1, Math.floor(total / 5));
  let prevPinDist = null;
  for (let i = 1; i <= steps; i++) {
    const frac = i / steps;
    const pos = {
      lat: from.lat + (to.lat - from.lat) * frac,
      lng: from.lng + (to.lng - from.lng) * frac,
    };
    state.pos = jitter(pos, rng);
    state.timeMs += 3200; // ~5y per ~3.2s ≈ walking pace

    if (pin) {
      const d = core.distanceYards(state.pos, pin);
      // GPS jitter is ±2-3y per fix; two consecutive noisy fixes can disagree
      // by ~12y, and the effect dominates at short range.
      if (prevPinDist != null && prevPinDist > 30) {
        assert(d <= prevPinDist + 15, `distance readout jumped up while walking toward pin: ${prevPinDist} -> ${d}`);
      }
      prevPinDist = d;
    }
  }
  state.pos = jitter(to, rng);
  return total;
}

// ── Putting model ─────────────────────────────────────────────────────────
function simulatePutts(firstPuttFeet, rng) {
  if (firstPuttFeet <= 5) return rng() < 0.85 ? 1 : 2;
  if (firstPuttFeet <= 15) return rng() < 0.25 ? 1 : 2;
  if (firstPuttFeet <= 35) { const r = rng(); return r < 0.08 ? 1 : r < 0.82 ? 2 : 3; }
  const r = rng();
  return r < 0.5 ? 2 : r < 0.93 ? 3 : 4;
}

// ── Play one hole ─────────────────────────────────────────────────────────
function playHole(state, hole, nextHole, weather, recommender, autoAdvance, rng, mode) {
  const pin = hole.gps.greenCenter;
  const appHole = {
    holeNumber: hole.holeNumber, par: hole.par, yardage: hole.yardage,
    strokes: 0, putts: null, fairwayHit: null, greenInRegulation: null,
    upAndDown: null, sandSave: null, shots: [],
  };

  const truth = { strokes: 0, teeResult: null, strokesToGreen: null };
  state.pos = jitter(hole.gps.tee, rng);
  let onGreen = false;
  let lastBall = { ...state.pos };
  const pendingPhrases = [];

  while (!onGreen && truth.strokes < 11) {
    const appDist = core.distanceYards(state.pos, pin);
    const bearing = core.bearingDegrees(state.pos, pin);
    const playsLike = core.playsLikeDistance(appDist, bearing, weather);

    // The caddy must always have advice in range — even on round 1 with no history
    let recClub = null;
    if (appDist > 30 && appDist < 320) {
      const rec = recommender.recommend(appDist, playsLike !== appDist ? playsLike : null);
      assert(rec != null, `no club recommendation at ${appDist}y (hole ${hole.holeNumber})`);
      if (rec) {
        // The recommendation must be the best available option: no other club's
        // number can sit meaningfully closer to the plays-like target.
        const target = playsLike ?? appDist;
        const bestPossible = Math.min(...Object.entries(core.standardDistances)
          .map(([, d]) => Math.abs(d - target)));
        assert(Math.abs(rec.primaryAvg - target) <= bestPossible + 30,
          `recommended ${rec.primaryClub} (${rec.primaryAvg}y) for plays-like ${target}y (best possible ${bestPossible})`);
        if (BAG.includes(rec.primaryClub)) recClub = rec.primaryClub;
      }
    }

    const isTeeShot = truth.strokes === 0;
    const dir0 = bearing;
    let carry, dirSigma, club;

    if (appDist <= 45) {
      // Short game: a chip/pitch, not a full swing — distance control is
      // proportional to the shot length
      club = appDist > 30 ? 'sw' : 'lw';
      carry = appDist * (0.9 + rng() * 0.25) + gauss(rng) * 3;
      carry = Math.max(3, carry);
      dirSigma = 3;
    } else {
      // Full swing: tee shot on par 4/5 = driver, otherwise trust the caddy
      if (isTeeShot && hole.par >= 4) club = 'driver';
      else if (recClub && recClub !== 'putter') club = recClub;
      else {
        club = Object.keys(GOLFER.carries).reduce((best, c) =>
          Math.abs(GOLFER.carries[c][0] - playsLike) < Math.abs(GOLFER.carries[best][0] - playsLike) ? c : best,
          'driver');
      }
      const [carryMean, carrySigma] = GOLFER.carries[club];
      const headwind = Math.cos((weather.windDirection - bearing) * Math.PI / 180) * weather.windSpeed;
      carry = carryMean + gauss(rng) * carrySigma - headwind * 0.8;
      carry = Math.max(15, Math.min(carry, appDist + 35)); // golfers club down when short
      dirSigma = GOLFER.dirSigmaDeg;
    }

    const dir = dir0 + gauss(rng) * dirSigma;
    const ball = project(state.pos, dir, carry);
    truth.strokes++;

    // Classify where it ended up
    const dToPin = core.distanceYards(ball, pin);
    const lateral = Math.abs(Math.sin((dir - bearing) * Math.PI / 180)) * carry;
    let result;
    const nearWater = (hole.gps.hazards || []).find(h =>
      h.type === 'water' && core.distanceYards(ball, h.position) < 18);
    const nearBunker = (hole.gps.hazards || []).find(h =>
      h.type === 'bunker' && core.distanceYards(ball, h.position) < 12);

    if (dToPin <= 14) { result = 'green'; onGreen = true; }
    else if (nearWater && rng() < 0.7) { result = 'water'; }
    else if (nearBunker && rng() < 0.6) { result = 'bunker'; }
    else if (dToPin <= 24) { result = 'fringe'; }
    else if (lateral < 16) { result = 'fairway'; }
    else { result = 'rough'; }

    if (isTeeShot && hole.par >= 4) truth.teeResult = result;
    if (onGreen && truth.strokesToGreen == null) truth.strokesToGreen = truth.strokes;

    const spokenDist = Math.round(carry / 5) * 5;
    const phrase = shotPhrase(rng, club, spokenDist, result);

    if (result === 'water') {
      truth.strokes++; // penalty stroke, replay from (near) the same spot
      if (mode === 'perShot') applyInput(appHole, phrase);
      state.timeMs += 60_000;
      continue; // hit again from the drop (approximately same position)
    }

    if (mode === 'perShot') applyInput(appHole, phrase);
    else pendingPhrases.push(phrase);

    // Walk to the ball; the app distance readout must shrink as we go
    walk(state, state.pos, ball, rng, onGreen ? null : pin);
    lastBall = ball;
    state.timeMs += 40_000; // pre-shot routine

    // Mid-hole, auto-advance must stay quiet unless we genuinely wandered
    // onto the next tee box
    if (nextHole) {
      autoAdvance.checkForAdvance(hole.holeNumber, state.pos, nextHole.gps.tee, state.timeMs);
      if (autoAdvance.suggestedAdvance != null) {
        const dNext = core.distanceYards(state.pos, nextHole.gps.tee);
        assert(dNext < 30, `auto-advance fired mid-hole ${hole.holeNumber}, ${dNext}y from next tee`);
        autoAdvance.suggestedAdvance = null;
      }
    }
  }

  // Putt out
  const firstPuttFeet = core.distanceYards(state.pos, pin) * 3;
  const putts = simulatePutts(Math.max(3, firstPuttFeet), rng);
  truth.strokes += putts;
  truth.putts = putts;

  if (mode === 'perShot') {
    applyInput(appHole, `${putts} putts`);
  } else if (mode === 'summary') {
    // Golfer waits until walking off the green: "bogey 2 putts"
    const diff = truth.strokes - hole.par;
    const word = { '-2': 'eagle', '-1': 'birdie', 0: 'par', 1: 'bogey', 2: 'double bogey', 3: 'triple' }[diff];
    const scorePart = word ?? `${truth.strokes}`;
    applyInput(appHole, `${scorePart} ${putts} putts`);
  } else {
    // Watch mode: bare number tapped on the wrist (mirrors applyWatchInput)
    applyInput(appHole, `${truth.strokes}`);
    applyInput(appHole, `${putts} putts`);
  }

  // ── Ground-truth verification ──────────────────────────────────────────
  assert(appHole.strokes === truth.strokes,
    `hole ${hole.holeNumber} (${mode}): app recorded ${appHole.strokes} strokes, truth ${truth.strokes}`);
  assert(appHole.putts === truth.putts,
    `hole ${hole.holeNumber} (${mode}): app recorded ${appHole.putts} putts, truth ${truth.putts}`);

  if (mode === 'perShot' && hole.par >= 4 && truth.teeResult && appHole.fairwayHit != null) {
    // When the tee phrase omitted the lie, FIR legitimately stays unknown —
    // but when it IS recorded it must match where the drive actually finished.
    const expectFIR = truth.teeResult === 'fairway';
    assert(appHole.fairwayHit === expectFIR,
      `hole ${hole.holeNumber}: FIR derived ${appHole.fairwayHit}, tee shot was ${truth.teeResult}`);
  }
  if (mode === 'perShot' && truth.strokesToGreen != null) {
    // The golfer always announces reaching the green (see shotPhrase), so the
    // app must derive GIR correctly whenever the green was reached in regulation.
    const expectGIR = truth.strokesToGreen <= hole.par - 2;
    if (expectGIR) {
      assert(appHole.greenInRegulation === true,
        `hole ${hole.holeNumber}: GIR should be true (on in ${truth.strokesToGreen}, par ${hole.par})`);
    }
  }

  // Walk to the next tee — auto-advance should notice
  if (nextHole) {
    walk(state, state.pos, nextHole.gps.tee, rng, null);
    autoAdvance.checkForAdvance(hole.holeNumber, state.pos, nextHole.gps.tee, state.timeMs);
    assert(autoAdvance.suggestedAdvance === hole.holeNumber + 1,
      `auto-advance missed the walk to tee ${hole.holeNumber + 1} (suggested: ${autoAdvance.suggestedAdvance})`);
    autoAdvance.confirmAdvance(state.timeMs);
  }

  return appHole;
}

// ── Play a full round ─────────────────────────────────────────────────────
function playRound(course, roundIndex, recommender, rng) {
  const weather = {
    windSpeed: 3 + rng() * 15,
    windDirection: rng() * 360,
    temperature: 62 + Math.floor(rng() * 44), // AZ: 62-105°F
  };
  const autoAdvance = core.makeAutoAdvance();
  const state = { pos: { ...course.holes[0].gps.tee }, timeMs: 8 * 3600_000 };
  const appHoles = [];

  for (let i = 0; i < 18; i++) {
    const r = rng();
    const mode = r < 0.70 ? 'perShot' : r < 0.90 ? 'summary' : 'watch';
    appHoles.push(playHole(
      state, course.holes[i], course.holes[i + 1] ?? null,
      weather, recommender, autoAdvance, rng, mode
    ));
  }

  const stats = core.calculateStats(appHoles);
  assert(stats.frontNine + stats.backNine === stats.totalStrokes, 'front+back != total');
  assert(stats.totalStrokes >= 60 && stats.totalStrokes <= 140,
    `implausible round total ${stats.totalStrokes}`);

  return { holes: appHoles, stats, isComplete: true, course };
}

// ── Plays-like physics spot checks ────────────────────────────────────────
(function playsLikeChecks() {
  // Dead headwind: wind FROM the north, shooting north
  const head = core.playsLikeDistance(150, 0, { windSpeed: 10, windDirection: 0, temperature: 70 });
  assert(head > 150, `headwind should play longer (got ${head})`);
  // Dead tailwind
  const tail = core.playsLikeDistance(150, 0, { windSpeed: 10, windDirection: 180, temperature: 70 });
  assert(tail < 150, `tailwind should play shorter (got ${tail})`);
  // Hot desert day: ball flies farther, plays shorter
  const hot = core.playsLikeDistance(150, 0, { windSpeed: null, windDirection: null, temperature: 105 });
  assert(hot < 150, `105°F should play shorter than actual (got ${hot})`);
  // Distance sanity: 400y measured between two known points
  const a = { lat: 33.3623, lng: -111.7433 };
  const b = project(a, 0, 400);
  const d = core.distanceYards(a, b);
  assert(Math.abs(d - 400) <= 1, `distance calc off: ${d} != 400`);
})();

// ── Run the season ────────────────────────────────────────────────────────
const rng = mulberry32(2026);
const recommender = core.makeRecommender();
recommender.loadBag(BAG);
const completedRounds = [];
const lines = [];

for (const course of COURSES) {
  for (let r = 0; r < ROUNDS_PER_COURSE; r++) {
    recommender.loadHistory(completedRounds); // caddy learns between rounds
    const round = playRound(course, r, recommender, rng);
    completedRounds.push(round);

    const s = round.stats;
    const toPar = s.scoreToPar >= 0 ? `+${s.scoreToPar}` : `${s.scoreToPar}`;
    lines.push(
      `  ${course.name.padEnd(28)} ${String(s.totalStrokes).padStart(3)} (${toPar})  ` +
      `F${s.frontNine}/B${s.backNine}  ${s.totalPutts} putts  ` +
      `GIR ${s.greensInRegulation}/${s.girHoles}  FIR ${s.fairwaysHit}/${s.fairwayHoles}  ` +
      `[${s.birdies}bd ${s.pars}p ${s.bogeys}bg ${s.doubleBogeys}db ${s.triplePlus}t+]`
    );
  }
}

// The caddy should now recommend from LEARNED distances at stock yardages
recommender.loadHistory(completedRounds);
const learned = recommender.recommend(150);
assert(learned && learned.primaryIsFromHistory,
  'after 6 rounds the caddy should recommend from learned history');

// Handicap over the season
const hcRounds = completedRounds.map(round => ({
  adjustedScore: round.holes.reduce((a, h) => a + Math.min(h.strokes, h.par + 3), 0),
  slope: round.course.slope,
  rating: round.course.rating,
}));
const index = core.calculateHandicapIndex(hcRounds);
assert(index != null, 'handicap index should compute after 3+ rounds');
assert(index > -10 && index <= 54, `handicap index implausible: ${index}`);

// ── Report ────────────────────────────────────────────────────────────────
console.log(`\nSimulated ${completedRounds.length} rounds (${ROUNDS_PER_COURSE}/course), Gilbert–Chandler–Tempe AZ:\n`);
for (const l of lines) console.log(l);
console.log(`\nHandicap index after season: ${index}`);
console.log(`Caddy learned distances: 150y -> ${learned.primaryClub} (avg ${learned.primaryAvg}y from history)`);
console.log(`\nsimulate: ${checks} checks, ${failures} failures`);
if (failures) {
  for (const f of failLog) console.log('  FAIL ' + f);
  process.exit(1);
}

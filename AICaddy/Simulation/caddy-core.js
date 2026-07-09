// Faithful JavaScript mirror of AICaddy's core Swift logic, used to simulate
// full rounds of golf on CI/Linux where Swift + iOS frameworks aren't available.
//
// IMPORTANT: every function here mirrors a Swift counterpart 1:1. If you change
// the Swift, change this file, and vice versa:
//   distanceYards / bearingDegrees   -> Services/LocationService.swift
//   adjustedDistance / tempAdjust /
//   playsLikeDistance                -> Services/WeatherService.swift
//   localParse + helpers             -> Services/ShotParserService.swift
//   deriveHoleStats / calculate      -> Models/RoundStats.swift
//   recommend / standardDistances    -> Services/ClubRecommendationService.swift
//   checkForAdvance                  -> Services/AutoAdvanceService.swift
//   calculateIndex                   -> Services/HandicapService.swift

'use strict';

// Swift's .rounded() rounds half away from zero; JS Math.round rounds half up.
const swiftRound = (x) => Math.sign(x) * Math.round(Math.abs(x));
const toInt = Math.trunc; // Swift Int(double) truncates toward zero

// MARK: - LocationService

function distanceYards(a, b) {
  const R = 6371000.0 / 0.9144;
  const dLat = (b.lat - a.lat) * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h = sinLat * sinLat +
    Math.cos(a.lat * Math.PI / 180) * Math.cos(b.lat * Math.PI / 180) * sinLng * sinLng;
  return toInt(2 * R * Math.asin(Math.sqrt(h)));
}

function bearingDegrees(a, b) {
  const lat1 = a.lat * Math.PI / 180;
  const lat2 = b.lat * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  const bearing = Math.atan2(y, x) * 180 / Math.PI;
  return (bearing + 360) % 360;
}

// MARK: - WeatherService

function adjustedDistance(yards, shotBearing, windSpeed, windDirection) {
  if (windSpeed == null || windDirection == null) return yards;
  const angleDiff = (windDirection - shotBearing) * Math.PI / 180;
  const headwind = Math.cos(angleDiff) * windSpeed;
  const crosswind = Math.abs(Math.sin(angleDiff) * windSpeed);
  let adjustment = headwind > 0 ? headwind * 1.0 : headwind * 0.5;
  adjustment += crosswind * 0.2;
  return yards + toInt(swiftRound(adjustment));
}

function temperatureAdjustment(yards, temperature) {
  if (temperature == null) return yards;
  const diff = temperature - 70;
  if (diff < 0) return yards - toInt(swiftRound(diff / 10.0 * 2.0)); // cold → plays longer
  return yards - toInt(swiftRound(diff / 10.0 * 1.0));               // hot → plays shorter
}

function playsLikeDistance(yards, shotBearing, weather) {
  const windAdjusted = adjustedDistance(yards, shotBearing, weather.windSpeed, weather.windDirection);
  const delta = windAdjusted - yards;
  return temperatureAdjustment(yards, weather.temperature) + delta;
}

// MARK: - ShotParserService (local parser)

const CLUBS = [
  'driver', '3-wood', '5-wood', '7-wood',
  '2-hybrid', '3-hybrid', '4-hybrid', '5-hybrid',
  '2-iron', '3-iron', '4-iron', '5-iron', '6-iron', '7-iron', '8-iron', '9-iron',
  'pw', 'gw', 'sw', 'lw', 'putter',
];

const clubAliases = [
  ['pitching wedge', 'pw'], ['gap wedge', 'gw'], ['sand wedge', 'sw'], ['lob wedge', 'lw'],
  ['52 degree', 'gw'], ['fifty two degree', 'gw'],
  ['56 degree', 'sw'], ['fifty six degree', 'sw'],
  ['58 degree', 'lw'], ['fifty eight degree', 'lw'],
  ['60 degree', 'lw'], ['sixty degree', 'lw'],
  ['3 wood', '3-wood'], ['3wood', '3-wood'], ['three wood', '3-wood'],
  ['5 wood', '5-wood'], ['5wood', '5-wood'], ['five wood', '5-wood'],
  ['7 wood', '7-wood'], ['7wood', '7-wood'], ['seven wood', '7-wood'],
  ['2 hybrid', '2-hybrid'], ['two hybrid', '2-hybrid'],
  ['3 hybrid', '3-hybrid'], ['three hybrid', '3-hybrid'],
  ['4 hybrid', '4-hybrid'], ['four hybrid', '4-hybrid'],
  ['5 hybrid', '5-hybrid'], ['five hybrid', '5-hybrid'],
  ['hybrid', '4-hybrid'], ['rescue', '4-hybrid'],
  ['2 iron', '2-iron'], ['two iron', '2-iron'],
  ['3 iron', '3-iron'], ['three iron', '3-iron'],
  ['4 iron', '4-iron'], ['four iron', '4-iron'],
  ['5 iron', '5-iron'], ['five iron', '5-iron'],
  ['6 iron', '6-iron'], ['six iron', '6-iron'],
  ['7 iron', '7-iron'], ['seven iron', '7-iron'],
  ['8 iron', '8-iron'], ['eight iron', '8-iron'],
  ['9 iron', '9-iron'], ['nine iron', '9-iron'],
  ['driver', 'driver'], ['big dog', 'driver'], ['big stick', 'driver'], ['drive', 'driver'],
  ['pitch', 'pw'], ['pw', 'pw'], ['gw', 'gw'], ['sw', 'sw'], ['lw', 'lw'], ['lob', 'lw'],
  ['putter', 'putter'], ['putted', 'putter'], ['putting', 'putter'], ['putt', 'putter'],
];

const resultAliases = [
  ['middle of the fairway', 'fairway'], ['split the fairway', 'fairway'],
  ['found the fairway', 'fairway'], ['in the fairway', 'fairway'],
  ['hit fairway', 'fairway'], ['fairway', 'fairway'],
  ['deep rough', 'deep-rough'], ['thick rough', 'deep-rough'], ['heavy rough', 'deep-rough'],
  ['in the rough', 'rough'], ['left rough', 'rough'], ['right rough', 'rough'],
  ['first cut', 'rough'], ['light rough', 'rough'], ['rough', 'rough'],
  ['greenside bunker', 'bunker'], ['fairway bunker', 'bunker'], ['sand trap', 'bunker'],
  ['in the sand', 'bunker'], ['bunker', 'bunker'], ['trap', 'bunker'],
  ['beach', 'bunker'], ['sand', 'bunker'],
  ['in the water', 'water'], ['water', 'water'], ['hazard', 'water'], ['wet', 'water'],
  ['lake', 'water'], ['pond', 'water'], ['creek', 'water'], ['drink', 'water'],
  ['out of bounds', 'ob'], ['o.b.', 'ob'], ['o b', 'ob'], ['ob', 'ob'],
  ['on the dance floor', 'green'], ['green in regulation', 'green'],
  ['hit the green', 'green'], ['found the green', 'green'],
  ['on the green', 'green'], ['on green', 'green'], ['pin high', 'green'],
  ['green', 'green'], ['gir', 'green'],
  ['just off the green', 'fringe'], ['on the fringe', 'fringe'],
  ['fringe', 'fringe'], ['collar', 'fringe'], ['apron', 'fringe'],
  ['in the trees', 'trees'], ['trees', 'trees'], ['woods', 'trees'],
  ['punch out', 'recovery'], ['chip out', 'recovery'], ['punched out', 'recovery'],
  ['punch', 'recovery'], ['recovery', 'recovery'],
  ['hole in one', 'holed'], ['holed out', 'holed'], ['holed', 'holed'],
  ['jarred it', 'holed'], ['drained it', 'holed'], ['in the hole', 'holed'],
];

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const wordRe = (w) => new RegExp(`\\b${escapeRe(w)}\\b`);
const containsWord = (text, word) => wordRe(word).test(text);

function normalize(s) {
  return s.toLowerCase().replace(/-/g, ' ').replace(/’/g, "'").trim();
}

function parseNumberWord(s) {
  const words = [['one', 1], ['two', 2], ['three', 3], ['four', 4], ['five', 5]];
  for (const [w, n] of words) if (containsWord(s, w)) return n;
  const digit = s.match(/\d/);
  return digit ? parseInt(digit[0], 10) : null;
}

function puttCount(text) {
  const m = text.match(/(\d+|one|two|three|four|five)\s*putts?\b/);
  return m ? parseNumberWord(m[0]) : null;
}

function wholeInputIsPutts(text) {
  return /^(\d+|one|two|three|four|five)\s*putts?$/.test(text);
}

function puttShots(count, startingAt) {
  const shots = [];
  for (let i = 0; i < count; i++) {
    shots.push({
      shotNumber: startingAt + i, club: 'putter', distanceYards: null,
      result: i === count - 1 ? 'holed' : null, isPenalty: false, isPutt: true,
    });
  }
  return shots;
}

function parseShotSegment(seg, shotNumber) {
  if (wholeInputIsPutts(seg)) {
    return puttShots(puttCount(seg) ?? 1, shotNumber);
  }

  let club = null;
  let remainder = seg;
  let matched = false;

  for (const [alias, c] of clubAliases) {
    const m = remainder.match(wordRe(alias));
    if (m) {
      club = c;
      matched = true;
      remainder = remainder.slice(0, m.index) + remainder.slice(m.index + m[0].length);
      break;
    }
  }

  let dist = null;
  let m = remainder.match(/\b(\d{1,3})\s*(?:yards?|yds?)\b/);
  if (m) {
    dist = parseInt(m[1], 10);
    remainder = remainder.slice(0, m.index) + remainder.slice(m.index + m[0].length);
    matched = true;
  } else {
    m = remainder.match(/\b(\d{2,3})\b(?!\s*(?:degrees?|footer|feet|foot|ft))/);
    if (m) {
      dist = parseInt(m[1], 10);
      remainder = remainder.slice(0, m.index) + remainder.slice(m.index + m[0].length);
      matched = true;
    }
  }

  let shotResult = null;
  let bestPos = -1;
  for (const [alias, r] of resultAliases) {
    const rm = remainder.match(wordRe(alias));
    if (rm) {
      if (rm.index > bestPos) {
        bestPos = rm.index;
        shotResult = r;
      }
      matched = true;
    }
  }

  if (!matched) return [];

  const isPenalty = containsWord(seg, 'penalty') || shotResult === 'water' || shotResult === 'ob';
  return [{
    shotNumber, club, distanceYards: dist, result: shotResult,
    isPenalty, isPutt: club === 'putter',
  }];
}

function wordScore(s) {
  const map = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12 };
  return map[s] ?? null;
}

function parseSimpleScore(input, par) {
  const putts = puttCount(input);
  let scorePart = input.replace(/(\d+|one|two|three|four|five)\s*putts?\b/, '');
  for (const filler of ['with', 'for', 'made', 'i had', 'had', 'got', 'shot', ' a ', ' an ']) {
    scorePart = scorePart.split(filler).join(' ');
  }
  scorePart = scorePart.replace(/\s+/g, ' ').trim();

  let strokes = null;
  switch (scorePart) {
    case 'ace': case 'hole in one': strokes = 1; break;
    case 'albatross': case 'double eagle': strokes = par - 3; break;
    case 'eagle': strokes = par - 2; break;
    case 'birdie': case 'bird': strokes = par - 1; break;
    case 'par': strokes = par; break;
    case 'bogey': case 'bogie': strokes = par + 1; break;
    case 'double': case 'double bogey': case 'double bogie': strokes = par + 2; break;
    case 'triple': case 'triple bogey': case 'triple bogie': strokes = par + 3; break;
    case 'quad': case 'quadruple bogey': strokes = par + 4; break;
    default: {
      const n = /^\d+$/.test(scorePart) ? parseInt(scorePart, 10) : null;
      if (n != null && n >= 1 && n <= 15) strokes = n;
      else if (/^[a-z]+$/.test(scorePart)) {
        const w = wordScore(scorePart);
        if (w != null && w >= 1 && w <= 15) strokes = w;
      }
    }
  }
  if (strokes == null) return null;
  return { strokes, putts };
}

function localParse(input, par, currentShotNumber) {
  const lower = normalize(input);
  const result = { shots: [], putts: null, totalStrokes: null, fairwayHit: null, greenInRegulation: null, confidence: 0.6 };

  const simple = parseSimpleScore(lower, par);
  if (simple) {
    result.totalStrokes = simple.strokes;
    result.putts = simple.putts;
    result.confidence = 0.8;
    return result;
  }

  if (wholeInputIsPutts(lower)) {
    const count = puttCount(lower) ?? 2;
    result.putts = count;
    result.shots = puttShots(count, currentShotNumber);
    result.confidence = 0.9;
    return result;
  }

  if (lower.includes('chip and a putt') || lower.includes('chip and putt') ||
      lower.includes('up and down') || lower.includes('up-and-down')) {
    result.shots = [
      { shotNumber: currentShotNumber, club: null, distanceYards: null, result: 'green', isPenalty: false, isPutt: false },
      { shotNumber: currentShotNumber + 1, club: 'putter', distanceYards: null, result: 'holed', isPenalty: false, isPutt: true },
    ];
    result.putts = 1;
    result.confidence = 0.85;
    return result;
  }

  const chipMatch = lower.match(/chip.*?(\d|one|two|three)\s*putts?/);
  if (chipMatch) {
    const count = parseNumberWord(chipMatch[0]) ?? 2;
    result.shots = [{ shotNumber: currentShotNumber, club: null, distanceYards: null, result: 'green', isPenalty: false, isPutt: false }];
    result.shots.push(...puttShots(count, currentShotNumber + 1));
    result.putts = count;
    result.confidence = 0.85;
    return result;
  }

  const segments = lower.split(/[,;.]/)
    .flatMap(s => s.split(' then '))
    .flatMap(s => s.split(' and '))
    .map(s => s.trim())
    .filter(s => s.length > 0);

  let shotNum = currentShotNumber;
  for (const seg of segments) {
    const shots = parseShotSegment(seg, shotNum);
    result.shots.push(...shots);
    shotNum += shots.length;
  }

  if (containsWord(lower, 'fairway')) result.fairwayHit = true;
  if (lower.includes('missed fairway') || lower.includes('miss fairway') ||
      lower.includes('missed the fairway')) result.fairwayHit = false;

  if (containsWord(lower, 'gir') || lower.includes('green in regulation') ||
      lower.includes('green in reg')) result.greenInRegulation = true;
  if (lower.includes('missed the green') || lower.includes('missed green')) result.greenInRegulation = false;

  if (result.putts == null) {
    const count = puttCount(lower);
    if (count != null) result.putts = count;
  }
  if (result.putts != null) {
    const puttShotCount = result.shots.filter(s => s.isPutt).length;
    if (puttShotCount < result.putts && result.shots.length > 0) {
      const start = Math.max(...result.shots.map(s => s.shotNumber)) + 1;
      result.shots.push(...puttShots(result.putts - puttShotCount, start));
    }
  }

  result.confidence = result.shots.length === 0 ? 0.4 : 0.7;
  return result;
}

// MARK: - StatsCalculator

function deriveHoleStats(hole) {
  const shots = hole.shots;
  if (!shots.length) return;

  const puttCountShots = shots.filter(s => s.isPutt).length;
  if (puttCountShots > 0 && hole.putts == null) hole.putts = puttCountShots;

  if (hole.par >= 4 && hole.fairwayHit == null) {
    const teeShot = shots.find(s => s.shotNumber === 1);
    if (teeShot && teeShot.result != null) {
      hole.fairwayHit = teeShot.result === 'fairway';
    }
  }

  if (hole.greenInRegulation == null) {
    const girTarget = hole.par - 2;
    const hitGreen = shots.find(s => (s.result === 'green' || s.result === 'holed') && s.shotNumber <= girTarget);
    if (hitGreen) {
      hole.greenInRegulation = true;
    } else if (shots.length >= girTarget) {
      const anyGreen = shots.filter(s => s.shotNumber <= girTarget)
        .some(s => s.result === 'green' || s.result === 'holed');
      if (!anyGreen) hole.greenInRegulation = false;
    }
  }

  if (hole.greenInRegulation === false && hole.upAndDown == null && hole.strokes > 0) {
    hole.upAndDown = hole.strokes <= hole.par;
  }

  if (hole.greenInRegulation === false && hole.sandSave == null) {
    const hitBunker = shots.some(s => s.result === 'bunker' && !s.isPutt);
    if (hitBunker && hole.strokes > 0) {
      hole.sandSave = hole.strokes <= hole.par;
    }
  }
}

function calculateStats(holes) {
  const played = holes.filter(h => h.strokes > 0);
  const totalStrokes = played.reduce((a, h) => a + h.strokes, 0);
  const totalPar = played.reduce((a, h) => a + h.par, 0);
  const holesWithPutts = played.filter(h => h.putts != null);
  const totalPutts = holesWithPutts.reduce((a, h) => a + h.putts, 0);
  const girHoles = played.filter(h => h.greenInRegulation != null);
  const gir = girHoles.filter(h => h.greenInRegulation === true).length;
  const fairwayHoles = played.filter(h => h.par >= 4 && h.fairwayHit != null);
  const fairwaysHit = fairwayHoles.filter(h => h.fairwayHit === true).length;
  const diffs = played.map(h => h.strokes - h.par);
  return {
    totalStrokes, totalPar, scoreToPar: totalStrokes - totalPar,
    frontNine: played.filter(h => h.holeNumber <= 9).reduce((a, h) => a + h.strokes, 0),
    backNine: played.filter(h => h.holeNumber > 9).reduce((a, h) => a + h.strokes, 0),
    totalPutts,
    oneputts: holesWithPutts.filter(h => h.putts === 1).length,
    threeputts: holesWithPutts.filter(h => h.putts >= 3).length,
    greensInRegulation: gir, girHoles: girHoles.length,
    fairwaysHit, fairwayHoles: fairwayHoles.length,
    eagles: diffs.filter(d => d <= -2).length,
    birdies: diffs.filter(d => d === -1).length,
    pars: diffs.filter(d => d === 0).length,
    bogeys: diffs.filter(d => d === 1).length,
    doubleBogeys: diffs.filter(d => d === 2).length,
    triplePlus: diffs.filter(d => d >= 3).length,
  };
}

// MARK: - ClubRecommendationService

const standardDistances = {
  driver: 230, '3-wood': 215, '5-wood': 205, '7-wood': 195,
  '2-hybrid': 210, '3-hybrid': 200, '4-hybrid': 190, '5-hybrid': 180,
  '2-iron': 200, '3-iron': 190, '4-iron': 180, '5-iron': 170, '6-iron': 160,
  '7-iron': 150, '8-iron': 140, '9-iron': 130,
  pw: 115, gw: 100, sw: 85, lw: 70,
};

function makeRecommender() {
  let clubHistory = {};
  let bagClubs = [];
  return {
    loadHistory(rounds) {
      clubHistory = {};
      for (const round of rounds) {
        if (!round.isComplete) continue;
        for (const hole of round.holes) {
          for (const shot of hole.shots) {
            if (shot.isPutt || shot.isPenalty) continue;
            if (shot.club && shot.distanceYards > 0) {
              (clubHistory[shot.club] ??= []).push(shot.distanceYards);
            }
          }
        }
      }
    },
    loadBag(clubs) { bagClubs = clubs ?? []; },
    recommend(distanceYards, playsLikeYards = null) {
      const target = playsLikeYards ?? distanceYards;
      const clubs = new Set(Object.keys(clubHistory));
      if (bagClubs.length === 0) {
        Object.keys(standardDistances).forEach(c => clubs.add(c));
      } else {
        bagClubs.forEach(c => clubs.add(c));
      }
      clubs.delete('putter');

      const candidates = [];
      for (const club of clubs) {
        const distances = clubHistory[club] ?? [];
        if (distances.length >= 2) {
          const avg = toInt(distances.reduce((a, b) => a + b, 0) / distances.length);
          candidates.push({ club, avg, count: distances.length, diff: Math.abs(avg - target), fromHistory: true });
        } else if (standardDistances[club] != null) {
          candidates.push({ club, avg: standardDistances[club], count: 0, diff: Math.abs(standardDistances[club] - target), fromHistory: false });
        }
      }
      if (!candidates.length) return null;
      candidates.sort((a, b) => a.diff !== b.diff ? a.diff - b.diff : (b.fromHistory ? 1 : 0) - (a.fromHistory ? 1 : 0));
      return {
        primaryClub: candidates[0].club,
        primaryAvg: candidates[0].avg,
        primaryIsFromHistory: candidates[0].fromHistory,
        alternateClub: candidates[1]?.club ?? null,
        targetDistance: distanceYards,
        playsLikeDistance: playsLikeYards,
      };
    },
  };
}

// MARK: - AutoAdvanceService

function makeAutoAdvance() {
  let lastAdvanceTime = null;
  return {
    isEnabled: true,
    suggestedAdvance: null,
    checkForAdvance(currentHole, userLocation, nextTeebox, nowMs) {
      if (!this.isEnabled || !nextTeebox) { this.suggestedAdvance = null; return; }
      if (lastAdvanceTime != null && (nowMs - lastAdvanceTime) < 120000) return;
      const dist = distanceYards(userLocation, nextTeebox);
      if (dist < 30 && currentHole < 18) {
        this.suggestedAdvance = currentHole + 1;
      } else {
        this.suggestedAdvance = null;
      }
    },
    confirmAdvance(nowMs) { lastAdvanceTime = nowMs; this.suggestedAdvance = null; },
  };
}

// MARK: - HandicapCalculator

function calculateHandicapIndex(rounds) {
  if (rounds.length < 3) return null;
  const differentials = rounds
    .filter(r => r.slope != null && r.rating != null && r.slope > 0)
    .map(r => (113.0 / r.slope) * (r.adjustedScore - r.rating));
  if (differentials.length < 3) return null;
  const sorted = [...differentials].sort((a, b) => a - b);
  const n = sorted.length;
  let useCount;
  if (n <= 5) useCount = 1;
  else if (n <= 8) useCount = 2;
  else if (n <= 11) useCount = 3;
  else if (n <= 14) useCount = 4;
  else if (n <= 16) useCount = 5;
  else if (n <= 18) useCount = 6;
  else if (n === 19) useCount = 7;
  else useCount = 8;
  const best = sorted.slice(0, useCount);
  const avg = best.reduce((a, b) => a + b, 0) / best.length;
  const index = avg * 0.96;
  return Math.min(54.0, swiftRound(index * 10) / 10);
}

module.exports = {
  swiftRound, distanceYards, bearingDegrees,
  adjustedDistance, temperatureAdjustment, playsLikeDistance,
  localParse, deriveHoleStats, calculateStats,
  makeRecommender, standardDistances, makeAutoAdvance,
  calculateHandicapIndex,
};

import { ParsedShotInput, Shot, Club, ShotResult } from '@/types/golf';
import { generateId } from './utils';

/**
 * Parse natural language shot input into structured data.
 * Uses Claude API on the server, but falls back to local regex parsing
 * when offline or for simple inputs.
 */
export async function parseShotInput(
  input: string,
  holeContext: { holeNumber: number; par: number; yardage?: number; currentShotNumber: number }
): Promise<ParsedShotInput> {
  // Try the AI parser first (via API route)
  try {
    const response = await fetch('/api/parse-shot', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input, context: holeContext }),
    });

    if (response.ok) {
      return await response.json();
    }
  } catch {
    // Offline or API error — fall through to local parser
  }

  // Local fallback parser
  return localParseShotInput(input, holeContext);
}

// ============================================================
// Local regex-based parser (works offline)
// ============================================================

const CLUB_ALIASES: Record<string, Club> = {
  driver: 'driver',
  '3 wood': '3-wood', '3wood': '3-wood', 'three wood': '3-wood',
  '5 wood': '5-wood', '5wood': '5-wood', 'five wood': '5-wood',
  '7 wood': '7-wood', '7wood': '7-wood', 'seven wood': '7-wood',
  '2 hybrid': '2-hybrid', '2hybrid': '2-hybrid',
  '3 hybrid': '3-hybrid', '3hybrid': '3-hybrid',
  '4 hybrid': '4-hybrid', '4hybrid': '4-hybrid',
  '5 hybrid': '5-hybrid', '5hybrid': '5-hybrid',
  '2 iron': '2-iron', '2iron': '2-iron',
  '3 iron': '3-iron', '3iron': '3-iron',
  '4 iron': '4-iron', '4iron': '4-iron',
  '5 iron': '5-iron', '5iron': '5-iron',
  '6 iron': '6-iron', '6iron': '6-iron',
  '7 iron': '7-iron', '7iron': '7-iron',
  '8 iron': '8-iron', '8iron': '8-iron',
  '9 iron': '9-iron', '9iron': '9-iron',
  'pitching wedge': 'pw', pw: 'pw',
  'gap wedge': 'gw', gw: 'gw',
  'sand wedge': 'sw', sw: 'sw',
  'lob wedge': 'lw', lw: 'lw',
  putter: 'putter', putt: 'putter',
};

const RESULT_ALIASES: Record<string, ShotResult> = {
  fairway: 'fairway', 'in the fairway': 'fairway', 'hit fairway': 'fairway',
  rough: 'rough', 'in the rough': 'rough',
  'deep rough': 'deep-rough',
  bunker: 'bunker', sand: 'bunker', trap: 'bunker', 'sand trap': 'bunker',
  water: 'water', 'in the water': 'water', hazard: 'water',
  ob: 'ob', 'out of bounds': 'ob', 'o.b.': 'ob',
  green: 'green', 'on the green': 'green', 'on green': 'green', 'hit the green': 'green',
  'pin high': 'green',
  fringe: 'fringe',
  trees: 'trees', 'in the trees': 'trees',
  holed: 'holed', 'hole in one': 'holed', 'holed out': 'holed',
};

export function localParseShotInput(
  input: string,
  context: { holeNumber: number; par: number; yardage?: number; currentShotNumber: number }
): ParsedShotInput {
  const lower = input.toLowerCase().trim();
  const result: ParsedShotInput = { shots: [], confidence: 0.6 };

  // Check for simple score-only input: "4", "bogey", "par", "birdie 2 putts"
  const simpleScore = parseSimpleScore(lower, context.par);
  if (simpleScore !== null) {
    result.totalStrokes = simpleScore.strokes;
    result.putts = simpleScore.putts;
    result.confidence = 0.8;
    return result;
  }

  // Check for putts-only input: "2 putts", "3 putt"
  const puttsMatch = lower.match(/(\d)\s*putts?/);
  if (puttsMatch && lower.length < 15) {
    result.putts = parseInt(puttsMatch[1]);
    result.confidence = 0.9;
    return result;
  }

  // Parse individual shots from comma-separated or natural language
  const segments = lower.split(/[,;]|then|and then/).map((s) => s.trim()).filter(Boolean);

  let shotNum = context.currentShotNumber;
  for (const seg of segments) {
    const shot = parseShotSegment(seg, shotNum);
    if (shot) {
      result.shots.push(shot);
      shotNum++;
    }
  }

  // If we found no shots but there's a single segment, try parsing it as one shot
  if (result.shots.length === 0 && segments.length === 1) {
    const shot = parseShotSegment(lower, context.currentShotNumber);
    if (shot) {
      result.shots.push(shot);
    }
  }

  // Extract fairway info
  if (lower.includes('fairway')) result.fairwayHit = true;
  if (lower.includes('missed fairway') || lower.includes('miss fairway')) result.fairwayHit = false;

  // Extract GIR info
  if (lower.includes('gir') || lower.includes('green in reg')) result.greenInRegulation = true;

  result.confidence = result.shots.length > 0 ? 0.7 : 0.4;
  return result;
}

function parseShotSegment(
  seg: string,
  shotNumber: number
): Partial<Shot> | null {
  const shot: Partial<Shot> = { id: generateId(), shotNumber };

  let matched = false;

  // Find club
  for (const [alias, club] of Object.entries(CLUB_ALIASES)) {
    if (seg.includes(alias)) {
      shot.club = club;
      if (club === 'putter') shot.isPutt = true;
      matched = true;
      break;
    }
  }

  // Find distance
  const distMatch = seg.match(/(\d{2,3})\s*(?:yards?|yds?)?/);
  if (distMatch) {
    shot.distanceYards = parseInt(distMatch[1]);
    matched = true;
  }

  // Find result
  for (const [alias, result] of Object.entries(RESULT_ALIASES)) {
    if (seg.includes(alias)) {
      shot.result = result;
      matched = true;
      break;
    }
  }

  // Check for penalty
  if (seg.includes('penalty') || seg.includes('water') || seg.includes('ob') || seg.includes('out of bounds')) {
    shot.isPenalty = true;
  }

  return matched ? shot : null;
}

function parseSimpleScore(
  input: string,
  par: number
): { strokes: number; putts?: number } | null {
  let strokes: number | null = null;
  let putts: number | undefined;

  // Extract putts if mentioned
  const puttsMatch = input.match(/(\d)\s*putts?/);
  if (puttsMatch) putts = parseInt(puttsMatch[1]);

  // Remove putts part for score parsing
  const scorePart = input.replace(/\d\s*putts?/, '').trim();

  // Named scores
  if (scorePart === 'ace' || scorePart === 'hole in one') strokes = 1;
  else if (scorePart === 'albatross' || scorePart === 'double eagle') strokes = par - 3;
  else if (scorePart === 'eagle') strokes = par - 2;
  else if (scorePart === 'birdie') strokes = par - 1;
  else if (scorePart === 'par') strokes = par;
  else if (scorePart === 'bogey') strokes = par + 1;
  else if (scorePart === 'double' || scorePart === 'double bogey') strokes = par + 2;
  else if (scorePart === 'triple' || scorePart === 'triple bogey') strokes = par + 3;
  // Just a number
  else if (/^\d$/.test(scorePart)) strokes = parseInt(scorePart);

  if (strokes !== null) return { strokes, putts };
  return null;
}

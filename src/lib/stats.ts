import { Round, RoundStats, HoleScore, Club } from '@/types/golf';

export function calculateRoundStats(round: Round): RoundStats {
  const holes = round.holes.filter((h) => h.strokes > 0);

  const totalStrokes = holes.reduce((s, h) => s + h.strokes, 0);
  const totalPar = holes.reduce((s, h) => s + h.par, 0);

  const front = holes.filter((h) => h.holeNumber <= 9);
  const back = holes.filter((h) => h.holeNumber > 9);

  // Putting
  const holesWithPutts = holes.filter((h) => h.putts != null);
  const totalPutts = holesWithPutts.reduce((s, h) => s + (h.putts ?? 0), 0);
  const oneputts = holesWithPutts.filter((h) => h.putts === 1).length;
  const threeputts = holesWithPutts.filter((h) => (h.putts ?? 0) >= 3).length;

  // GIR
  const girHoles = holes.filter((h) => h.greenInRegulation != null);
  const gir = girHoles.filter((h) => h.greenInRegulation === true).length;

  // Fairways (only par 4+ holes)
  const fairwayHoles = holes.filter((h) => h.par >= 4 && h.fairwayHit != null);
  const fairwaysHit = fairwayHoles.filter((h) => h.fairwayHit === true).length;

  // Up and downs (only when missed GIR)
  const upDownHoles = holes.filter((h) => h.upAndDown != null);
  const upAndDowns = upDownHoles.filter((h) => h.upAndDown === true).length;

  // Sand saves
  const sandHoles = holes.filter((h) => h.sandSave != null);
  const sandSaves = sandHoles.filter((h) => h.sandSave === true).length;

  // Scoring distribution
  const scoreDiffs = holes.map((h) => h.strokes - h.par);

  // Driving distance
  const drives = holes.flatMap((h) =>
    h.shots.filter(
      (s) =>
        s.shotNumber === 1 &&
        h.par >= 4 &&
        s.distanceYards != null &&
        (s.distanceYards ?? 0) > 0
    )
  );
  const avgDrivingDistance =
    drives.length > 0
      ? Math.round(drives.reduce((s, d) => s + (d.distanceYards ?? 0), 0) / drives.length)
      : 0;

  // Par performance
  const par3s = holes.filter((h) => h.par === 3);
  const par4s = holes.filter((h) => h.par === 4);
  const par5s = holes.filter((h) => h.par === 5);

  // Club distances
  const clubDistances: RoundStats['clubDistances'] = {};
  for (const hole of holes) {
    for (const shot of hole.shots) {
      if (shot.club && shot.distanceYards && shot.distanceYards > 0 && !shot.isPutt) {
        const existing = clubDistances[shot.club] ?? { avg: 0, count: 0, distances: [] };
        existing.distances.push(shot.distanceYards);
        existing.count = existing.distances.length;
        existing.avg = Math.round(
          existing.distances.reduce((a, b) => a + b, 0) / existing.count
        );
        clubDistances[shot.club] = existing;
      }
    }
  }

  // Scrambling: up-and-down success when missed GIR
  const scramblingAttempts = holes.filter(
    (h) => h.greenInRegulation === false
  ).length;
  const scramblingSuccesses = holes.filter(
    (h) => h.greenInRegulation === false && h.strokes <= h.par
  ).length;

  return {
    totalStrokes,
    totalPar,
    scoreToPar: totalStrokes - totalPar,
    frontNine: front.reduce((s, h) => s + h.strokes, 0),
    backNine: back.reduce((s, h) => s + h.strokes, 0),

    totalPutts,
    puttsPerHole: holesWithPutts.length > 0 ? roundNum(totalPutts / holesWithPutts.length, 1) : 0,
    oneputts,
    threeputts,

    greensInRegulation: gir,
    greensInRegulationPct: girHoles.length > 0 ? roundNum((gir / girHoles.length) * 100, 1) : 0,
    girHoles: girHoles.length,

    fairwaysHit,
    fairwaysPct: fairwayHoles.length > 0 ? roundNum((fairwaysHit / fairwayHoles.length) * 100, 1) : 0,
    fairwayHoles: fairwayHoles.length,

    upAndDowns,
    upAndDownAttempts: upDownHoles.length,
    upAndDownPct: upDownHoles.length > 0 ? roundNum((upAndDowns / upDownHoles.length) * 100, 1) : 0,

    sandSaves,
    sandSaveAttempts: sandHoles.length,
    sandSavePct: sandHoles.length > 0 ? roundNum((sandSaves / sandHoles.length) * 100, 1) : 0,

    eagles: scoreDiffs.filter((d) => d <= -2).length,
    birdies: scoreDiffs.filter((d) => d === -1).length,
    pars: scoreDiffs.filter((d) => d === 0).length,
    bogeys: scoreDiffs.filter((d) => d === 1).length,
    doubleBogeys: scoreDiffs.filter((d) => d === 2).length,
    triplePlus: scoreDiffs.filter((d) => d >= 3).length,

    avgDrivingDistance,
    drives: drives.length,

    par3Avg: par3s.length > 0 ? roundNum(par3s.reduce((s, h) => s + h.strokes, 0) / par3s.length, 1) : 0,
    par4Avg: par4s.length > 0 ? roundNum(par4s.reduce((s, h) => s + h.strokes, 0) / par4s.length, 1) : 0,
    par5Avg: par5s.length > 0 ? roundNum(par5s.reduce((s, h) => s + h.strokes, 0) / par5s.length, 1) : 0,

    clubDistances,

    scramblingPct:
      scramblingAttempts > 0
        ? roundNum((scramblingSuccesses / scramblingAttempts) * 100, 1)
        : 0,
  };
}

function roundNum(n: number, decimals: number): number {
  const f = Math.pow(10, decimals);
  return Math.round(n * f) / f;
}

/** Auto-derive GIR, fairway hit, up-and-down from shot data when possible */
export function deriveHoleStats(hole: HoleScore): HoleScore {
  const updated = { ...hole };
  const shots = hole.shots;

  if (shots.length === 0) return updated;

  // Auto-detect putts
  const putts = shots.filter((s) => s.isPutt);
  if (putts.length > 0 && updated.putts == null) {
    updated.putts = putts.length;
  }

  // Auto-detect fairway hit (first shot on par 4+)
  if (hole.par >= 4 && updated.fairwayHit == null) {
    const teeShot = shots.find((s) => s.shotNumber === 1);
    if (teeShot?.result) {
      updated.fairwayHit = teeShot.result === 'fairway';
    }
  }

  // Auto-detect GIR: on green in (par - 2) strokes or fewer
  if (updated.greenInRegulation == null && shots.length > 0) {
    const girTarget = hole.par - 2;
    const greenShot = shots.find(
      (s) => (s.result === 'green' || s.result === 'holed') && s.shotNumber <= girTarget
    );
    if (greenShot) {
      updated.greenInRegulation = true;
    } else if (shots.length >= girTarget) {
      // If we have enough shots tracked and none hit the green in regulation
      const anyGreenByTarget = shots
        .filter((s) => s.shotNumber <= girTarget)
        .some((s) => s.result === 'green' || s.result === 'holed');
      if (!anyGreenByTarget) {
        updated.greenInRegulation = false;
      }
    }
  }

  // Auto-detect up-and-down
  if (updated.greenInRegulation === false && updated.upAndDown == null) {
    if (updated.strokes <= updated.par) {
      updated.upAndDown = true;
    } else if (updated.strokes > updated.par) {
      updated.upAndDown = false;
    }
  }

  // Auto-detect sand save
  if (updated.greenInRegulation === false && updated.sandSave == null) {
    const hitBunker = shots.some(
      (s) => s.result === 'bunker' && !s.isPutt
    );
    if (hitBunker) {
      updated.sandSave = updated.strokes <= updated.par;
    }
  }

  return updated;
}

/** Aggregate stats across multiple rounds */
export function aggregateStats(rounds: Round[]): {
  avgScore: number;
  avgPutts: number;
  avgGIR: number;
  avgFairways: number;
  avgDriving: number;
  roundCount: number;
  bestScore: number;
  worstScore: number;
  avgScoreToPar: number;
  clubAvgDistances: Partial<Record<Club, number>>;
} {
  const completed = rounds.filter((r) => r.isComplete);
  if (completed.length === 0) {
    return {
      avgScore: 0, avgPutts: 0, avgGIR: 0, avgFairways: 0, avgDriving: 0,
      roundCount: 0, bestScore: 0, worstScore: 0, avgScoreToPar: 0,
      clubAvgDistances: {},
    };
  }

  const allStats = completed.map(calculateRoundStats);

  const scores = allStats.map((s) => s.totalStrokes);
  const clubAgg: Record<string, number[]> = {};

  for (const s of allStats) {
    for (const [club, data] of Object.entries(s.clubDistances)) {
      if (data) {
        if (!clubAgg[club]) clubAgg[club] = [];
        clubAgg[club].push(...data.distances);
      }
    }
  }

  const clubAvgDistances: Partial<Record<Club, number>> = {};
  for (const [club, dists] of Object.entries(clubAgg)) {
    clubAvgDistances[club as Club] = Math.round(
      dists.reduce((a, b) => a + b, 0) / dists.length
    );
  }

  return {
    roundCount: completed.length,
    avgScore: roundNum(scores.reduce((a, b) => a + b, 0) / scores.length, 1),
    bestScore: Math.min(...scores),
    worstScore: Math.max(...scores),
    avgScoreToPar: roundNum(
      allStats.reduce((s, r) => s + r.scoreToPar, 0) / allStats.length, 1
    ),
    avgPutts: roundNum(
      allStats.reduce((s, r) => s + r.totalPutts, 0) / allStats.length, 1
    ),
    avgGIR: roundNum(
      allStats.reduce((s, r) => s + r.greensInRegulationPct, 0) / allStats.length, 1
    ),
    avgFairways: roundNum(
      allStats.reduce((s, r) => s + r.fairwaysPct, 0) / allStats.length, 1
    ),
    avgDriving: roundNum(
      allStats.filter((s) => s.drives > 0).reduce((s, r) => s + r.avgDrivingDistance, 0) /
        (allStats.filter((s) => s.drives > 0).length || 1),
      0
    ),
    clubAvgDistances,
  };
}

// ============================================================
// Core data models for AI Golf Caddy
// ============================================================

export type Club =
  | 'driver'
  | '3-wood'
  | '5-wood'
  | '7-wood'
  | '2-hybrid'
  | '3-hybrid'
  | '4-hybrid'
  | '5-hybrid'
  | '2-iron'
  | '3-iron'
  | '4-iron'
  | '5-iron'
  | '6-iron'
  | '7-iron'
  | '8-iron'
  | '9-iron'
  | 'pw'
  | 'gw'
  | 'sw'
  | 'lw'
  | 'putter';

export type ShotResult =
  | 'fairway'
  | 'rough'
  | 'deep-rough'
  | 'bunker'
  | 'water'
  | 'ob'
  | 'green'
  | 'fringe'
  | 'trees'
  | 'recovery'
  | 'holed';

export type ShotShape = 'straight' | 'draw' | 'fade' | 'hook' | 'slice' | 'push' | 'pull';

export interface Shot {
  id: string;
  shotNumber: number;       // 1-based shot number within the hole
  club?: Club;
  distanceYards?: number;
  result?: ShotResult;
  shape?: ShotShape;
  isPenalty?: boolean;       // penalty stroke (water, OB, etc.)
  isPutt?: boolean;
  notes?: string;
}

export interface HoleScore {
  holeNumber: number;       // 1-18
  par: number;
  yardage?: number;
  handicapIndex?: number;   // hole handicap rating 1-18
  strokes: number;
  putts?: number;
  fairwayHit?: boolean | null; // null for par 3s
  greenInRegulation?: boolean | null;
  upAndDown?: boolean | null;  // null if GIR
  sandSave?: boolean | null;
  shots: Shot[];
  notes?: string;
}

export interface CourseHole {
  holeNumber: number;
  par: number;
  yardage?: number;
  handicapIndex?: number;
}

export interface CourseTee {
  name: string;            // e.g., "Blue", "White", "Red"
  rating?: number;
  slope?: number;
  holes: CourseHole[];
}

export interface Course {
  id: string;
  name: string;
  city?: string;
  state?: string;
  tees: CourseTee[];
}

export interface Round {
  id: string;
  courseId: string;
  courseName: string;
  teeName: string;
  date: string;            // ISO date string
  holes: HoleScore[];
  isComplete: boolean;
  currentHole: number;     // 1-based, which hole the player is on
  createdAt: string;
  updatedAt: string;
}

// ============================================================
// Computed stats (derived from round data, never stored directly)
// ============================================================

export interface RoundStats {
  totalStrokes: number;
  totalPar: number;
  scoreToPar: number;
  frontNine: number;
  backNine: number;

  // Putting
  totalPutts: number;
  puttsPerHole: number;
  oneputts: number;
  threeputts: number;

  // Greens
  greensInRegulation: number;
  greensInRegulationPct: number;
  girHoles: number; // holes where GIR data exists

  // Fairways (excludes par 3s)
  fairwaysHit: number;
  fairwaysPct: number;
  fairwayHoles: number; // holes where fairway data exists

  // Short game
  upAndDowns: number;
  upAndDownAttempts: number;
  upAndDownPct: number;
  sandSaves: number;
  sandSaveAttempts: number;
  sandSavePct: number;

  // Scoring distribution
  eagles: number;
  birdies: number;
  pars: number;
  bogeys: number;
  doubleBogeys: number;
  triplePlus: number;

  // Driving
  avgDrivingDistance: number;
  drives: number;

  // Par performance
  par3Avg: number;
  par4Avg: number;
  par5Avg: number;

  // Club distances (avg yards per club used)
  clubDistances: Partial<Record<Club, { avg: number; count: number; distances: number[] }>>;

  // Scrambling (getting up-and-down when missing GIR)
  scramblingPct: number;
}

export interface PlayerProfile {
  id: string;
  name: string;
  handicap?: number;
  homeCourse?: string;
  // Club distances from history for AI recommendations
  avgClubDistances: Partial<Record<Club, number>>;
}

// ============================================================
// AI Shot Parser types
// ============================================================

export interface ParsedShotInput {
  shots: Partial<Shot>[];
  putts?: number;
  totalStrokes?: number;
  fairwayHit?: boolean;
  greenInRegulation?: boolean;
  notes?: string;
  confidence: number; // 0-1, how confident the AI is in the parse
}

export interface AICaddyRecommendation {
  suggestedClub: Club;
  reasoning: string;
  alternateClub?: Club;
  distanceToPin?: number;
}

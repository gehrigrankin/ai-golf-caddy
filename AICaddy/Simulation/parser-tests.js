// Table-driven tests for the voice/text shot parser (mirrors ShotParserService.localParse).
// Run: node parser-tests.js
'use strict';
const { localParse } = require('./caddy-core');

let passed = 0, failed = 0;
const fails = [];

function check(name, cond, detail) {
  if (cond) { passed++; }
  else { failed++; fails.push(`${name}: ${detail}`); }
}

function t(input, par, expect, opts = {}) {
  const r = localParse(input, par, opts.shotNumber ?? 1);
  const name = JSON.stringify(input);
  if ('totalStrokes' in expect) check(name, r.totalStrokes === expect.totalStrokes, `totalStrokes ${r.totalStrokes} != ${expect.totalStrokes}`);
  if ('putts' in expect) check(name, r.putts === expect.putts, `putts ${r.putts} != ${expect.putts}`);
  if ('shotCount' in expect) check(name, r.shots.length === expect.shotCount, `shots ${r.shots.length} != ${expect.shotCount} (${JSON.stringify(r.shots)})`);
  if ('fairwayHit' in expect) check(name, r.fairwayHit === expect.fairwayHit, `fairwayHit ${r.fairwayHit} != ${expect.fairwayHit}`);
  if ('clubs' in expect) {
    const clubs = r.shots.map(s => s.club);
    check(name, JSON.stringify(clubs) === JSON.stringify(expect.clubs), `clubs ${JSON.stringify(clubs)} != ${JSON.stringify(expect.clubs)}`);
  }
  if ('results' in expect) {
    const results = r.shots.map(s => s.result);
    check(name, JSON.stringify(results) === JSON.stringify(expect.results), `results ${JSON.stringify(results)} != ${JSON.stringify(expect.results)}`);
  }
  if ('dists' in expect) {
    const dists = r.shots.map(s => s.distanceYards);
    check(name, JSON.stringify(dists) === JSON.stringify(expect.dists), `dists ${JSON.stringify(dists)} != ${JSON.stringify(expect.dists)}`);
  }
  if ('penalties' in expect) {
    const p = r.shots.map(s => s.isPenalty);
    check(name, JSON.stringify(p) === JSON.stringify(expect.penalties), `penalties ${JSON.stringify(p)} != ${JSON.stringify(expect.penalties)}`);
  }
  return r;
}

// --- Simple scores ---
t('4', 4, { totalStrokes: 4 });
t('par', 4, { totalStrokes: 4 });
t('birdie', 4, { totalStrokes: 3 });
t('eagle', 5, { totalStrokes: 3 });
t('bogey', 3, { totalStrokes: 4 });
t('double bogey', 4, { totalStrokes: 6 });
t('triple', 4, { totalStrokes: 7 });
t('four', 4, { totalStrokes: 4 });          // speech returns number words
t('seven', 5, { totalStrokes: 7 });
t('made par', 4, { totalStrokes: 4 });       // filler words
t('par with 2 putts', 4, { totalStrokes: 4, putts: 2 });
t('birdie 1 putt', 4, { totalStrokes: 3, putts: 1 });
t('hole in one', 3, { totalStrokes: 1 });

// --- Putts ---
t('2 putts', 4, { putts: 2, shotCount: 2 });          // expands into 2 putt shots
t('one putt', 4, { putts: 1, shotCount: 1 });
t('3 putt', 4, { putts: 3, shotCount: 3 });

// --- The bugs that were fixed ---
// "sand wedge on the green" used to record a BUNKER (contains "sand")
t('sand wedge on the green', 4, { clubs: ['sw'], results: ['green'] });
// "lob wedge" used to set isPenalty (contains "ob")
t('lob wedge to the green', 4, { clubs: ['lw'], results: ['green'], penalties: [false] });
// "260" used to match the "60" alias -> lob wedge
t('driver 260 down the middle of the fairway', 4, { clubs: ['driver'], dists: [260], results: ['fairway'], fairwayHit: true });
// bare distance with a 56 inside used to become a sand wedge
t('156 to the green', 4, { clubs: [null], dists: [156], results: ['green'] });
// degree lofts parse as clubs, and the loft number is NOT the distance
t('56 degree 80 yards', 4, { clubs: ['sw'], dists: [80] });
t('sixty degree from 40 yards on the green', 4, { clubs: ['lw'], dists: [40], results: ['green'] });
// trailing putt segments expand instead of collapsing to 1 shot
t('driver 250 fairway then 8 iron on the green and 2 putts', 4,
  { shotCount: 4, putts: 2, fairwayHit: true, clubs: ['driver', '8-iron', 'putter', 'putter'] });

// --- Multi-shot lines ---
t('driver 250 fairway, 7 iron 155 green, 2 putts', 4,
  { shotCount: 4, putts: 2, clubs: ['driver', '7-iron', 'putter', 'putter'], dists: [250, 155, null, null] });
t('3 wood 230 rough then 9 iron on the green', 4,
  { shotCount: 2, clubs: ['3-wood', '9-iron'], results: ['rough', 'green'] });
t('driver in the water, penalty, wedge on and 2 putts', 5, { putts: 2 });

// --- Short game ---
t('chip and a putt', 4, { shotCount: 2, putts: 1 });
t('up and down', 4, { shotCount: 2, putts: 1 });
t('chip and 2 putts', 4, { shotCount: 3, putts: 2 });

// --- Recovery / trees: result should be where the ball ENDED ---
t('punched out of the trees to the fairway', 4, { results: ['fairway'] });

// --- Penalties ---
t('driver ob', 4, { penalties: [true] });
t('7 iron in the water', 3, { clubs: ['7-iron'], results: ['water'], penalties: [true] });

// --- Hyphens and casing from speech recognition ---
t('7-iron 150 on the green', 4, { clubs: ['7-iron'], dists: [150], results: ['green'] });
t('Driver 250 Fairway', 4, { clubs: ['driver'], dists: [250], fairwayHit: true });

// --- Fuzz: garbage inputs must not crash or invent shots ---
for (const junk of ['', 'um', 'nice weather today', 'asdf qwerty', '!!!', 'the quick brown fox']) {
  const r = localParse(junk, 4, 1);
  check(`fuzz ${JSON.stringify(junk)}`, r.totalStrokes == null || r.totalStrokes <= 15, 'invented a score');
}

console.log(`parser-tests: ${passed} passed, ${failed} failed`);
if (fails.length) {
  for (const f of fails) console.log('  FAIL ' + f);
  process.exit(1);
}

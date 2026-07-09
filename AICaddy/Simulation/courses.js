// Synthetic-but-realistic 18-hole layouts anchored at real East Valley (AZ)
// course locations. Overpass isn't reachable from CI, so hole routings are
// generated: each tee sits a short walk from the previous green, greens have
// front/center/back points, and some holes carry water/bunker hazards —
// exactly the shape OSMCourseService.fetchCourseHoles produces.
'use strict';

const YD = 0.9144; // yards -> meters

// Deterministic RNG so failures reproduce
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function offset(point, northYards, eastYards) {
  const dLat = (northYards * YD) / 111320;
  const dLng = (eastYards * YD) / (111320 * Math.cos(point.lat * Math.PI / 180));
  return { lat: point.lat + dLat, lng: point.lng + dLng };
}

function project(point, bearingDeg, yards) {
  const rad = bearingDeg * Math.PI / 180;
  return offset(point, Math.cos(rad) * yards, Math.sin(rad) * yards);
}

/**
 * Generate an 18-hole routing.
 * @param {string} name
 * @param {{lat:number,lng:number}} start clubhouse / hole-1 tee
 * @param {Array<{par:number,yds:number}>} specs 18 hole specs
 * @param {number} seed
 */
function makeCourse(name, city, start, specs, seed) {
  const rng = mulberry32(seed);
  const holes = [];
  let tee = { ...start };
  // Rotate through headings so the routing loops back toward the clubhouse
  let heading = 40 + rng() * 50;

  specs.forEach((spec, i) => {
    const holeNumber = i + 1;
    // Front nine works away from the clubhouse, back nine turns home
    const turn = (i < 9 ? 1 : -1) * (55 + rng() * 70);
    if (i > 0) heading = (heading + turn + 360) % 360;

    const green = project(tee, heading, spec.yds);
    const greenFront = project(green, (heading + 180) % 360, 12);
    const greenBack = project(green, heading, 12);

    const hazards = [];
    if (spec.water) {
      // Water guarding the approach ~40y short of the green
      hazards.push({ type: 'water', position: project(green, (heading + 180) % 360, 40 + rng() * 20), label: 'Water' });
    }
    if (spec.par >= 4 || rng() < 0.6) {
      hazards.push({ type: 'bunker', position: project(green, (heading + 90 + rng() * 180) % 360, 15 + rng() * 10), label: 'Bunker' });
    }

    holes.push({
      holeNumber,
      par: spec.par,
      yardage: spec.yds,
      gps: { tee: { ...tee }, greenCenter: green, greenFront, greenBack, hazards },
    });

    // Next tee: a 25-40y walk from this green
    tee = project(green, (heading + 20 + rng() * 40) % 360, 25 + rng() * 15);
  });

  return { name, city, location: start, holes, slope: 126 + Math.floor(rng() * 10), rating: 70.4 + rng() * 2 };
}

// Real course anchor points in the Gilbert / Chandler / Mesa / Tempe area
const COURSES = [
  makeCourse('Western Skies Golf Club', 'Gilbert, AZ', { lat: 33.3623, lng: -111.7433 }, [
    { par: 4, yds: 385 }, { par: 5, yds: 520, water: true }, { par: 3, yds: 165 },
    { par: 4, yds: 400 }, { par: 4, yds: 375 }, { par: 3, yds: 180, water: true },
    { par: 5, yds: 545 }, { par: 4, yds: 410 }, { par: 4, yds: 355 },
    { par: 4, yds: 390 }, { par: 3, yds: 150 }, { par: 5, yds: 530 },
    { par: 4, yds: 420, water: true }, { par: 4, yds: 365 }, { par: 3, yds: 195 },
    { par: 4, yds: 405 }, { par: 5, yds: 510 }, { par: 4, yds: 380 },
  ], 11),

  makeCourse('Ocotillo Golf Club', 'Chandler, AZ', { lat: 33.2492, lng: -111.8635 }, [
    { par: 4, yds: 395, water: true }, { par: 3, yds: 170, water: true }, { par: 5, yds: 535 },
    { par: 4, yds: 380 }, { par: 4, yds: 415, water: true }, { par: 3, yds: 155 },
    { par: 4, yds: 370 }, { par: 5, yds: 525, water: true }, { par: 4, yds: 400 },
    { par: 4, yds: 385 }, { par: 3, yds: 185, water: true }, { par: 4, yds: 410 },
    { par: 5, yds: 540 }, { par: 4, yds: 360 }, { par: 4, yds: 395, water: true },
    { par: 3, yds: 140 }, { par: 4, yds: 425 }, { par: 5, yds: 515 },
  ], 22),

  makeCourse('Ken McDonald Golf Course', 'Tempe, AZ', { lat: 33.3676, lng: -111.9207 }, [
    { par: 4, yds: 375 }, { par: 4, yds: 405 }, { par: 3, yds: 160 },
    { par: 5, yds: 505 }, { par: 4, yds: 390 }, { par: 4, yds: 365 },
    { par: 3, yds: 175, water: true }, { par: 4, yds: 400 }, { par: 5, yds: 550 },
    { par: 4, yds: 385 }, { par: 4, yds: 370 }, { par: 3, yds: 145 },
    { par: 4, yds: 415 }, { par: 5, yds: 520, water: true }, { par: 4, yds: 380 },
    { par: 3, yds: 190 }, { par: 4, yds: 395 }, { par: 5, yds: 500 },
  ], 33),
];

module.exports = { COURSES, mulberry32, project, offset };

import { NextRequest, NextResponse } from 'next/server';

const GOLFBERT_KEY = process.env.GOLFBERT_API_KEY;
const GOLFBERT_HOST = 'golfbert.p.rapidapi.com';

async function golfbertFetch(path: string) {
  const response = await fetch(`https://${GOLFBERT_HOST}${path}`, {
    headers: {
      'x-rapidapi-key': GOLFBERT_KEY!,
      'x-rapidapi-host': GOLFBERT_HOST,
    },
  });
  if (!response.ok) throw new Error(`Golfbert ${path}: ${response.status}`);
  return response.json();
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const courseId = searchParams.get('id');

  if (!courseId) {
    return NextResponse.json({ error: 'Course ID required' }, { status: 400 });
  }

  if (!GOLFBERT_KEY) {
    return NextResponse.json({ error: 'Golf course API not configured' }, { status: 500 });
  }

  try {
    // Fetch course details, holes, and tee info in parallel
    const [courseData, holesData] = await Promise.all([
      golfbertFetch(`/courses/${courseId}`),
      golfbertFetch(`/courses/${courseId}/holes`),
    ]);

    // Fetch GPS data for each hole
    const holes = holesData.holes || holesData || [];
    const holesWithGps = await Promise.all(
      holes.map(async (hole: Record<string, unknown>) => {
        let gps = undefined;
        try {
          const gpsData = await golfbertFetch(`/holes/${hole.id}/gpsdata`);
          gps = normalizeHoleGps(gpsData);
        } catch {
          // GPS data not available for this hole
        }

        return {
          holeNumber: hole.number || hole.hole_number,
          par: hole.par,
          yardage: hole.yards || hole.yardage,
          handicapIndex: hole.handicap || hole.handicap_index,
          gps,
        };
      })
    );

    // Normalize tees
    const tees = (courseData.teeboxes || courseData.tees || []).map(
      (t: Record<string, unknown>) => ({
        name: t.name || t.tee_name || 'Default',
        rating: t.rating || t.course_rating,
        slope: t.slope || t.slope_rating,
        holes: holesWithGps,
      })
    );

    // If no tees came from API, create a default one
    if (tees.length === 0) {
      tees.push({ name: 'Default', holes: holesWithGps });
    }

    const course = {
      id: String(courseId),
      name: courseData.name || courseData.club_name || 'Unknown',
      city: courseData.city,
      state: courseData.state || courseData.region,
      location:
        courseData.latitude && courseData.longitude
          ? { lat: Number(courseData.latitude), lng: Number(courseData.longitude) }
          : undefined,
      tees,
    };

    return NextResponse.json(course);
  } catch (err) {
    console.error('Course detail error:', err);
    return NextResponse.json({ error: 'Failed to load course details' }, { status: 500 });
  }
}

function normalizeHoleGps(gpsData: Record<string, unknown> | Record<string, unknown>[]) {
  // Golfbert returns GPS points with type labels
  const points = Array.isArray(gpsData) ? gpsData : (gpsData as Record<string, unknown[]>).gps_points || [];

  const gps: Record<string, unknown> = {};
  const hazards: { type: string; position: { lat: number; lng: number }; label?: string }[] = [];

  for (const point of points as Record<string, unknown>[]) {
    const lat = Number(point.latitude || point.lat);
    const lng = Number(point.longitude || point.lng || point.lon);
    if (!lat || !lng) continue;

    const type = String(point.type || point.label || '').toLowerCase();
    const coord = { lat, lng };

    if (type.includes('tee')) {
      gps.tee = coord;
    } else if (type.includes('green') && type.includes('center')) {
      gps.greenCenter = coord;
    } else if (type.includes('green') && type.includes('front')) {
      gps.greenFront = coord;
    } else if (type.includes('green') && type.includes('back')) {
      gps.greenBack = coord;
    } else if (type.includes('fairway') || type.includes('dogleg')) {
      gps.fairwayCenter = coord;
    } else if (type.includes('bunker') || type.includes('sand')) {
      hazards.push({ type: 'bunker', position: coord, label: String(point.label || 'Bunker') });
    } else if (type.includes('water') || type.includes('hazard') || type.includes('lake') || type.includes('pond')) {
      hazards.push({ type: 'water', position: coord, label: String(point.label || 'Water') });
    }
  }

  if (hazards.length > 0) gps.hazards = hazards;

  return Object.keys(gps).length > 0 ? gps : undefined;
}

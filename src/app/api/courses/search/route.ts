import { NextRequest, NextResponse } from 'next/server';

const GOLFBERT_KEY = process.env.GOLFBERT_API_KEY;
const GOLFBERT_HOST = 'golfbert.p.rapidapi.com';

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const name = searchParams.get('name');
  const lat = searchParams.get('lat');
  const lng = searchParams.get('lng');

  if (!GOLFBERT_KEY) {
    return NextResponse.json({ error: 'Golf course API not configured' }, { status: 500 });
  }

  try {
    let url: string;

    if (lat && lng) {
      // Search by location
      url = `https://${GOLFBERT_HOST}/courses?lat=${lat}&lng=${lng}&radius=30`;
    } else if (name) {
      // Search by name
      url = `https://${GOLFBERT_HOST}/courses?name=${encodeURIComponent(name)}`;
    } else {
      return NextResponse.json({ error: 'Provide name or lat/lng' }, { status: 400 });
    }

    const response = await fetch(url, {
      headers: {
        'x-rapidapi-key': GOLFBERT_KEY,
        'x-rapidapi-host': GOLFBERT_HOST,
      },
    });

    if (!response.ok) {
      const text = await response.text();
      console.error('Golfbert search error:', text);
      return NextResponse.json({ error: 'Course search failed' }, { status: 502 });
    }

    const data = await response.json();

    // Normalize the response to our format
    const courses = (data.courses || data || []).map((c: Record<string, unknown>) => ({
      id: String(c.id),
      name: c.name || c.club_name || 'Unknown',
      city: c.city,
      state: c.state || c.region,
      location: c.latitude && c.longitude
        ? { lat: Number(c.latitude), lng: Number(c.longitude) }
        : undefined,
    }));

    return NextResponse.json({ courses });
  } catch (err) {
    console.error('Course search error:', err);
    return NextResponse.json({ error: 'Search failed' }, { status: 500 });
  }
}

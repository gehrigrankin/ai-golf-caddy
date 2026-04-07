export interface GpsCoord {
  lat: number;
  lng: number;
}

const EARTH_RADIUS_YARDS = 6_371_000 / 0.9144; // ~6,967,410 yards

/** Haversine distance between two GPS coordinates, in yards */
export function distanceYards(a: GpsCoord, b: GpsCoord): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);

  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);

  const h =
    sinLat * sinLat +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;

  return Math.round(2 * EARTH_RADIUS_YARDS * Math.asin(Math.sqrt(h)));
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

/** Bearing from point A to point B in degrees (0 = north, 90 = east) */
export function bearing(a: GpsCoord, b: GpsCoord): number {
  const dLng = toRad(b.lng - a.lng);
  const y = Math.sin(dLng) * Math.cos(toRad(b.lat));
  const x =
    Math.cos(toRad(a.lat)) * Math.sin(toRad(b.lat)) -
    Math.sin(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.cos(dLng);
  return ((toDeg(Math.atan2(y, x)) + 360) % 360);
}

function toDeg(rad: number): number {
  return (rad * 180) / Math.PI;
}

/** Calculate a destination point given start, bearing (degrees), and distance (yards) */
export function destinationPoint(start: GpsCoord, bearingDeg: number, distYards: number): GpsCoord {
  const R = EARTH_RADIUS_YARDS;
  const d = distYards / R;
  const brng = toRad(bearingDeg);
  const lat1 = toRad(start.lat);
  const lng1 = toRad(start.lng);

  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(brng)
  );
  const lng2 =
    lng1 +
    Math.atan2(
      Math.sin(brng) * Math.sin(d) * Math.cos(lat1),
      Math.cos(d) - Math.sin(lat1) * Math.sin(lat2)
    );

  return { lat: toDeg(lat2), lng: toDeg(lng2) };
}

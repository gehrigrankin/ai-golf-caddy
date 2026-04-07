'use client';

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import Map, { Marker, Source, Layer, MapRef } from 'react-map-gl/mapbox';
import 'mapbox-gl/dist/mapbox-gl.css';
import { HoleGps, GpsPoint } from '@/types/golf';
import { distanceYards } from '@/lib/gps';
import { useGeolocation } from '@/hooks/useGeolocation';

interface HoleMapProps {
  holeGps?: HoleGps;
  holeNumber: number;
  par: number;
  mapboxToken: string;
}

export default function HoleMap({ holeGps, holeNumber, par, mapboxToken }: HoleMapProps) {
  const mapRef = useRef<MapRef>(null);
  const { position: userPosition, accuracy } = useGeolocation(true);
  const [dragTarget, setDragTarget] = useState<GpsPoint | null>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [showDistances, setShowDistances] = useState(true);

  // Determine the key points
  const greenCenter = holeGps?.greenCenter;
  const greenFront = holeGps?.greenFront;
  const greenBack = holeGps?.greenBack;
  const tee = holeGps?.tee;
  const hazards = holeGps?.hazards || [];

  // Calculate center of the hole for initial map view
  const center = useMemo(() => {
    if (greenCenter && tee) {
      return {
        lat: (greenCenter.lat + tee.lat) / 2,
        lng: (greenCenter.lng + tee.lng) / 2,
      };
    }
    return greenCenter || tee || userPosition || { lat: 33.5, lng: -84.3 };
  }, [greenCenter, tee, userPosition]);

  // Calculate distances from user position
  const distToGreenCenter = userPosition && greenCenter ? distanceYards(userPosition, greenCenter) : null;
  const distToGreenFront = userPosition && greenFront ? distanceYards(userPosition, greenFront) : null;
  const distToGreenBack = userPosition && greenBack ? distanceYards(userPosition, greenBack) : null;
  const distToDragTarget = userPosition && dragTarget ? distanceYards(userPosition, dragTarget) : null;

  // Distances from drag target to key points
  const dragToGreen = dragTarget && greenCenter ? distanceYards(dragTarget, greenCenter) : null;

  // Fit bounds to show the full hole
  useEffect(() => {
    if (!mapRef.current || (!greenCenter && !tee)) return;

    const points: GpsPoint[] = [];
    if (tee) points.push(tee);
    if (greenCenter) points.push(greenCenter);
    if (greenFront) points.push(greenFront);
    if (greenBack) points.push(greenBack);
    if (userPosition) points.push(userPosition);
    hazards.forEach((h) => points.push(h.position));

    if (points.length < 2) return;

    const lats = points.map((p) => p.lat);
    const lngs = points.map((p) => p.lng);

    mapRef.current.fitBounds(
      [
        [Math.min(...lngs) - 0.001, Math.min(...lats) - 0.001],
        [Math.max(...lngs) + 0.001, Math.max(...lats) + 0.001],
      ],
      { padding: 50, duration: 500 }
    );
  }, [greenCenter, greenFront, greenBack, tee, userPosition, hazards]);

  // Handle map click to place/move drag target
  const handleMapClick = useCallback(
    (e: { lngLat: { lat: number; lng: number } }) => {
      if (!isDragging) {
        setDragTarget({ lat: e.lngLat.lat, lng: e.lngLat.lng });
      }
    },
    [isDragging]
  );

  // Handle drag target movement
  const handleTargetDrag = useCallback(
    (e: { lngLat: { lat: number; lng: number } }) => {
      setDragTarget({ lat: e.lngLat.lat, lng: e.lngLat.lng });
    },
    []
  );

  // GeoJSON line from user to green
  const userToGreenLine = useMemo(() => {
    if (!userPosition || !greenCenter) return null;
    return {
      type: 'Feature' as const,
      geometry: {
        type: 'LineString' as const,
        coordinates: [
          [userPosition.lng, userPosition.lat],
          [greenCenter.lng, greenCenter.lat],
        ],
      },
      properties: {},
    };
  }, [userPosition, greenCenter]);

  // GeoJSON line from user to drag target
  const userToTargetLine = useMemo(() => {
    if (!userPosition || !dragTarget) return null;
    return {
      type: 'Feature' as const,
      geometry: {
        type: 'LineString' as const,
        coordinates: [
          [userPosition.lng, userPosition.lat],
          [dragTarget.lng, dragTarget.lat],
        ],
      },
      properties: {},
    };
  }, [userPosition, dragTarget]);

  // Line from drag target to green
  const targetToGreenLine = useMemo(() => {
    if (!dragTarget || !greenCenter) return null;
    return {
      type: 'Feature' as const,
      geometry: {
        type: 'LineString' as const,
        coordinates: [
          [dragTarget.lng, dragTarget.lat],
          [greenCenter.lng, greenCenter.lat],
        ],
      },
      properties: {},
    };
  }, [dragTarget, greenCenter]);

  if (!mapboxToken) {
    return (
      <div className="bg-gray-800/60 rounded-xl p-4 text-center text-gray-400 text-sm">
        <p>Set NEXT_PUBLIC_MAPBOX_TOKEN in .env.local to enable the hole map.</p>
      </div>
    );
  }

  if (!holeGps || (!greenCenter && !tee)) {
    return (
      <div className="bg-gray-800/60 rounded-xl p-4 text-center text-sm">
        <div className="text-gray-400 mb-1">No GPS data for hole {holeNumber}</div>
        {userPosition && (
          <div className="text-gray-500">
            Your position: {userPosition.lat.toFixed(5)}, {userPosition.lng.toFixed(5)}
            {accuracy && <span> ({Math.round(accuracy)}m accuracy)</span>}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {/* Distance banner */}
      {showDistances && (
        <div className="flex items-center gap-2 overflow-x-auto hide-scrollbar">
          {distToGreenFront != null && (
            <DistanceBadge label="Front" yards={distToGreenFront} color="text-green-400" />
          )}
          {distToGreenCenter != null && (
            <DistanceBadge label="Center" yards={distToGreenCenter} color="text-white" />
          )}
          {distToGreenBack != null && (
            <DistanceBadge label="Back" yards={distToGreenBack} color="text-red-400" />
          )}
          {distToDragTarget != null && (
            <DistanceBadge label="Target" yards={distToDragTarget} color="text-amber-400" />
          )}
        </div>
      )}

      {/* Map */}
      <div className="rounded-xl overflow-hidden border border-gray-700/50" style={{ height: 280 }}>
        <Map
          ref={mapRef}
          initialViewState={{
            latitude: center.lat,
            longitude: center.lng,
            zoom: 16.5,
            bearing: 0,
            pitch: 0,
          }}
          mapStyle="mapbox://styles/mapbox/satellite-v9"
          mapboxAccessToken={mapboxToken}
          onClick={handleMapClick}
          attributionControl={false}
          logoPosition="bottom-right"
          style={{ width: '100%', height: '100%' }}
          interactive={true}
        >
          {/* Line: user to green */}
          {userToGreenLine && (
            <Source type="geojson" data={userToGreenLine}>
              <Layer
                type="line"
                paint={{
                  'line-color': '#10b981',
                  'line-width': 2,
                  'line-dasharray': [4, 3],
                  'line-opacity': 0.7,
                }}
              />
            </Source>
          )}

          {/* Line: user to drag target */}
          {userToTargetLine && (
            <Source type="geojson" data={userToTargetLine}>
              <Layer
                type="line"
                paint={{
                  'line-color': '#f59e0b',
                  'line-width': 2,
                  'line-opacity': 0.8,
                }}
              />
            </Source>
          )}

          {/* Line: drag target to green */}
          {targetToGreenLine && (
            <Source type="geojson" data={targetToGreenLine}>
              <Layer
                type="line"
                paint={{
                  'line-color': '#f59e0b',
                  'line-width': 1.5,
                  'line-dasharray': [3, 2],
                  'line-opacity': 0.6,
                }}
              />
            </Source>
          )}

          {/* User position marker */}
          {userPosition && (
            <Marker latitude={userPosition.lat} longitude={userPosition.lng}>
              <div className="relative">
                <div className="w-4 h-4 bg-blue-500 rounded-full border-2 border-white shadow-lg" />
                {accuracy && accuracy > 10 && (
                  <div
                    className="absolute rounded-full bg-blue-500/20 border border-blue-500/30 -translate-x-1/2 -translate-y-1/2"
                    style={{
                      top: '50%',
                      left: '50%',
                      // rough pixel approximation of accuracy circle
                      width: Math.min(60, Math.max(20, accuracy * 2)),
                      height: Math.min(60, Math.max(20, accuracy * 2)),
                    }}
                  />
                )}
              </div>
            </Marker>
          )}

          {/* Tee marker */}
          {tee && (
            <Marker latitude={tee.lat} longitude={tee.lng}>
              <div className="flex flex-col items-center">
                <div className="w-3 h-3 bg-white rounded-full border border-gray-400 shadow" />
                <div className="text-[10px] text-white font-medium bg-black/60 px-1 rounded mt-0.5">
                  TEE
                </div>
              </div>
            </Marker>
          )}

          {/* Green marker */}
          {greenCenter && (
            <Marker latitude={greenCenter.lat} longitude={greenCenter.lng}>
              <div className="flex flex-col items-center">
                <div className="relative">
                  <div className="w-5 h-5 bg-green-500 rounded-full border-2 border-white shadow-lg flex items-center justify-center">
                    <div className="w-1 h-1 bg-white rounded-full" />
                  </div>
                </div>
                {distToGreenCenter != null && (
                  <div className="text-[10px] text-white font-bold bg-black/70 px-1.5 py-0.5 rounded mt-0.5">
                    {distToGreenCenter}y
                  </div>
                )}
              </div>
            </Marker>
          )}

          {/* Green front/back markers */}
          {greenFront && (
            <Marker latitude={greenFront.lat} longitude={greenFront.lng}>
              <div className="w-2.5 h-2.5 bg-green-300 rounded-full border border-white/60 shadow" />
            </Marker>
          )}
          {greenBack && (
            <Marker latitude={greenBack.lat} longitude={greenBack.lng}>
              <div className="w-2.5 h-2.5 bg-red-400 rounded-full border border-white/60 shadow" />
            </Marker>
          )}

          {/* Hazard markers */}
          {hazards.map((hazard, i) => (
            <Marker key={i} latitude={hazard.position.lat} longitude={hazard.position.lng}>
              <div className="flex flex-col items-center">
                <div
                  className={`w-3.5 h-3.5 rounded-full border border-white/60 shadow ${
                    hazard.type === 'water'
                      ? 'bg-blue-500'
                      : hazard.type === 'bunker'
                      ? 'bg-yellow-500'
                      : 'bg-green-800'
                  }`}
                />
                {userPosition && (
                  <div className="text-[9px] text-white bg-black/60 px-1 rounded mt-0.5">
                    {distanceYards(userPosition, hazard.position)}y
                  </div>
                )}
              </div>
            </Marker>
          ))}

          {/* Draggable target marker */}
          {dragTarget && (
            <Marker
              latitude={dragTarget.lat}
              longitude={dragTarget.lng}
              draggable
              onDragStart={() => setIsDragging(true)}
              onDrag={handleTargetDrag}
              onDragEnd={(e) => {
                setIsDragging(false);
                setDragTarget({ lat: e.lngLat.lat, lng: e.lngLat.lng });
              }}
            >
              <div className="flex flex-col items-center cursor-move">
                <div className="relative">
                  {/* Crosshair target */}
                  <div className="w-8 h-8 rounded-full border-2 border-amber-400 bg-amber-400/20 flex items-center justify-center shadow-lg">
                    <div className="w-0.5 h-4 bg-amber-400 absolute" />
                    <div className="w-4 h-0.5 bg-amber-400 absolute" />
                    <div className="w-2 h-2 rounded-full bg-amber-400" />
                  </div>
                </div>
                <div className="text-[10px] font-bold text-amber-400 bg-black/80 px-1.5 py-0.5 rounded mt-0.5 whitespace-nowrap">
                  {distToDragTarget != null ? `${distToDragTarget}y` : ''}
                  {dragToGreen != null ? ` | ${dragToGreen}y to green` : ''}
                </div>
              </div>
            </Marker>
          )}
        </Map>
      </div>

      {/* Controls */}
      <div className="flex items-center justify-between text-xs">
        <div className="flex gap-2">
          {dragTarget && (
            <button
              onClick={() => setDragTarget(null)}
              className="text-amber-400 hover:text-amber-300"
            >
              Clear target
            </button>
          )}
          {!dragTarget && (
            <span className="text-gray-500">Tap map to place distance target</span>
          )}
        </div>
        <button
          onClick={() => setShowDistances(!showDistances)}
          className="text-gray-500 hover:text-gray-300"
        >
          {showDistances ? 'Hide' : 'Show'} distances
        </button>
      </div>
    </div>
  );
}

function DistanceBadge({
  label,
  yards,
  color,
}: {
  label: string;
  yards: number;
  color: string;
}) {
  return (
    <div className="flex-shrink-0 bg-gray-800/80 rounded-lg px-3 py-1.5 text-center">
      <div className="text-[10px] text-gray-400 uppercase">{label}</div>
      <div className={`text-lg font-bold leading-tight ${color}`}>{yards}</div>
      <div className="text-[10px] text-gray-500">yds</div>
    </div>
  );
}

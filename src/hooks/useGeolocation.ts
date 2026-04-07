'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { GpsCoord } from '@/lib/gps';

interface GeolocationState {
  position: GpsCoord | null;
  accuracy: number | null;   // meters
  heading: number | null;    // degrees, 0 = north
  error: string | null;
  isTracking: boolean;
}

export function useGeolocation(active: boolean = true) {
  const [state, setState] = useState<GeolocationState>({
    position: null,
    accuracy: null,
    heading: null,
    error: null,
    isTracking: false,
  });
  const watchId = useRef<number | null>(null);

  const start = useCallback(() => {
    if (!('geolocation' in navigator)) {
      setState((s) => ({ ...s, error: 'Geolocation not supported' }));
      return;
    }

    setState((s) => ({ ...s, isTracking: true, error: null }));

    watchId.current = navigator.geolocation.watchPosition(
      (pos) => {
        setState({
          position: { lat: pos.coords.latitude, lng: pos.coords.longitude },
          accuracy: pos.coords.accuracy,
          heading: pos.coords.heading,
          error: null,
          isTracking: true,
        });
      },
      (err) => {
        setState((s) => ({
          ...s,
          error:
            err.code === 1
              ? 'Location permission denied'
              : err.code === 2
              ? 'Location unavailable'
              : 'Location request timed out',
          isTracking: false,
        }));
      },
      {
        enableHighAccuracy: true,
        maximumAge: 5000,       // accept cached positions up to 5s old
        timeout: 10000,
      }
    );
  }, []);

  const stop = useCallback(() => {
    if (watchId.current !== null) {
      navigator.geolocation.clearWatch(watchId.current);
      watchId.current = null;
    }
    setState((s) => ({ ...s, isTracking: false }));
  }, []);

  useEffect(() => {
    if (active) {
      start();
    } else {
      stop();
    }
    return stop;
  }, [active, start, stop]);

  return state;
}

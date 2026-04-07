'use client';

import { useState, useCallback } from 'react';
import { Course, GpsPoint } from '@/types/golf';

interface SearchResult {
  id: string;
  name: string;
  city?: string;
  state?: string;
  location?: GpsPoint;
}

interface CourseSearchProps {
  onCourseSelected: (course: Course) => void;
  onSkip: () => void;
}

export default function CourseSearch({ onCourseSelected, onSkip }: CourseSearchProps) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [useLocation, setUseLocation] = useState(false);

  const searchByName = useCallback(async () => {
    if (!query.trim()) return;
    setSearching(true);
    setError('');
    setResults([]);

    try {
      const res = await fetch(`/api/courses/search?name=${encodeURIComponent(query.trim())}`);
      if (!res.ok) {
        const data = await res.json();
        setError(data.error || 'Search failed');
        return;
      }
      const data = await res.json();
      setResults(data.courses || []);
      if ((data.courses || []).length === 0) {
        setError('No courses found. Try a different name or set up manually.');
      }
    } catch {
      setError('Search failed. Check your connection.');
    } finally {
      setSearching(false);
    }
  }, [query]);

  const searchNearby = useCallback(async () => {
    setUseLocation(true);
    setSearching(true);
    setError('');
    setResults([]);

    try {
      const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true,
          timeout: 10000,
        });
      });

      const res = await fetch(
        `/api/courses/search?lat=${pos.coords.latitude}&lng=${pos.coords.longitude}`
      );
      if (!res.ok) {
        const data = await res.json();
        setError(data.error || 'Search failed');
        return;
      }
      const data = await res.json();
      setResults(data.courses || []);
      if ((data.courses || []).length === 0) {
        setError('No courses found nearby.');
      }
    } catch (err) {
      if (err instanceof GeolocationPositionError) {
        setError('Could not get your location. Try searching by name.');
      } else {
        setError('Search failed.');
      }
    } finally {
      setSearching(false);
      setUseLocation(false);
    }
  }, []);

  const selectCourse = useCallback(
    async (result: SearchResult) => {
      setLoadingId(result.id);
      setError('');

      try {
        const res = await fetch(`/api/courses/details?id=${result.id}`);
        if (!res.ok) {
          setError('Failed to load course details');
          return;
        }
        const course: Course = await res.json();
        onCourseSelected(course);
      } catch {
        setError('Failed to load course details');
      } finally {
        setLoadingId(null);
      }
    },
    [onCourseSelected]
  );

  return (
    <div className="space-y-4">
      <div className="text-center">
        <h2 className="text-lg font-semibold mb-1">Find Your Course</h2>
        <p className="text-sm text-gray-400">
          Search for your course to auto-load hole data and GPS maps
        </p>
      </div>

      {/* Search by name */}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          searchByName();
        }}
        className="flex gap-2"
      >
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Course name..."
          className="flex-1 bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/50"
        />
        <button
          type="submit"
          disabled={searching || !query.trim()}
          className="bg-emerald-600 text-white px-5 py-3 rounded-xl font-medium hover:bg-emerald-700 disabled:opacity-50"
        >
          {searching && !useLocation ? '...' : 'Search'}
        </button>
      </form>

      {/* Search nearby */}
      <button
        onClick={searchNearby}
        disabled={searching}
        className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl bg-gray-800 border border-gray-700 text-gray-300 hover:text-white hover:border-gray-600 disabled:opacity-50 transition-colors"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
          <path fillRule="evenodd" d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 103 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 002.274 1.765 11.842 11.842 0 00.976.544l.062.029.018.008.006.003zM10 11.25a2.25 2.25 0 100-4.5 2.25 2.25 0 000 4.5z" clipRule="evenodd" />
        </svg>
        {searching && useLocation ? 'Finding nearby courses...' : 'Find courses near me'}
      </button>

      {/* Results */}
      {results.length > 0 && (
        <div className="space-y-2">
          <div className="text-xs text-gray-500 uppercase tracking-wide">
            {results.length} course{results.length !== 1 ? 's' : ''} found
          </div>
          {results.map((r) => (
            <button
              key={r.id}
              onClick={() => selectCourse(r)}
              disabled={loadingId !== null}
              className="w-full text-left p-4 rounded-xl bg-gray-800/50 border border-gray-700/50 hover:border-emerald-500/50 hover:bg-gray-800 transition-colors disabled:opacity-50"
            >
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-medium">{r.name}</div>
                  {(r.city || r.state) && (
                    <div className="text-sm text-gray-400">
                      {[r.city, r.state].filter(Boolean).join(', ')}
                    </div>
                  )}
                </div>
                {loadingId === r.id && (
                  <div className="text-sm text-emerald-400 animate-pulse">Loading...</div>
                )}
              </div>
            </button>
          ))}
        </div>
      )}

      {error && (
        <div className="text-sm text-amber-400 text-center p-2">{error}</div>
      )}

      {/* Skip / manual setup */}
      <button
        onClick={onSkip}
        className="w-full text-center text-sm text-gray-500 hover:text-gray-300 py-2 transition-colors"
      >
        Set up course manually instead
      </button>
    </div>
  );
}

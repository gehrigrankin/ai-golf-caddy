'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { Course, Round, HoleScore, CourseTee } from '@/types/golf';
import { generateId } from '@/lib/utils';
import { saveRound, saveCourse, getAllCourses } from '@/lib/db';
import CourseSearch from '@/components/CourseSearch';
import CourseSetup from '@/components/CourseSetup';
import HolePlay from '@/components/HolePlay';
import HoleMap from '@/components/HoleMap';
import Scorecard from '@/components/Scorecard';
import RoundSummary from '@/components/RoundSummary';

const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN || '';

type Phase = 'search' | 'setup' | 'play' | 'summary';

export default function RoundPage() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>('search');
  const [courses, setCourses] = useState<Course[]>([]);
  const [activeCourse, setActiveCourse] = useState<Course | null>(null);
  const [round, setRound] = useState<Round | null>(null);
  const [currentHole, setCurrentHole] = useState(1);
  const [showScorecard, setShowScorecard] = useState(false);
  const [showMap, setShowMap] = useState(true);

  useEffect(() => {
    getAllCourses().then(setCourses);
  }, []);

  // When a course is found via API search
  const handleApiCourseSelected = useCallback(
    async (course: Course) => {
      // Save the course locally for future use
      await saveCourse(course);
      setCourses((prev) => [...prev.filter((c) => c.id !== course.id), course]);
      setActiveCourse(course);
      // Go straight to tee selection if there are multiple tees, otherwise start
      if (course.tees.length === 1) {
        startRound(course, course.tees[0].name);
      } else {
        setPhase('setup');
      }
    },
    []
  );

  // Manual course setup or tee selection for API course
  const handleCourseSetupComplete = useCallback(
    (course: Course, teeName: string) => {
      setActiveCourse(course);
      startRound(course, teeName);
    },
    []
  );

  const startRound = useCallback((course: Course, teeName: string) => {
    const tee: CourseTee = course.tees.find((t) => t.name === teeName) || course.tees[0];

    const holes: HoleScore[] = tee.holes.map((h) => ({
      holeNumber: h.holeNumber,
      par: h.par,
      yardage: h.yardage,
      handicapIndex: h.handicapIndex,
      strokes: 0,
      putts: undefined,
      fairwayHit: h.par >= 4 ? null : undefined,
      greenInRegulation: null,
      upAndDown: null,
      sandSave: null,
      shots: [],
    }));

    const newRound: Round = {
      id: generateId(),
      courseId: course.id,
      courseName: course.name,
      teeName: tee.name,
      date: new Date().toISOString(),
      holes,
      isComplete: false,
      currentHole: 1,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    setRound(newRound);
    setCurrentHole(1);
    setPhase('play');
    saveRound(newRound);
  }, []);

  const updateHole = useCallback(
    (updatedHole: HoleScore) => {
      if (!round) return;

      const newHoles = round.holes.map((h) =>
        h.holeNumber === updatedHole.holeNumber ? updatedHole : h
      );
      const newRound = {
        ...round,
        holes: newHoles,
        currentHole,
        updatedAt: new Date().toISOString(),
      };
      setRound(newRound);
      saveRound(newRound);
    },
    [round, currentHole]
  );

  const goToHole = useCallback((n: number) => {
    if (n >= 1 && n <= 18) {
      setCurrentHole(n);
      setShowScorecard(false);
    }
  }, []);

  const handleNext = useCallback(() => {
    if (currentHole < 18) {
      setCurrentHole(currentHole + 1);
    } else if (round) {
      const finishedRound = {
        ...round,
        isComplete: true,
        updatedAt: new Date().toISOString(),
      };
      setRound(finishedRound);
      saveRound(finishedRound);
      setPhase('summary');
    }
  }, [currentHole, round]);

  const handlePrev = useCallback(() => {
    if (currentHole > 1) {
      setCurrentHole(currentHole - 1);
    }
  }, [currentHole]);

  if (!round && phase !== 'search' && phase !== 'setup') return null;

  const currentHoleData = round?.holes.find((h) => h.holeNumber === currentHole);
  const totalScore = round?.holes.reduce((s, h) => s + h.strokes, 0) ?? 0;
  const totalPar = round?.holes
    .filter((h) => h.strokes > 0)
    .reduce((s, h) => s + h.par, 0) ?? 0;

  // Get GPS data for current hole from the active course
  const currentHoleGps = activeCourse
    ? activeCourse.tees[0]?.holes.find((h) => h.holeNumber === currentHole)?.gps
    : undefined;

  const hasGps = activeCourse?.tees[0]?.holes.some((h) => h.gps);

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <div className="max-w-lg mx-auto px-4 py-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <button
            onClick={() => {
              if (phase === 'search' || phase === 'setup' || phase === 'summary') {
                router.push('/');
              } else {
                if (confirm('Leave round? Your progress is saved.')) {
                  router.push('/');
                }
              }
            }}
            className="text-gray-400 hover:text-white text-sm"
          >
            &larr; Home
          </button>

          {phase === 'play' && round && (
            <div className="flex items-center gap-3">
              {hasGps && MAPBOX_TOKEN && (
                <button
                  onClick={() => setShowMap(!showMap)}
                  className={`text-sm transition-colors ${
                    showMap ? 'text-emerald-400 hover:text-emerald-300' : 'text-gray-400 hover:text-white'
                  }`}
                >
                  Map
                </button>
              )}
              <button
                onClick={() => setShowScorecard(!showScorecard)}
                className="text-sm text-emerald-400 hover:text-emerald-300"
              >
                {showScorecard ? 'Back to Hole' : 'Scorecard'}
              </button>
            </div>
          )}
        </div>

        {/* Search phase — find course via API */}
        {phase === 'search' && (
          <>
            <h1 className="text-2xl font-bold mb-6">New Round</h1>
            <CourseSearch
              onCourseSelected={handleApiCourseSelected}
              onSkip={() => setPhase('setup')}
            />
          </>
        )}

        {/* Setup phase — manual course creation or tee selection */}
        {phase === 'setup' && (
          <>
            <h1 className="text-2xl font-bold mb-6">
              {activeCourse ? `Select Tee — ${activeCourse.name}` : 'New Round'}
            </h1>
            <CourseSetup
              onComplete={handleCourseSetupComplete}
              existingCourses={activeCourse ? [activeCourse, ...courses] : courses}
            />
          </>
        )}

        {/* Play phase */}
        {phase === 'play' && round && currentHoleData && (
          <>
            {showScorecard ? (
              <div className="space-y-4">
                <h2 className="text-lg font-bold">Scorecard</h2>
                <Scorecard round={round} onHoleClick={goToHole} />
                <p className="text-xs text-gray-500 text-center">Tap a hole to jump to it</p>
              </div>
            ) : (
              <div className="space-y-4">
                {/* Hole map (collapsible) */}
                {showMap && MAPBOX_TOKEN && currentHoleGps && (
                  <HoleMap
                    holeGps={currentHoleGps}
                    holeNumber={currentHole}
                    par={currentHoleData.par}
                    mapboxToken={MAPBOX_TOKEN}
                  />
                )}

                {/* Hole play controls */}
                <HolePlay
                  hole={currentHoleData}
                  onUpdate={updateHole}
                  onNext={handleNext}
                  onPrev={handlePrev}
                  isFirst={currentHole === 1}
                  isLast={currentHole === 18}
                  totalScore={totalScore}
                  totalPar={totalPar}
                />
              </div>
            )}

            {/* Hole dots */}
            {!showScorecard && (
              <div className="mt-6 flex items-center justify-center gap-1 flex-wrap">
                {round.holes.map((h) => (
                  <button
                    key={h.holeNumber}
                    onClick={() => goToHole(h.holeNumber)}
                    className={`w-7 h-7 rounded-full text-xs font-medium transition-colors ${
                      h.holeNumber === currentHole
                        ? 'bg-emerald-600 text-white'
                        : h.strokes > 0
                        ? 'bg-gray-700 text-gray-300'
                        : 'bg-gray-800 text-gray-600'
                    }`}
                  >
                    {h.holeNumber}
                  </button>
                ))}
              </div>
            )}
          </>
        )}

        {/* Summary phase */}
        {phase === 'summary' && round && (
          <RoundSummary
            round={round}
            onClose={() => router.push('/')}
            onHoleClick={(n) => {
              setCurrentHole(n);
              setPhase('play');
              setShowScorecard(false);
            }}
          />
        )}
      </div>
    </div>
  );
}

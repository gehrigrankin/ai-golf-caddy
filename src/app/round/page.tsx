'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { Course, Round, HoleScore, CourseTee } from '@/types/golf';
import { generateId } from '@/lib/utils';
import { saveRound, getAllCourses } from '@/lib/db';
import CourseSetup from '@/components/CourseSetup';
import HolePlay from '@/components/HolePlay';
import Scorecard from '@/components/Scorecard';
import RoundSummary from '@/components/RoundSummary';

type Phase = 'setup' | 'play' | 'scorecard' | 'summary';

export default function RoundPage() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>('setup');
  const [courses, setCourses] = useState<Course[]>([]);
  const [round, setRound] = useState<Round | null>(null);
  const [currentHole, setCurrentHole] = useState(1);
  const [showScorecard, setShowScorecard] = useState(false);

  useEffect(() => {
    getAllCourses().then(setCourses);
  }, []);

  const handleCourseSelected = useCallback(
    (course: Course, teeName: string) => {
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
    },
    []
  );

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

  const goToHole = useCallback(
    (n: number) => {
      if (n >= 1 && n <= 18) {
        setCurrentHole(n);
        setShowScorecard(false);
      }
    },
    []
  );

  const handleNext = useCallback(() => {
    if (currentHole < 18) {
      setCurrentHole(currentHole + 1);
    } else {
      // Finish round
      if (round) {
        const finishedRound = {
          ...round,
          isComplete: true,
          updatedAt: new Date().toISOString(),
        };
        setRound(finishedRound);
        saveRound(finishedRound);
        setPhase('summary');
      }
    }
  }, [currentHole, round]);

  const handlePrev = useCallback(() => {
    if (currentHole > 1) {
      setCurrentHole(currentHole - 1);
    }
  }, [currentHole]);

  if (!round && phase !== 'setup') return null;

  const currentHoleData = round?.holes.find((h) => h.holeNumber === currentHole);
  const totalScore = round?.holes.reduce((s, h) => s + h.strokes, 0) ?? 0;
  const totalPar = round?.holes
    .filter((h) => h.strokes > 0)
    .reduce((s, h) => s + h.par, 0) ?? 0;

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <div className="max-w-lg mx-auto px-4 py-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <button
            onClick={() => {
              if (phase === 'setup') {
                router.push('/');
              } else if (phase === 'summary') {
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
            <button
              onClick={() => setShowScorecard(!showScorecard)}
              className="text-sm text-emerald-400 hover:text-emerald-300"
            >
              {showScorecard ? 'Back to Hole' : 'Scorecard'}
            </button>
          )}
        </div>

        {/* Setup phase */}
        {phase === 'setup' && (
          <>
            <h1 className="text-2xl font-bold mb-6">New Round</h1>
            <CourseSetup onComplete={handleCourseSelected} existingCourses={courses} />
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
            )}

            {/* Mini scorecard / hole dots */}
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

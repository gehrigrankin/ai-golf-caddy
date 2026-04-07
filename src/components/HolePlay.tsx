'use client';

import { useState, useCallback } from 'react';
import { HoleScore, Shot, ParsedShotInput } from '@/types/golf';
import { parseShotInput } from '@/lib/shot-parser';
import { deriveHoleStats } from '@/lib/stats';
import { scoreBgClass, scoreLabel, cn, generateId } from '@/lib/utils';
import VoiceInput from './VoiceInput';

interface HolePlayProps {
  hole: HoleScore;
  onUpdate: (hole: HoleScore) => void;
  onNext: () => void;
  onPrev: () => void;
  isFirst: boolean;
  isLast: boolean;
  totalScore: number;
  totalPar: number;
}

export default function HolePlay({
  hole,
  onUpdate,
  onNext,
  onPrev,
  isFirst,
  isLast,
  totalScore,
  totalPar,
}: HolePlayProps) {
  const [parsing, setParsing] = useState(false);
  const [lastParse, setLastParse] = useState<string>('');

  const handleVoiceResult = useCallback(
    async (transcript: string) => {
      setParsing(true);
      setLastParse('');

      try {
        const parsed: ParsedShotInput = await parseShotInput(transcript, {
          holeNumber: hole.holeNumber,
          par: hole.par,
          yardage: hole.yardage,
          currentShotNumber: hole.shots.length + 1,
        });

        const updated = { ...hole };

        // If we got a total stroke count
        if (parsed.totalStrokes != null) {
          updated.strokes = parsed.totalStrokes;
          setLastParse(`Score: ${parsed.totalStrokes}`);
        }

        // Add any new shots
        if (parsed.shots.length > 0) {
          const newShots: Shot[] = parsed.shots.map((s, i) => ({
            id: s.id || generateId(),
            shotNumber: s.shotNumber || hole.shots.length + i + 1,
            club: s.club,
            distanceYards: s.distanceYards,
            result: s.result,
            shape: s.shape,
            isPenalty: s.isPenalty,
            isPutt: s.isPutt,
            notes: s.notes,
          }));
          updated.shots = [...updated.shots, ...newShots];

          // Auto-update stroke count from shots if not explicitly set
          if (parsed.totalStrokes == null) {
            updated.strokes = updated.shots.length;
          }

          const desc = newShots
            .map(
              (s) =>
                [s.club, s.distanceYards ? `${s.distanceYards}y` : '', s.result]
                  .filter(Boolean)
                  .join(' ') || 'shot'
            )
            .join(', ');
          setLastParse(desc);
        }

        // Apply explicit overrides
        if (parsed.putts != null) updated.putts = parsed.putts;
        if (parsed.fairwayHit != null) updated.fairwayHit = parsed.fairwayHit;
        if (parsed.greenInRegulation != null)
          updated.greenInRegulation = parsed.greenInRegulation;

        // Auto-derive stats from shot data
        const derived = deriveHoleStats(updated);
        onUpdate(derived);
      } catch (err) {
        console.error('Parse error:', err);
        setLastParse('Could not parse input. Try again.');
      } finally {
        setParsing(false);
      }
    },
    [hole, onUpdate]
  );

  const adjustStrokes = (delta: number) => {
    const newStrokes = Math.max(0, hole.strokes + delta);
    const updated = { ...hole, strokes: newStrokes };
    onUpdate(deriveHoleStats(updated));
  };

  const adjustPutts = (delta: number) => {
    const newPutts = Math.max(0, (hole.putts ?? 0) + delta);
    onUpdate({ ...hole, putts: newPutts });
  };

  const toggleFairway = () => {
    if (hole.par < 4) return;
    const next = hole.fairwayHit === true ? false : hole.fairwayHit === false ? null : true;
    onUpdate({ ...hole, fairwayHit: next });
  };

  const toggleGIR = () => {
    const next =
      hole.greenInRegulation === true
        ? false
        : hole.greenInRegulation === false
        ? null
        : true;
    onUpdate({ ...hole, greenInRegulation: next });
  };

  const clearShots = () => {
    onUpdate({
      ...hole,
      shots: [],
      strokes: 0,
      putts: undefined,
      fairwayHit: hole.par >= 4 ? null : undefined,
      greenInRegulation: null,
      upAndDown: null,
      sandSave: null,
    });
    setLastParse('');
  };

  const scoreDiff = hole.strokes > 0 ? hole.strokes - hole.par : null;
  const runningScore = totalScore - totalPar;

  return (
    <div className="space-y-5">
      {/* Hole header */}
      <div className="text-center space-y-1">
        <div className="flex items-center justify-between">
          <div className="text-sm text-gray-400">
            {runningScore === 0 ? 'E' : runningScore > 0 ? `+${runningScore}` : runningScore} thru{' '}
            {hole.holeNumber - 1 > 0 ? hole.holeNumber - 1 : '-'}
          </div>
          <div className="text-sm text-gray-400">{totalScore} strokes</div>
        </div>
        <h2 className="text-4xl font-bold">Hole {hole.holeNumber}</h2>
        <div className="flex items-center justify-center gap-4 text-gray-400">
          <span>Par {hole.par}</span>
          {hole.yardage && <span>{hole.yardage} yds</span>}
        </div>
      </div>

      {/* Score display */}
      <div className="flex items-center justify-center gap-6">
        <button
          onClick={() => adjustStrokes(-1)}
          className="w-14 h-14 rounded-full bg-gray-800 border border-gray-700 text-2xl font-bold hover:border-gray-500 active:scale-95"
        >
          -
        </button>
        <div className="text-center">
          <div
            className={cn(
              'w-20 h-20 rounded-full flex items-center justify-center text-3xl font-bold',
              hole.strokes > 0 ? scoreBgClass(hole.strokes, hole.par) : 'bg-gray-800 border-2 border-gray-600'
            )}
          >
            {hole.strokes || '-'}
          </div>
          {scoreDiff !== null && (
            <div className="text-sm text-gray-400 mt-1">{scoreLabel(hole.strokes, hole.par)}</div>
          )}
        </div>
        <button
          onClick={() => adjustStrokes(1)}
          className="w-14 h-14 rounded-full bg-gray-800 border border-gray-700 text-2xl font-bold hover:border-gray-500 active:scale-95"
        >
          +
        </button>
      </div>

      {/* Quick stats row */}
      <div className="grid grid-cols-3 gap-2">
        {/* Putts */}
        <div className="bg-gray-800/60 rounded-xl p-3 text-center">
          <div className="text-xs text-gray-400 mb-1">Putts</div>
          <div className="flex items-center justify-center gap-2">
            <button onClick={() => adjustPutts(-1)} className="w-7 h-7 rounded-full bg-gray-700 text-sm hover:bg-gray-600">-</button>
            <span className="text-lg font-semibold w-6 text-center">{hole.putts ?? '-'}</span>
            <button onClick={() => adjustPutts(1)} className="w-7 h-7 rounded-full bg-gray-700 text-sm hover:bg-gray-600">+</button>
          </div>
        </div>

        {/* Fairway */}
        <button
          onClick={toggleFairway}
          disabled={hole.par < 4}
          className={cn(
            'rounded-xl p-3 text-center transition-colors',
            hole.par < 4
              ? 'bg-gray-800/30 opacity-40'
              : hole.fairwayHit === true
              ? 'bg-emerald-600/20 border border-emerald-500/50'
              : hole.fairwayHit === false
              ? 'bg-red-600/20 border border-red-500/50'
              : 'bg-gray-800/60 hover:bg-gray-700/60'
          )}
        >
          <div className="text-xs text-gray-400 mb-1">Fairway</div>
          <div className="text-lg font-semibold">
            {hole.par < 4 ? 'N/A' : hole.fairwayHit === true ? 'Hit' : hole.fairwayHit === false ? 'Miss' : '-'}
          </div>
        </button>

        {/* GIR */}
        <button
          onClick={toggleGIR}
          className={cn(
            'rounded-xl p-3 text-center transition-colors',
            hole.greenInRegulation === true
              ? 'bg-emerald-600/20 border border-emerald-500/50'
              : hole.greenInRegulation === false
              ? 'bg-red-600/20 border border-red-500/50'
              : 'bg-gray-800/60 hover:bg-gray-700/60'
          )}
        >
          <div className="text-xs text-gray-400 mb-1">GIR</div>
          <div className="text-lg font-semibold">
            {hole.greenInRegulation === true ? 'Yes' : hole.greenInRegulation === false ? 'No' : '-'}
          </div>
        </button>
      </div>

      {/* Voice / text input */}
      <div>
        <VoiceInput
          onResult={handleVoiceResult}
          disabled={parsing}
          placeholder={`"driver 250 fairway" or just "${hole.par}"`}
        />
        {parsing && (
          <div className="text-center text-sm text-emerald-400 mt-2 animate-pulse">
            Processing...
          </div>
        )}
        {lastParse && !parsing && (
          <div className="text-center text-sm text-gray-400 mt-2">
            Recorded: {lastParse}
          </div>
        )}
      </div>

      {/* Shot log */}
      {hole.shots.length > 0 && (
        <div className="bg-gray-800/40 rounded-xl p-3">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-400">Shot Log</h3>
            <button onClick={clearShots} className="text-xs text-red-400 hover:text-red-300">
              Clear
            </button>
          </div>
          <div className="space-y-1">
            {hole.shots.map((shot, i) => (
              <div key={shot.id || i} className="flex items-center gap-2 text-sm">
                <span className="text-gray-500 w-5">{shot.shotNumber}.</span>
                <span className="text-emerald-400">{shot.club || '?'}</span>
                {shot.distanceYards && (
                  <span className="text-gray-300">{shot.distanceYards}y</span>
                )}
                {shot.result && (
                  <span
                    className={cn(
                      'px-2 py-0.5 rounded text-xs',
                      shot.result === 'fairway' || shot.result === 'green'
                        ? 'bg-emerald-600/20 text-emerald-400'
                        : shot.result === 'water' || shot.result === 'ob'
                        ? 'bg-red-600/20 text-red-400'
                        : 'bg-gray-700 text-gray-300'
                    )}
                  >
                    {shot.result}
                  </span>
                )}
                {shot.isPutt && (
                  <span className="text-xs text-blue-400">putt</span>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Navigation */}
      <div className="flex gap-3">
        <button
          onClick={onPrev}
          disabled={isFirst}
          className="flex-1 py-3 rounded-xl font-medium bg-gray-800 text-gray-300 hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed"
        >
          Prev Hole
        </button>
        <button
          onClick={onNext}
          className="flex-1 py-3 rounded-xl font-medium bg-emerald-600 text-white hover:bg-emerald-700"
        >
          {isLast ? 'Finish Round' : 'Next Hole'}
        </button>
      </div>
    </div>
  );
}

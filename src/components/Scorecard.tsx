'use client';

import { Round } from '@/types/golf';
import { scoreBgClass, formatScore, cn } from '@/lib/utils';

interface ScorecardProps {
  round: Round;
  onHoleClick?: (holeNumber: number) => void;
  compact?: boolean;
}

export default function Scorecard({ round, onHoleClick, compact }: ScorecardProps) {
  const front = round.holes.filter((h) => h.holeNumber <= 9);
  const back = round.holes.filter((h) => h.holeNumber > 9);

  const frontPar = front.reduce((s, h) => s + h.par, 0);
  const backPar = back.reduce((s, h) => s + h.par, 0);
  const frontScore = front.reduce((s, h) => s + h.strokes, 0);
  const backScore = back.reduce((s, h) => s + h.strokes, 0);
  const totalPar = frontPar + backPar;
  const totalScore = frontScore + backScore;

  const renderNine = (holes: typeof front, label: string, par: number, score: number) => (
    <div className="overflow-x-auto">
      <table className="w-full text-center text-sm">
        <thead>
          <tr className="text-gray-500 text-xs">
            <th className="py-1 px-1 text-left">{label}</th>
            {holes.map((h) => (
              <th key={h.holeNumber} className="py-1 px-1 min-w-[2rem]">
                {h.holeNumber}
              </th>
            ))}
            <th className="py-1 px-2 bg-gray-800/50 rounded">Tot</th>
          </tr>
        </thead>
        <tbody>
          <tr className="text-gray-400 text-xs">
            <td className="py-0.5 px-1 text-left">Par</td>
            {holes.map((h) => (
              <td key={h.holeNumber} className="py-0.5">{h.par}</td>
            ))}
            <td className="py-0.5 bg-gray-800/50 font-medium">{par}</td>
          </tr>
          {!compact && (
            <tr className="text-gray-500 text-xs">
              <td className="py-0.5 px-1 text-left">Yds</td>
              {holes.map((h) => (
                <td key={h.holeNumber} className="py-0.5">{h.yardage || '-'}</td>
              ))}
              <td className="py-0.5 bg-gray-800/50">
                {holes.reduce((s, h) => s + (h.yardage || 0), 0) || '-'}
              </td>
            </tr>
          )}
          <tr>
            <td className="py-1 px-1 text-left font-medium text-gray-300">Score</td>
            {holes.map((h) => (
              <td
                key={h.holeNumber}
                onClick={() => onHoleClick?.(h.holeNumber)}
                className={cn(
                  'py-1 rounded cursor-pointer hover:opacity-80 font-semibold',
                  h.strokes > 0 ? scoreBgClass(h.strokes, h.par) : 'text-gray-600'
                )}
              >
                {h.strokes || '-'}
              </td>
            ))}
            <td className="py-1 bg-gray-800/50 font-bold text-white rounded">
              {score || '-'}
            </td>
          </tr>
          {!compact && (
            <>
              <tr className="text-xs text-gray-500">
                <td className="py-0.5 px-1 text-left">Putts</td>
                {holes.map((h) => (
                  <td key={h.holeNumber} className="py-0.5">
                    {h.putts ?? '-'}
                  </td>
                ))}
                <td className="py-0.5 bg-gray-800/50">
                  {holes.reduce((s, h) => s + (h.putts ?? 0), 0) || '-'}
                </td>
              </tr>
              <tr className="text-xs text-gray-500">
                <td className="py-0.5 px-1 text-left">FIR</td>
                {holes.map((h) => (
                  <td key={h.holeNumber} className="py-0.5">
                    {h.par < 4 ? '' : h.fairwayHit === true ? 'O' : h.fairwayHit === false ? 'X' : '-'}
                  </td>
                ))}
                <td className="py-0.5 bg-gray-800/50">
                  {holes.filter((h) => h.fairwayHit === true).length}/
                  {holes.filter((h) => h.par >= 4 && h.fairwayHit != null).length}
                </td>
              </tr>
              <tr className="text-xs text-gray-500">
                <td className="py-0.5 px-1 text-left">GIR</td>
                {holes.map((h) => (
                  <td key={h.holeNumber} className="py-0.5">
                    {h.greenInRegulation === true ? 'O' : h.greenInRegulation === false ? 'X' : '-'}
                  </td>
                ))}
                <td className="py-0.5 bg-gray-800/50">
                  {holes.filter((h) => h.greenInRegulation === true).length}/
                  {holes.filter((h) => h.greenInRegulation != null).length}
                </td>
              </tr>
            </>
          )}
        </tbody>
      </table>
    </div>
  );

  return (
    <div className="space-y-3">
      {/* Summary bar */}
      <div className="flex items-center justify-between px-2">
        <div className="text-lg font-bold">
          {totalScore > 0 && (
            <>
              {totalScore}{' '}
              <span
                className={cn(
                  'text-sm font-medium',
                  totalScore - totalPar < 0
                    ? 'text-red-400'
                    : totalScore - totalPar > 0
                    ? 'text-sky-400'
                    : 'text-green-400'
                )}
              >
                ({formatScore(totalScore - totalPar)})
              </span>
            </>
          )}
        </div>
        <div className="text-sm text-gray-400">
          {round.courseName} &middot; {round.teeName}
        </div>
      </div>

      {renderNine(front, 'Out', frontPar, frontScore)}
      {renderNine(back, 'In', backPar, backScore)}
    </div>
  );
}

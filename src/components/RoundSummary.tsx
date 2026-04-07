'use client';

import { Round, RoundStats } from '@/types/golf';
import { calculateRoundStats } from '@/lib/stats';
import { formatScore } from '@/lib/utils';
import Scorecard from './Scorecard';

interface RoundSummaryProps {
  round: Round;
  onClose: () => void;
  onHoleClick?: (holeNumber: number) => void;
}

function StatCard({ label, value, sub }: { label: string; value: string | number; sub?: string }) {
  return (
    <div className="bg-gray-800/60 rounded-xl p-3 text-center">
      <div className="text-xs text-gray-400 mb-0.5">{label}</div>
      <div className="text-xl font-bold">{value}</div>
      {sub && <div className="text-xs text-gray-500">{sub}</div>}
    </div>
  );
}

export default function RoundSummary({ round, onClose, onHoleClick }: RoundSummaryProps) {
  const stats: RoundStats = calculateRoundStats(round);

  return (
    <div className="space-y-6 pb-8">
      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-2xl font-bold">Round Summary</h2>
        <p className="text-gray-400">{round.courseName} &middot; {round.teeName}</p>
        <p className="text-gray-500 text-sm">{new Date(round.date).toLocaleDateString()}</p>
      </div>

      {/* Big score */}
      <div className="text-center">
        <div className="text-6xl font-bold">{stats.totalStrokes}</div>
        <div className={`text-2xl font-semibold ${stats.scoreToPar < 0 ? 'text-red-400' : stats.scoreToPar > 0 ? 'text-sky-400' : 'text-green-400'}`}>
          {formatScore(stats.scoreToPar)}
        </div>
        <div className="text-gray-400 text-sm mt-1">
          Front {stats.frontNine} &middot; Back {stats.backNine}
        </div>
      </div>

      {/* Key stats grid */}
      <div className="grid grid-cols-3 gap-2">
        <StatCard label="Putts" value={stats.totalPutts} sub={`${stats.puttsPerHole}/hole`} />
        <StatCard label="GIR" value={`${stats.greensInRegulation}/${stats.girHoles}`} sub={`${stats.greensInRegulationPct}%`} />
        <StatCard label="Fairways" value={`${stats.fairwaysHit}/${stats.fairwayHoles}`} sub={`${stats.fairwaysPct}%`} />
      </div>

      {/* Scoring distribution */}
      <div>
        <h3 className="text-sm font-medium text-gray-400 mb-2">Scoring</h3>
        <div className="grid grid-cols-6 gap-1">
          {[
            { label: 'Eagles', value: stats.eagles, color: 'text-yellow-400' },
            { label: 'Birdies', value: stats.birdies, color: 'text-red-400' },
            { label: 'Pars', value: stats.pars, color: 'text-green-400' },
            { label: 'Bogeys', value: stats.bogeys, color: 'text-sky-400' },
            { label: 'Dbl', value: stats.doubleBogeys, color: 'text-blue-400' },
            { label: '3+', value: stats.triplePlus, color: 'text-gray-400' },
          ].map((item) => (
            <div key={item.label} className="text-center">
              <div className={`text-lg font-bold ${item.color}`}>{item.value}</div>
              <div className="text-xs text-gray-500">{item.label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Detailed stats */}
      <div className="space-y-3">
        <h3 className="text-sm font-medium text-gray-400">Detailed Stats</h3>
        <div className="grid grid-cols-2 gap-2">
          <StatCard label="1-Putts" value={stats.oneputts} />
          <StatCard label="3-Putts" value={stats.threeputts} />
          <StatCard label="Up & Down" value={stats.upAndDownAttempts > 0 ? `${stats.upAndDownPct}%` : '-'} sub={stats.upAndDownAttempts > 0 ? `${stats.upAndDowns}/${stats.upAndDownAttempts}` : undefined} />
          <StatCard label="Sand Saves" value={stats.sandSaveAttempts > 0 ? `${stats.sandSavePct}%` : '-'} sub={stats.sandSaveAttempts > 0 ? `${stats.sandSaves}/${stats.sandSaveAttempts}` : undefined} />
          <StatCard label="Scrambling" value={stats.scramblingPct > 0 ? `${stats.scramblingPct}%` : '-'} />
          {stats.avgDrivingDistance > 0 && (
            <StatCard label="Avg Drive" value={`${stats.avgDrivingDistance}y`} sub={`${stats.drives} drives`} />
          )}
        </div>
      </div>

      {/* Par performance */}
      <div>
        <h3 className="text-sm font-medium text-gray-400 mb-2">Scoring Avg by Par</h3>
        <div className="grid grid-cols-3 gap-2">
          {stats.par3Avg > 0 && <StatCard label="Par 3 Avg" value={stats.par3Avg} />}
          {stats.par4Avg > 0 && <StatCard label="Par 4 Avg" value={stats.par4Avg} />}
          {stats.par5Avg > 0 && <StatCard label="Par 5 Avg" value={stats.par5Avg} />}
        </div>
      </div>

      {/* Club distances */}
      {Object.keys(stats.clubDistances).length > 0 && (
        <div>
          <h3 className="text-sm font-medium text-gray-400 mb-2">Club Distances</h3>
          <div className="grid grid-cols-2 gap-2">
            {Object.entries(stats.clubDistances)
              .sort((a, b) => (b[1]?.avg ?? 0) - (a[1]?.avg ?? 0))
              .map(([club, data]) => (
                <StatCard
                  key={club}
                  label={club.toUpperCase()}
                  value={`${data?.avg}y`}
                  sub={`${data?.count} shots`}
                />
              ))}
          </div>
        </div>
      )}

      {/* Full scorecard */}
      <div>
        <h3 className="text-sm font-medium text-gray-400 mb-2">Scorecard</h3>
        <Scorecard round={round} onHoleClick={onHoleClick} />
      </div>

      <button
        onClick={onClose}
        className="w-full bg-emerald-600 text-white py-4 rounded-2xl text-lg font-semibold hover:bg-emerald-700"
      >
        Done
      </button>
    </div>
  );
}

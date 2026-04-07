'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { Round } from '@/types/golf';
import { getAllRounds, deleteRound } from '@/lib/db';
import { formatScore, formatDate } from '@/lib/utils';
import { calculateRoundStats, aggregateStats } from '@/lib/stats';
import Scorecard from '@/components/Scorecard';
import RoundSummary from '@/components/RoundSummary';

export default function HistoryPage() {
  const [rounds, setRounds] = useState<Round[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedRound, setSelectedRound] = useState<Round | null>(null);
  const [view, setView] = useState<'list' | 'stats'>('list');

  useEffect(() => {
    getAllRounds().then((r) => {
      setRounds(r);
      setLoading(false);
    });
  }, []);

  const completed = rounds.filter((r) => r.isComplete);
  const agg = aggregateStats(completed);

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this round?')) return;
    await deleteRound(id);
    setRounds((prev) => prev.filter((r) => r.id !== id));
    if (selectedRound?.id === id) setSelectedRound(null);
  };

  if (selectedRound) {
    return (
      <div className="min-h-screen bg-gray-950 text-white">
        <div className="max-w-lg mx-auto px-4 py-6">
          <RoundSummary
            round={selectedRound}
            onClose={() => setSelectedRound(null)}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <div className="max-w-lg mx-auto px-4 py-6 pb-safe">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <Link href="/" className="text-gray-400 hover:text-white text-sm">
            ← Home
          </Link>
          <h1 className="text-xl font-bold">History & Stats</h1>
          <div className="w-12" />
        </div>

        {/* View toggle */}
        <div className="flex gap-2 mb-6">
          <button
            onClick={() => setView('list')}
            className={`flex-1 py-2 px-4 rounded-xl font-medium transition-colors ${
              view === 'list'
                ? 'bg-emerald-600 text-white'
                : 'bg-gray-800 text-gray-400 hover:text-white'
            }`}
          >
            Rounds
          </button>
          <button
            onClick={() => setView('stats')}
            className={`flex-1 py-2 px-4 rounded-xl font-medium transition-colors ${
              view === 'stats'
                ? 'bg-emerald-600 text-white'
                : 'bg-gray-800 text-gray-400 hover:text-white'
            }`}
          >
            Trends
          </button>
        </div>

        {view === 'stats' && completed.length > 0 ? (
          <div className="space-y-6">
            {/* Aggregate stats */}
            <div className="text-center">
              <div className="text-sm text-gray-400 mb-1">{agg.roundCount} rounds played</div>
            </div>

            <div className="grid grid-cols-3 gap-2">
              <StatBox label="Avg Score" value={agg.avgScore} />
              <StatBox label="Best" value={agg.bestScore} />
              <StatBox label="Avg vs Par" value={agg.avgScoreToPar > 0 ? `+${agg.avgScoreToPar}` : `${agg.avgScoreToPar}`} />
            </div>

            <div className="grid grid-cols-3 gap-2">
              <StatBox label="Avg Putts" value={agg.avgPutts} />
              <StatBox label="Avg GIR" value={`${agg.avgGIR}%`} />
              <StatBox label="Avg FIR" value={`${agg.avgFairways}%`} />
            </div>

            {agg.avgDriving > 0 && (
              <div className="grid grid-cols-1 gap-2">
                <StatBox label="Avg Driving Distance" value={`${agg.avgDriving} yds`} />
              </div>
            )}

            {/* Club averages */}
            {Object.keys(agg.clubAvgDistances).length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-gray-400 mb-3">Club Distances (all rounds)</h3>
                <div className="grid grid-cols-2 gap-2">
                  {Object.entries(agg.clubAvgDistances)
                    .sort((a, b) => (b[1] ?? 0) - (a[1] ?? 0))
                    .map(([club, avg]) => (
                      <StatBox key={club} label={club.toUpperCase()} value={`${avg} yds`} />
                    ))}
                </div>
              </div>
            )}

            {/* Score history chart (simple bar representation) */}
            <div>
              <h3 className="text-sm font-medium text-gray-400 mb-3">Score History</h3>
              <div className="space-y-1">
                {completed.slice(0, 20).map((round) => {
                  const stats = calculateRoundStats(round);
                  const maxScore = Math.max(...completed.map((r) => r.holes.reduce((s, h) => s + h.strokes, 0)));
                  const pct = maxScore > 0 ? (stats.totalStrokes / maxScore) * 100 : 0;
                  return (
                    <button
                      key={round.id}
                      onClick={() => setSelectedRound(round)}
                      className="w-full flex items-center gap-2 hover:bg-gray-800/50 rounded-lg px-2 py-1 transition-colors"
                    >
                      <div className="text-xs text-gray-500 w-16 text-left shrink-0">
                        {formatDate(round.date).replace(/, \d{4}/, '')}
                      </div>
                      <div className="flex-1 h-5 bg-gray-800/50 rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full ${
                            stats.scoreToPar <= 0 ? 'bg-emerald-600' : stats.scoreToPar <= 5 ? 'bg-sky-600' : 'bg-amber-600'
                          }`}
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                      <div className="text-sm font-medium w-10 text-right">{stats.totalStrokes}</div>
                      <div className={`text-xs w-8 text-right ${stats.scoreToPar <= 0 ? 'text-emerald-400' : 'text-sky-400'}`}>
                        {formatScore(stats.scoreToPar)}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
        ) : view === 'list' ? (
          <div className="space-y-2">
            {loading && <div className="text-center text-gray-500 py-8">Loading...</div>}

            {!loading && completed.length === 0 && (
              <div className="text-center text-gray-500 py-8">
                <p>No completed rounds yet.</p>
                <Link href="/round" className="text-emerald-400 hover:text-emerald-300 text-sm mt-2 inline-block">
                  Start your first round →
                </Link>
              </div>
            )}

            {completed.map((round) => {
              const stats = calculateRoundStats(round);
              return (
                <div
                  key={round.id}
                  className="bg-gray-800/40 border border-gray-700/30 rounded-xl overflow-hidden"
                >
                  <button
                    onClick={() => setSelectedRound(round)}
                    className="w-full p-4 flex items-center justify-between text-left hover:bg-gray-800/60 transition-colors"
                  >
                    <div>
                      <div className="font-medium">{round.courseName}</div>
                      <div className="text-xs text-gray-500">
                        {formatDate(round.date)} &middot; {round.teeName}
                      </div>
                      <div className="flex gap-3 mt-1 text-xs text-gray-400">
                        {stats.totalPutts > 0 && <span>{stats.totalPutts} putts</span>}
                        {stats.girHoles > 0 && <span>{stats.greensInRegulationPct}% GIR</span>}
                        {stats.fairwayHoles > 0 && <span>{stats.fairwaysPct}% FIR</span>}
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="text-right">
                        <div className="text-2xl font-bold">{stats.totalStrokes}</div>
                        <div
                          className={`text-sm font-medium ${
                            stats.scoreToPar < 0
                              ? 'text-red-400'
                              : stats.scoreToPar > 0
                              ? 'text-sky-400'
                              : 'text-green-400'
                          }`}
                        >
                          {formatScore(stats.scoreToPar)}
                        </div>
                      </div>
                    </div>
                  </button>
                  <div className="border-t border-gray-700/30 px-4 py-2 flex justify-end">
                    <button
                      onClick={() => handleDelete(round.id)}
                      className="text-xs text-gray-500 hover:text-red-400 transition-colors"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="text-center text-gray-500 py-8">
            Play some rounds to see your trends!
          </div>
        )}
      </div>
    </div>
  );
}

function StatBox({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-gray-800/60 rounded-xl p-3 text-center">
      <div className="text-xs text-gray-400 mb-0.5">{label}</div>
      <div className="text-lg font-bold">{value}</div>
    </div>
  );
}

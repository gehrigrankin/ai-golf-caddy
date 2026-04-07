'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { Round } from '@/types/golf';
import { getAllRounds, deleteRound } from '@/lib/db';
import { formatScore, formatDate, scoreBgClass } from '@/lib/utils';
import { calculateRoundStats } from '@/lib/stats';

export default function Home() {
  const [rounds, setRounds] = useState<Round[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getAllRounds().then((r) => {
      setRounds(r);
      setLoading(false);
    });
  }, []);

  const inProgress = rounds.find((r) => !r.isComplete);
  const completed = rounds.filter((r) => r.isComplete).slice(0, 5);

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this round?')) return;
    await deleteRound(id);
    setRounds((prev) => prev.filter((r) => r.id !== id));
  };

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <div className="max-w-lg mx-auto px-4 py-8 pb-safe">
        {/* Hero */}
        <div className="text-center mb-10">
          <div className="text-5xl mb-3">⛳</div>
          <h1 className="text-3xl font-bold tracking-tight">AI Caddy</h1>
          <p className="text-gray-400 mt-2">Track your round with voice. Get the stats you never had time to log.</p>
        </div>

        {/* Resume in-progress round */}
        {inProgress && (
          <Link
            href="/round"
            className="block mb-4 bg-amber-600/20 border border-amber-500/40 rounded-2xl p-5 hover:bg-amber-600/30 transition-colors"
          >
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xs text-amber-400 font-medium uppercase tracking-wide mb-1">
                  Round in Progress
                </div>
                <div className="font-semibold">{inProgress.courseName}</div>
                <div className="text-sm text-gray-400">
                  Hole {inProgress.currentHole} &middot; {inProgress.teeName}
                </div>
              </div>
              <div className="text-right">
                <div className="text-2xl font-bold">
                  {inProgress.holes.reduce((s, h) => s + h.strokes, 0) || '-'}
                </div>
                <div className="text-xs text-gray-500">
                  {formatDate(inProgress.date)}
                </div>
              </div>
            </div>
          </Link>
        )}

        {/* Start new round */}
        <Link
          href="/round"
          className="block w-full bg-emerald-600 text-white text-center py-4 rounded-2xl text-lg font-semibold hover:bg-emerald-700 active:scale-[0.98] transition-all mb-8"
        >
          Start New Round
        </Link>

        {/* Quick links */}
        <div className="grid grid-cols-2 gap-3 mb-8">
          <Link
            href="/history"
            className="bg-gray-800/60 border border-gray-700/50 rounded-xl p-4 hover:bg-gray-800 transition-colors"
          >
            <div className="text-2xl mb-1">📊</div>
            <div className="font-medium">History</div>
            <div className="text-xs text-gray-400">{completed.length} round{completed.length !== 1 ? 's' : ''}</div>
          </Link>
          <Link
            href="/history"
            className="bg-gray-800/60 border border-gray-700/50 rounded-xl p-4 hover:bg-gray-800 transition-colors"
          >
            <div className="text-2xl mb-1">📈</div>
            <div className="font-medium">Stats</div>
            <div className="text-xs text-gray-400">Trends & averages</div>
          </Link>
        </div>

        {/* Recent rounds */}
        {completed.length > 0 && (
          <div>
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide mb-3">
              Recent Rounds
            </h2>
            <div className="space-y-2">
              {completed.map((round) => {
                const stats = calculateRoundStats(round);
                return (
                  <div
                    key={round.id}
                    className="bg-gray-800/40 border border-gray-700/30 rounded-xl p-4 flex items-center justify-between"
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
                      <button
                        onClick={() => handleDelete(round.id)}
                        className="text-gray-600 hover:text-red-400 text-xs p-1"
                      >
                        ✕
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>

            {rounds.filter((r) => r.isComplete).length > 5 && (
              <Link
                href="/history"
                className="block text-center text-sm text-emerald-400 hover:text-emerald-300 mt-3"
              >
                View all rounds →
              </Link>
            )}
          </div>
        )}

        {/* Empty state */}
        {!loading && rounds.length === 0 && (
          <div className="text-center text-gray-500 mt-8">
            <p>No rounds yet. Tap &quot;Start New Round&quot; to begin!</p>
            <p className="text-sm mt-2">Set up your course, then just talk to your caddy.</p>
          </div>
        )}
      </div>
    </div>
  );
}

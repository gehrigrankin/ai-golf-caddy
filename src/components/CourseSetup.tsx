'use client';

import { useState } from 'react';
import { Course, CourseTee, CourseHole } from '@/types/golf';
import { generateId } from '@/lib/utils';
import { saveCourse } from '@/lib/db';

interface CourseSetupProps {
  onComplete: (course: Course, teeName: string) => void;
  existingCourses: Course[];
}

const DEFAULT_PARS = [4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5];

export default function CourseSetup({ onComplete, existingCourses }: CourseSetupProps) {
  const [mode, setMode] = useState<'select' | 'create'>('select');
  const [courseName, setCourseName] = useState('');
  const [teeName, setTeeName] = useState('White');
  const [courseRating, setCourseRating] = useState('');
  const [slope, setSlope] = useState('');
  const [holes, setHoles] = useState<CourseHole[]>(
    DEFAULT_PARS.map((par, i) => ({ holeNumber: i + 1, par, yardage: undefined }))
  );
  const [selectedCourseId, setSelectedCourseId] = useState('');
  const [selectedTeeName, setSelectedTeeName] = useState('');

  const handleParChange = (index: number, par: number) => {
    setHoles((h) => h.map((hole, i) => (i === index ? { ...hole, par } : hole)));
  };

  const handleYardageChange = (index: number, yardage: string) => {
    const val = yardage ? parseInt(yardage) : undefined;
    setHoles((h) => h.map((hole, i) => (i === index ? { ...hole, yardage: val } : hole)));
  };

  const handleCreateCourse = async () => {
    if (!courseName.trim()) return;

    const tee: CourseTee = {
      name: teeName,
      rating: courseRating ? parseFloat(courseRating) : undefined,
      slope: slope ? parseInt(slope) : undefined,
      holes,
    };

    const course: Course = {
      id: generateId(),
      name: courseName.trim(),
      tees: [tee],
    };

    await saveCourse(course);
    onComplete(course, teeName);
  };

  const handleSelectExisting = () => {
    const course = existingCourses.find((c) => c.id === selectedCourseId);
    if (course) {
      onComplete(course, selectedTeeName || course.tees[0]?.name || 'Default');
    }
  };

  // Quick setup with all par 4s
  const setAllPars = (par: number) => {
    setHoles((h) => h.map((hole) => ({ ...hole, par })));
  };

  return (
    <div className="space-y-6">
      {/* Mode toggle */}
      {existingCourses.length > 0 && (
        <div className="flex gap-2">
          <button
            onClick={() => setMode('select')}
            className={`flex-1 py-2 px-4 rounded-xl font-medium transition-colors ${
              mode === 'select'
                ? 'bg-emerald-600 text-white'
                : 'bg-gray-800 text-gray-400 hover:text-white'
            }`}
          >
            Play saved course
          </button>
          <button
            onClick={() => setMode('create')}
            className={`flex-1 py-2 px-4 rounded-xl font-medium transition-colors ${
              mode === 'create'
                ? 'bg-emerald-600 text-white'
                : 'bg-gray-800 text-gray-400 hover:text-white'
            }`}
          >
            New course
          </button>
        </div>
      )}

      {mode === 'select' && existingCourses.length > 0 ? (
        <div className="space-y-4">
          <div className="space-y-2">
            {existingCourses.map((course) => (
              <button
                key={course.id}
                onClick={() => {
                  setSelectedCourseId(course.id);
                  setSelectedTeeName(course.tees[0]?.name || '');
                }}
                className={`w-full text-left p-4 rounded-xl border transition-colors ${
                  selectedCourseId === course.id
                    ? 'border-emerald-500 bg-emerald-500/10'
                    : 'border-gray-700 bg-gray-800/50 hover:border-gray-600'
                }`}
              >
                <div className="font-semibold">{course.name}</div>
                <div className="text-sm text-gray-400">
                  Tees: {course.tees.map((t) => t.name).join(', ')}
                </div>
              </button>
            ))}
          </div>

          {selectedCourseId && (
            <>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Tee</label>
                <select
                  value={selectedTeeName}
                  onChange={(e) => setSelectedTeeName(e.target.value)}
                  className="w-full bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white"
                >
                  {existingCourses
                    .find((c) => c.id === selectedCourseId)
                    ?.tees.map((t) => (
                      <option key={t.name} value={t.name}>
                        {t.name}
                        {t.rating ? ` (${t.rating}/${t.slope})` : ''}
                      </option>
                    ))}
                </select>
              </div>
              <button
                onClick={handleSelectExisting}
                className="w-full bg-emerald-600 text-white py-4 rounded-2xl text-lg font-semibold hover:bg-emerald-700"
              >
                Start Round
              </button>
            </>
          )}
        </div>
      ) : (
        <div className="space-y-4">
          {/* Course name */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">Course Name</label>
            <input
              type="text"
              value={courseName}
              onChange={(e) => setCourseName(e.target.value)}
              placeholder="e.g., Pine Valley Golf Club"
              className="w-full bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/50"
            />
          </div>

          {/* Tee info */}
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className="block text-sm text-gray-400 mb-1">Tee</label>
              <input
                type="text"
                value={teeName}
                onChange={(e) => setTeeName(e.target.value)}
                placeholder="White"
                className="w-full bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/50"
              />
            </div>
            <div>
              <label className="block text-sm text-gray-400 mb-1">Rating</label>
              <input
                type="number"
                step="0.1"
                value={courseRating}
                onChange={(e) => setCourseRating(e.target.value)}
                placeholder="72.1"
                className="w-full bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/50"
              />
            </div>
            <div>
              <label className="block text-sm text-gray-400 mb-1">Slope</label>
              <input
                type="number"
                value={slope}
                onChange={(e) => setSlope(e.target.value)}
                placeholder="131"
                className="w-full bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/50"
              />
            </div>
          </div>

          {/* Quick par presets */}
          <div>
            <label className="block text-sm text-gray-400 mb-2">Quick Set All Pars</label>
            <div className="flex gap-2">
              {[3, 4, 5].map((p) => (
                <button
                  key={p}
                  onClick={() => setAllPars(p)}
                  className="px-4 py-2 bg-gray-800 border border-gray-700 rounded-lg text-sm hover:border-emerald-500 transition-colors"
                >
                  All Par {p}
                </button>
              ))}
              <button
                onClick={() =>
                  setHoles(
                    DEFAULT_PARS.map((par, i) => ({
                      holeNumber: i + 1,
                      par,
                      yardage: holes[i]?.yardage,
                    }))
                  )
                }
                className="px-4 py-2 bg-gray-800 border border-gray-700 rounded-lg text-sm hover:border-emerald-500 transition-colors"
              >
                Default
              </button>
            </div>
          </div>

          {/* Hole-by-hole setup */}
          <div>
            <label className="block text-sm text-gray-400 mb-2">Hole Setup</label>
            <div className="space-y-1">
              <div className="grid grid-cols-[3rem_1fr_1fr] gap-2 text-xs text-gray-500 px-1">
                <div>Hole</div>
                <div>Par</div>
                <div>Yards</div>
              </div>
              {holes.map((hole, i) => (
                <div key={i} className="grid grid-cols-[3rem_1fr_1fr] gap-2 items-center">
                  <div className="text-center text-sm font-medium text-gray-400">
                    {hole.holeNumber}
                  </div>
                  <div className="flex gap-1">
                    {[3, 4, 5].map((p) => (
                      <button
                        key={p}
                        onClick={() => handleParChange(i, p)}
                        className={`flex-1 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                          hole.par === p
                            ? 'bg-emerald-600 text-white'
                            : 'bg-gray-800 text-gray-400 hover:text-white'
                        }`}
                      >
                        {p}
                      </button>
                    ))}
                  </div>
                  <input
                    type="number"
                    value={hole.yardage || ''}
                    onChange={(e) => handleYardageChange(i, e.target.value)}
                    placeholder="yds"
                    className="bg-gray-800 border border-gray-700 rounded-lg px-2 py-1.5 text-sm text-white placeholder-gray-600 focus:outline-none focus:ring-1 focus:ring-emerald-500/50"
                  />
                </div>
              ))}
            </div>
          </div>

          {/* Total par */}
          <div className="text-center text-gray-400">
            Total Par: <span className="text-white font-semibold">{holes.reduce((s, h) => s + h.par, 0)}</span>
          </div>

          <button
            onClick={handleCreateCourse}
            disabled={!courseName.trim()}
            className="w-full bg-emerald-600 text-white py-4 rounded-2xl text-lg font-semibold hover:bg-emerald-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Start Round
          </button>
        </div>
      )}
    </div>
  );
}

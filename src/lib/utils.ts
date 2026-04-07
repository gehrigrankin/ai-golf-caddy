export function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

export function formatScore(scoreToPar: number): string {
  if (scoreToPar === 0) return 'E';
  return scoreToPar > 0 ? `+${scoreToPar}` : `${scoreToPar}`;
}

export function scoreLabel(strokes: number, par: number): string {
  const diff = strokes - par;
  if (strokes === 0) return '';
  if (diff <= -3) return 'Albatross';
  if (diff === -2) return 'Eagle';
  if (diff === -1) return 'Birdie';
  if (diff === 0) return 'Par';
  if (diff === 1) return 'Bogey';
  if (diff === 2) return 'Double';
  if (diff === 3) return 'Triple';
  return `+${diff}`;
}

export function scoreBgClass(strokes: number, par: number): string {
  if (strokes === 0) return '';
  const diff = strokes - par;
  if (diff <= -2) return 'bg-yellow-400 text-yellow-900';
  if (diff === -1) return 'bg-red-500 text-white';
  if (diff === 0) return 'bg-green-600 text-white';
  if (diff === 1) return 'bg-sky-600 text-white';
  if (diff === 2) return 'bg-blue-800 text-white';
  return 'bg-gray-800 text-white';
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function cn(...classes: (string | false | null | undefined)[]): string {
  return classes.filter(Boolean).join(' ');
}

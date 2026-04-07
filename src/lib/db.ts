'use client';

import { Course, Round, PlayerProfile } from '@/types/golf';

const DB_NAME = 'ai-golf-caddy';
const DB_VERSION = 1;

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains('rounds')) {
        const roundStore = db.createObjectStore('rounds', { keyPath: 'id' });
        roundStore.createIndex('date', 'date');
        roundStore.createIndex('courseId', 'courseId');
      }
      if (!db.objectStoreNames.contains('courses')) {
        db.createObjectStore('courses', { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains('profile')) {
        db.createObjectStore('profile', { keyPath: 'id' });
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function txn<T>(
  storeName: string,
  mode: IDBTransactionMode,
  fn: (store: IDBObjectStore) => IDBRequest<T>
): Promise<T> {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, mode);
        const store = tx.objectStore(storeName);
        const req = fn(store);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      })
  );
}

// ============================================================
// Rounds
// ============================================================

export async function saveRound(round: Round): Promise<void> {
  await txn('rounds', 'readwrite', (store) => store.put(round));
}

export async function getRound(id: string): Promise<Round | undefined> {
  return txn('rounds', 'readonly', (store) => store.get(id));
}

export async function getAllRounds(): Promise<Round[]> {
  const rounds = await txn<Round[]>('rounds', 'readonly', (store) => store.getAll());
  return rounds.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
}

export async function deleteRound(id: string): Promise<void> {
  await txn('rounds', 'readwrite', (store) => store.delete(id));
}

// ============================================================
// Courses
// ============================================================

export async function saveCourse(course: Course): Promise<void> {
  await txn('courses', 'readwrite', (store) => store.put(course));
}

export async function getCourse(id: string): Promise<Course | undefined> {
  return txn('courses', 'readonly', (store) => store.get(id));
}

export async function getAllCourses(): Promise<Course[]> {
  return txn('courses', 'readonly', (store) => store.getAll());
}

export async function deleteCourse(id: string): Promise<void> {
  await txn('courses', 'readwrite', (store) => store.delete(id));
}

// ============================================================
// Player Profile
// ============================================================

const PROFILE_ID = 'default';

export async function getProfile(): Promise<PlayerProfile | undefined> {
  return txn('profile', 'readonly', (store) => store.get(PROFILE_ID));
}

export async function saveProfile(profile: Omit<PlayerProfile, 'id'>): Promise<void> {
  await txn('profile', 'readwrite', (store) =>
    store.put({ ...profile, id: PROFILE_ID })
  );
}

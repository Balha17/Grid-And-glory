/**
 * bank-loader.ts — reads db/seed/bank.en-ar.v1.json into runtime shapes.
 *
 * In production this is a Postgres query; the JSON path exists so the match engine,
 * the tests, and the local demo run against the *real* bank rather than fixtures
 * that drift from the content.
 */

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import type { EntityCatalog, Localized, QuestionDoc } from "./types.ts";

const here = dirname(fileURLToPath(import.meta.url));
const DEFAULT_BANK = resolve(here, "../../db/seed/bank.en-ar.v1.json");

interface RawBank {
  catalogs: {
    clubs: Array<{ id: string; en: string; ar: string }>;
    people: Array<{ id: string; en: string; ar: string }>;
    nations: Array<{ id: string; en: string; ar: string }>;
    competitions: Array<{ id: string; en: string; ar: string }>;
  };
  questions: QuestionDoc[];
}

export interface LoadedBank {
  catalog: EntityCatalog;
  questions: QuestionDoc[];
  /** Difficulty 4–5 only: Shooting Chance fodder. */
  shotQuestions: QuestionDoc[];
}

const toMap = (rows: Array<{ id: string } & Localized>): Map<string, Localized> =>
  new Map(rows.map((r) => [r.id, { en: r.en, ar: r.ar }]));

export const loadBank = async (path = DEFAULT_BANK): Promise<LoadedBank> => {
  const raw = JSON.parse(await readFile(path, "utf8")) as RawBank;

  const catalog: EntityCatalog = {
    clubs: toMap(raw.catalogs.clubs),
    people: toMap(raw.catalogs.people),
    nations: toMap(raw.catalogs.nations),
    competitions: toMap(raw.catalogs.competitions),
  };

  // Never publish a visual clue unless its real image is hosted and available.
  // The current bank still contains placeholder asset:// references, so exclude
  // every media-dependent question from live matches and Shooting Chances.
  const playableQuestions = raw.questions.filter(
    (q) => q.format !== "blur_reveal" && !(q.media?.length),
  );

  return {
    catalog,
    questions: playableQuestions,
    shotQuestions: playableQuestions.filter((q) => q.difficulty >= 4),
  };
};

/** Draw a match pool: spread across formats and difficulty so one match is not all `mc`. */
export const drawPool = (questions: QuestionDoc[], size: number, seed: number): QuestionDoc[] => {
  let state = seed >>> 0 || 1;
  const next = (): number => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 4294967296;
  };

  const byFormat: Record<string, QuestionDoc[]> = {};
  for (const q of questions) {
    (byFormat[q.format] ??= []).push(q);
  }
  for (const key of Object.keys(byFormat)) {
    byFormat[key].sort((a, b) => a.id.localeCompare(b.id));
  }

  const formats = Object.keys(byFormat).sort();
  const pool: QuestionDoc[] = [];
  const used = new Set<string>();

  let cursor = 0;
  while (pool.length < size && used.size < questions.length) {
    const format = formats[cursor % formats.length];
    const bucket = byFormat[format];
    const candidates = bucket.filter((q) => !used.has(q.id));
    if (candidates.length) {
      const pick = candidates[Math.floor(next() * candidates.length)];
      pool.push(pick);
      used.add(pick.id);
    }
    cursor += 1;
    if (cursor > questions.length * formats.length) break;
  }
  return pool;
};

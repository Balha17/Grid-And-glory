#!/usr/bin/env node
/**
 * db/shuffle-answers.mjs — authoring pipeline step 3.
 *
 * Spreads correct answers across option positions. The server shuffles options
 * per player at serve time, so this is *hygiene*, not fairness: it keeps preview
 * builds, screenshots, and analytics from all showing the right answer in slot 1.
 *
 * Idempotent by construction: options are sorted by id before shuffling and the
 * PRNG is seeded from the question id, so the output is a pure function of the
 * id set. Re-running is a no-op.
 *
 * stat_highlow keeps `opt_equal` pinned last — "Equal" reads as a trailing option,
 * never as the first thing your thumb lands on.
 *
 * Usage: node db/shuffle-answers.mjs [path]
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const target = resolve(process.argv[2] ?? "db/seed/bank.en-ar.v1.json");
const bank = JSON.parse(readFileSync(target, "utf8"));

/** FNV-1a → 32-bit seed. */
const seedOf = (str) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
};

/** mulberry32 — small, fast, deterministic. */
const rng = (seed) => () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const shuffle = (items, random) => {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
};

let changed = 0;
for (const q of bank.questions) {
  const before = JSON.stringify(q.options);

  // canonical input order ⇒ stable output
  const canonical = [...q.options].sort((a, b) => a.id.localeCompare(b.id));
  const random = rng(seedOf(q.id));

  if (q.format === "stat_highlow") {
    const entities = canonical.filter((o) => o.id !== "opt_equal");
    const equal = canonical.find((o) => o.id === "opt_equal");
    q.options = equal ? [...shuffle(entities, random), equal] : shuffle(entities, random);
  } else {
    q.options = shuffle(canonical, random);
  }

  if (JSON.stringify(q.options) !== before) changed += 1;
}

bank.meta.updatedAt = new Date().toISOString();
writeFileSync(target, `${JSON.stringify(bank, null, 2)}\n`, "utf8");
console.log(`shuffle-answers: ${changed}/${bank.questions.length} question(s) reordered`);

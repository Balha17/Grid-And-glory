#!/usr/bin/env node
/**
 * db/validate.mjs — authoring pipeline step 2 (CI gate).
 *
 * Dependency-free validator for the bilingual question bank. It enforces the
 * structural contract (mirroring db/schema/question-bank.schema.json) plus the
 * semantic and fairness invariants that JSON Schema cannot express:
 *
 *   - every reference resolves into a catalog
 *   - stat_highlow answer is arithmetically consistent with its own values
 *   - emoji sequences are bidi-isolated (otherwise RTL mirrors the clue)
 *   - blur_reveal assets are text-free (otherwise one locale gets a free hint)
 *   - ar/en character parity is inside the fairness band
 *   - no duplicate prompts
 *   - regional / format quotas
 *   - answer-position bias
 *
 * Usage: node db/validate.mjs [path]   → exit 1 on any error
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ARABIC_CHAR = /[\u0600-\u06FF\u0750-\u077F]/;
const ARABIC_DIACRITICS = /[\u064B-\u0652\u0670]/g;
const BIDI_ISOLATE = /^\u2066[\s\S]*\u2069$/;
const FORMATS = ["mc", "career_path", "emoji_story", "blur_reveal", "stat_highlow"];
const FORMAT_PREFIX = {
  mc: "q_mc_", career_path: "q_career_", emoji_story: "q_emoji_",
  blur_reveal: "q_blur_", stat_highlow: "q_stat_",
};
const PARITY_HARD = [0.55, 1.85];
const PARITY_WARN = [0.7, 1.5];
const MENA_REGIONS = new Set(["MENA", "AFRICA"]);

const errors = [];
const warnings = [];
const info = [];
const fail = (id, msg) => errors.push(`${id}: ${msg}`);
const warn = (id, msg) => warnings.push(`${id}: ${msg}`);

const file = resolve(process.argv[2] ?? "db/seed/bank.en-ar.v1.json");
const bank = JSON.parse(readFileSync(file, "utf8"));

/* ------------------------------------------------------------------ catalogs */

const cats = bank.catalogs ?? {};
for (const name of ["clubs", "people", "nations", "assets", "competitions"]) {
  if (!Array.isArray(cats[name])) fail("catalogs", `missing or non-array "${name}"`);
}

/**
 * Catalog index. `localized` says where the en/ar pair lives: most entities carry it
 * at the top level, assets carry it under `alt` (they are media, not vocabulary).
 */
const index = (arr, idPrefix, localized = true) => {
  const m = new Map();
  for (const item of arr ?? []) {
    if (!item.id?.startsWith(idPrefix)) fail(item.id ?? "?", `id must start with "${idPrefix}"`);
    if (m.has(item.id)) fail(item.id, `duplicate id in catalog`);
    const pair = localized ? item : item.alt;
    for (const loc of ["en", "ar"]) {
      if (typeof pair?.[loc] !== "string" || !pair[loc].trim()) {
        fail(item.id, `missing ${localized ? "" : "alt."}${loc}`);
      }
    }
    if (!ARABIC_CHAR.test(pair?.ar ?? "")) fail(item.id, `"ar" contains no Arabic characters`);
    m.set(item.id, item);
  }
  return m;
};

const clubs = index(cats.clubs, "c_");
const people = index(cats.people, "p_");
const nations = index(cats.nations, "n_");
const assets = index(cats.assets, "a_", false);
const competitions = index(cats.competitions, "");

const entity = (id) => people.get(id) ?? clubs.get(id) ?? nations.get(id) ?? null;
const entityFor = (id) => (/^p_/.test(id) ? people : /^c_/.test(id) ? clubs : nations).get(id) ?? null;

for (const [id, a] of assets) {
  if (typeof a.textFree !== "boolean") fail(id, "asset.textFree must be boolean");
}

/* ---------------------------------------------------------------- questions */

const questions = bank.questions ?? [];
if (!questions.length) fail("bank", "no questions");

const seenIds = new Set();
const seenPrompts = new Map();
const formatCount = Object.fromEntries(FORMATS.map((f) => [f, 0]));
const answerPositions = [0, 0, 0, 0, 0, 0];
let bridgeCount = 0;

const normalizePrompt = (s) =>
  s
    .replace(/[\u2066-\u2069]/g, "")
    .replace(ARABIC_DIACRITICS, "")
    .replace(/[\u0640]/g, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();

for (const q of questions) {
  const id = q.id ?? "<missing-id>";

  if (seenIds.has(id)) fail(id, "duplicate question id");
  seenIds.add(id);

  const prefix = FORMAT_PREFIX[q.format];
  if (!prefix) fail(id, `unknown format "${q.format}"`);
  else if (!id.startsWith(prefix)) fail(id, `id must start with "${prefix}" for format ${q.format}`);

  if (!Number.isInteger(q.difficulty) || q.difficulty < 1 || q.difficulty > 5) {
    fail(id, "difficulty must be an integer 1..5");
  }

  /* every competition must exist in the catalog — otherwise the UI silently renders an id */
  for (const comp of q.competitions ?? []) {
    if (!competitions.has(comp)) fail(id, `unknown competition "${comp}" (not in catalogs.competitions)`);
  }

  /* localized copy */
  for (const [field, obj] of [["prompt", q.prompt], ["explainer", q.explainer]]) {
    if (!obj?.en?.trim() || !obj?.ar?.trim()) fail(id, `${field} needs en and ar`);
    else if (!ARABIC_CHAR.test(obj.ar)) fail(id, `${field}.ar contains no Arabic characters`);
  }

  /* options */
  const opts = q.options ?? [];
  if (opts.length < 2 || opts.length > 6) fail(id, `needs 2..6 options, has ${opts.length}`);
  const optIds = new Set();
  for (const o of opts) {
    if (!/^opt_[a-z0-9_]+$/.test(o.id ?? "")) fail(id, `bad option id "${o.id}"`);
    if (optIds.has(o.id)) fail(id, `duplicate option id "${o.id}"`);
    if (!o.en?.trim() || !o.ar?.trim()) fail(id, `option ${o.id} needs en and ar`);
    // A pure-numeral option ("5", "4") is deliberately identical in both locales: the game
    // standardises on Western digits. Only *words* must actually be Arabic.
    if (o.ar && /\p{L}/u.test(o.ar) && !ARABIC_CHAR.test(o.ar)) {
      fail(id, `option ${o.id} .ar has Latin letters, not Arabic`);
    }
    if ((o.en ?? "").length > 80) fail(id, `option ${o.id} exceeds 80 chars (breaks the answer card)`);
    optIds.add(o.id);
  }
  if (!optIds.has(q.answerOptionId)) fail(id, `answerOptionId "${q.answerOptionId}" is not an option`);

  /* format-specific */
  const fd = q.formatData;
  if (q.format === "mc" && fd !== undefined) fail(id, "mc must not carry formatData");

  if (q.format === "career_path") {
    if (!fd) fail(id, "career_path requires formatData");
    else {
      const ids = fd.clubIds ?? [];
      if (ids.length < 3) fail(id, "career path needs >= 3 clubs");
      if (new Set(ids).size !== ids.length) {
        fail(id, "career path repeats a club — a repeated crest is a broken clue");
      }
      for (const c of ids) if (!clubs.has(c)) fail(id, `unknown club "${c}"`);
    }
  }

  if (q.format === "emoji_story") {
    if (!fd?.emoji) fail(id, "emoji_story requires formatData.emoji");
    else {
      if (!BIDI_ISOLATE.test(fd.emoji)) {
        fail(id, "emoji must be wrapped in U+2066…U+2069 — without it an RTL UI mirrors the clue");
      }
      if (/\p{L}/u.test(fd.emoji)) fail(id, "emoji clue contains letters — it would be language-dependent");
      if (fd.revealMode === "sequential" && !Number.isInteger(fd.emojiIntervalMs)) {
        warn(id, "sequential reveal without emojiIntervalMs");
      }
    }
  }

  if (q.format === "blur_reveal") {
    if (!fd) fail(id, "blur_reveal requires formatData");
    const media = q.media ?? [];
    if (!media.length) fail(id, "blur_reveal requires a media entry");
    for (const m of media) {
      const asset = assets.get(m.assetId);
      if (!asset) fail(id, `unknown asset "${m.assetId}"`);
      else if (m.role === "reveal" && asset.textFree !== true) {
        fail(id, `asset "${m.assetId}" is not text-free — the locale that can read the text gets a free hint`);
      }
    }
    if (fd && (fd.revealMs < 2000 || fd.revealMs > 8000)) fail(id, "revealMs must be 2000..8000");
    if (fd && fd.initialBlurSigma < 4) fail(id, "initialBlurSigma must be >= 4 or the answer is legible instantly");
  }

  if (q.format === "stat_highlow") {
    if (!fd) fail(id, "stat_highlow requires formatData");
    else {
      for (const key of ["entityA", "entityB"]) {
        if (!entity(fd[key])) fail(id, `unknown entity "${fd[key]}"`);
      }
      /* the visible option text must be the entity's own name, or the reveal lies */
      const nameOf = (k) => entityFor(fd[k]);
      const a = nameOf("entityA");
      const b = nameOf("entityB");
      const optA = opts.find((o) => o.id === "opt_a");
      const optB = opts.find((o) => o.id === "opt_b");
      if (a && optA && (optA.en !== a.en || optA.ar !== a.ar)) {
        fail(id, `opt_a text must equal entityA name ("${a.en}")`);
      }
      if (b && optB && (optB.en !== b.en || optB.ar !== b.ar)) {
        fail(id, `opt_b text must equal entityB name ("${b.en}")`);
      }
      if (opts.length !== 3 || !opts.some((o) => o.id === "opt_equal")) {
        fail(id, "stat_highlow must have exactly opt_a, opt_b, opt_equal");
      }
      /* arithmetic truth: the answer must follow from the question's own values */
      const { A, B } = fd.values ?? {};
      if (typeof A !== "number" || typeof B !== "number") fail(id, "values.A and values.B must be numbers");
      else {
        const expected =
          A === B ? "opt_equal" : (fd.direction === "lower" ? A < B : A > B) ? "opt_a" : "opt_b";
        if (q.answerOptionId !== expected) {
          fail(id, `answerOptionId is "${q.answerOptionId}" but values (A=${A}, B=${B}, ${fd.direction}) imply "${expected}"`);
        }
      }
      if (!q.stats?.dataAsOf) fail(id, "stat_highlow requires stats.dataAsOf");
    }
  }

  if (q.stats?.dataAsOf) {
    const d = new Date(q.stats.dataAsOf);
    if (Number.isNaN(d.getTime())) fail(id, "stats.dataAsOf is not a date");
    else if (d.getTime() > Date.now()) fail(id, "stats.dataAsOf is in the future");
  }

  /* publishing gate */
  if (q.authoring?.status === "published") {
    if (!q.authoring.reviewedBy) fail(id, "published question needs authoring.reviewedBy");
    if (!q.localization?.verifiedBy) fail(id, "published question needs localization.verifiedBy (Arabic sign-off)");
  }

  /* localization parity — recompute, never trust */
  const en = [...(q.prompt?.en ?? ""), ...opts.flatMap((o) => [...(o.en ?? "")])].length;
  const ar = [...(q.prompt?.ar ?? ""), ...opts.flatMap((o) => [...(o.ar ?? "")])].length;
  const ratio = en ? ar / en : 0;
  if (q.localization.enChars !== en || q.localization.arChars !== ar) {
    fail(id, `localization counts stale (declared ${q.localization.enChars}/${q.localization.arChars}, actual ${en}/${ar}) — run db/normalize.mjs`);
  }
  if (ratio < PARITY_HARD[0] || ratio > PARITY_HARD[1]) {
    fail(id, `parity ${ratio.toFixed(2)} outside [${PARITY_HARD}] — one locale reads a materially different amount`);
  } else if (ratio < PARITY_WARN[0] || ratio > PARITY_WARN[1]) {
    warn(id, `parity ${ratio.toFixed(2)} outside the comfortable band [${PARITY_WARN}]`);
  }

  /* duplicate prompts — the clue is part of the identity, not just the wording.
     career_path / emoji_story deliberately share a prompt template. */
  const clue =
    q.format === "career_path" ? (q.formatData?.clubIds ?? []).join(">")
    : q.format === "emoji_story" ? (q.formatData?.emoji ?? "")
    : q.format === "blur_reveal" ? (q.media?.[0]?.assetId ?? "")
    : q.format === "stat_highlow" ? `${q.formatData?.entityA}~${q.formatData?.entityB}`
    : "";
  const key = `${normalizePrompt(q.prompt?.en ?? "")}#${clue}`;
  const keyAr = `${normalizePrompt(q.prompt?.ar ?? "")}#${clue}`;
  for (const k of [key, keyAr]) {
    if (!k) continue;
    if (seenPrompts.has(k) && seenPrompts.get(k) !== id) {
      fail(id, `prompt duplicates "${seenPrompts.get(k)}" (normalized: "${k}")`);
    }
    seenPrompts.set(k, id);
  }

  /* quotas */
  formatCount[q.format] += 1;
  if (q.bridge === true) bridgeCount += 1;
  const idx = opts.findIndex((o) => o.id === q.answerOptionId);
  if (idx >= 0) answerPositions[idx] += 1;
}

/* ------------------------------------------------------------- bank-level */

const total = questions.length;

if (total >= 20) {
  for (const f of FORMATS) {
    const share = formatCount[f] / total;
    if (f !== "mc" && share < 0.10) warn("bank", `format ${f} is ${(share * 100).toFixed(0)}% (target 15%)`);
  }
}

const mena = questions.filter((q) => MENA_REGIONS.has(q.region) || q.bridge === true).length;
const globalish = questions.filter((q) => ["GLOBAL", "EUROPE", "SOUTH_AMERICA", "NORTH_AMERICA", "ASIA"].includes(q.region)).length;
info.push(`regional split: MENA/AFRICA/bridge ${mena}/${total} (${((mena / total) * 100).toFixed(0)}%), global ${globalish}/${total} (${((globalish / total) * 100).toFixed(0)}%), bridge ${bridgeCount}`);
if (total >= 20 && mena / total < 0.35) warn("bank", `MENA/African coverage is ${((mena / total) * 100).toFixed(0)}% (target >= 35%)`);
if (total >= 20 && globalish / total < 0.35) warn("bank", `global coverage is ${((globalish / total) * 100).toFixed(0)}% (target >= 35%)`);

const live = answerPositions.slice(0, Math.max(...questions.map((q) => (q.options ?? []).length)));
const totalAnswers = live.reduce((s, n) => s + n, 0);
if (totalAnswers >= 12) {
  const worst = Math.max(...live) / totalAnswers;
  if (worst > 0.4) {
    warn("bank", `answer-position bias: one position holds ${(worst * 100).toFixed(0)}% of correct answers (target <= 40%)`);
  }
  info.push(`answer positions: [${live.join(", ")}]`);
}

const parityRatios = questions.map((q) => q.localization.parityRatio).filter((n) => n > 0);
const meanParity = parityRatios.reduce((s, n) => s + n, 0) / (parityRatios.length || 1);
info.push(`parity mean ${meanParity.toFixed(3)} (min ${Math.min(...parityRatios).toFixed(3)}, max ${Math.max(...parityRatios).toFixed(3)})`);
info.push(`formats: ${FORMATS.map((f) => `${f}=${formatCount[f]}`).join(" ")}`);

/* ------------------------------------------------------------------ report */

console.log(`\nGrid & Glory — bank validation: ${file}`);
console.log(`questions: ${total}  •  published: ${questions.filter((q) => q.authoring?.status === "published").length}`);
for (const line of info) console.log(`  · ${line}`);
if (warnings.length) {
  console.log(`\n⚠ ${warnings.length} warning(s)`);
  for (const w of warnings) console.log(`  - ${w}`);
}
if (errors.length) {
  console.log(`\n✖ ${errors.length} error(s)`);
  for (const e of errors) console.log(`  - ${e}`);
  console.log("\nFAILED");
  process.exit(1);
}
console.log("\n✓ PASSED");

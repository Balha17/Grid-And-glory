#!/usr/bin/env node
/**
 * db/normalize.mjs — authoring pipeline step 1.
 *
 * Recomputes the `localization` block for every question from the actual copy.
 * Hand-editing those numbers is forbidden: they are the evidence behind the
 * cross-language fairness rule in docs/00-product-spec.md §3.4.
 *
 * Usage: node db/normalize.mjs [path-to-bank.json]
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const target = resolve(process.argv[2] ?? "db/seed/bank.en-ar.v1.json");
const bank = JSON.parse(readFileSync(target, "utf8"));

/** Characters a player must actually read for one question, per locale. */
const measure = (question) => {
  const prompt = question.prompt;
  const options = question.options ?? [];
  const en = [...prompt.en, ...options.flatMap((o) => [...o.en])].length;
  const ar = [...prompt.ar, ...options.flatMap((o) => [...o.ar])].length;
  return { enChars: en, arChars: ar, parityRatio: Number((ar / en).toFixed(3)) };
};

let changed = 0;
for (const question of bank.questions) {
  const next = measure(question);
  const prev = question.localization;
  if (
    prev.enChars !== next.enChars ||
    prev.arChars !== next.arChars ||
    prev.parityRatio !== next.parityRatio
  ) {
    question.localization = { ...prev, ...next };
    changed += 1;
  }
}

bank.meta.updatedAt = new Date().toISOString();
writeFileSync(target, `${JSON.stringify(bank, null, 2)}\n`, "utf8");
console.log(`normalize: ${target} — ${changed}/${bank.questions.length} question(s) updated`);

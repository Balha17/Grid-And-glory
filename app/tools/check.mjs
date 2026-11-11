#!/usr/bin/env node
/**
 * app/tools/check.mjs — Dart sanity gate that runs without a Flutter SDK.
 *
 * There is no `dart` in this environment, so the analyzer cannot run. That is not a
 * reason to ship unchecked Dart. This script catches the four failure classes that a
 * compiler would catch first, plus the RTL rule the project treats as non-negotiable:
 *
 *   1. unbalanced (), {}, []            → the file does not parse
 *   2. a relative import that does not resolve  → the file does not build
 *   3. an l10n key used in Dart but absent from the ARB → build failure at gen-l10n
 *   4. ARB placeholder drift between locales → a runtime crash in one language only
 *   5. `EdgeInsets.only(left:` / `Positioned(left:` → the app is broken in Arabic
 *
 * It is a linter-shaped approximation, not a compiler. It says so out loud so nobody
 * mistakes a green run for "the app builds".
 *
 * Usage: node app/tools/check.mjs
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const LIB = join(ROOT, "lib");

const errors = [];
const warnings = [];
let checkedFiles = 0;

/* ------------------------------------------------------------------ helpers */

const walk = (dir) => {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (entry.endsWith(".dart")) out.push(full);
  }
  return out;
};

/**
 * Removes comments but KEEPS string literals, because a real usage can live inside
 * interpolation: `'${l10n.accuracy}: …'`.
 */
const stripComments = (source) => {
  let out = "";
  let i = 0;
  const n = source.length;
  while (i < n) {
    const two = source.slice(i, i + 2);
    if (two === "//") {
      while (i < n && source[i] !== "\n") i += 1;
      continue;
    }
    if (two === "/*") {
      i += 2;
      while (i < n && source.slice(i, i + 2) !== "*/") i += 1;
      i += 2;
      continue;
    }
    const ch = source[i];
    if (ch === "'" || ch === '"') {
      const start = i;
      i += 1;
      while (i < n && source[i] !== ch) {
        if (source[i] === "\\") i += 1;
        i += 1;
      }
      i += 1;
      // Keep the literal body: `${l10n.accuracy}` only exists inside a string.
      out += ` ${source.slice(start, i)} `;
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
};

/**
 * Removes comments and string literals, then balances delimiters.
 * Interpolation braces live inside literals and are balanced there, so treating a
 * literal as opaque keeps the running totals correct in practice.
 */
const strip = (source) => {
  let out = "";
  let i = 0;
  const n = source.length;

  while (i < n) {
    const two = source.slice(i, i + 2);

    if (two === "//") {
      while (i < n && source[i] !== "\n") i += 1;
      continue;
    }
    if (two === "/*") {
      i += 2;
      while (i < n && source.slice(i, i + 2) !== "*/") i += 1;
      i += 2;
      continue;
    }

    const ch = source[i];
    if (ch === "'" || ch === '"') {
      // Raw strings (r'...') and triple-quoted strings behave differently enough to
      // matter; handle both rather than produce a false positive.
      const triple = source.slice(i, i + 3);
      if (triple === "'''" || triple === '"""') {
        i += 3;
        while (i < n && source.slice(i, i + 3) !== triple) {
          if (source[i] === "\\") i += 1;
          i += 1;
        }
        i += 3;
        continue;
      }
      i += 1;
      while (i < n && source[i] !== ch) {
        if (source[i] === "\\") i += 1;
        i += 1;
      }
      i += 1;
      continue;
    }

    out += ch;
    i += 1;
  }
  return out;
};

const balance = (stripped, file) => {
  const openers = { "(": ")", "{": "}", "[": "]" };
  const closers = new Set([")", "}", "]"]);
  const stack = [];

  for (let i = 0; i < stripped.length; i += 1) {
    const ch = stripped[i];
    if (openers[ch]) stack.push({ ch, at: i });
    else if (closers.has(ch)) {
      const top = stack.pop();
      if (!top || openers[top.ch] !== ch) {
        errors.push(`${relative(ROOT, file)}: unbalanced "${ch}" at offset ${i}`);
        return;
      }
    }
  }
  if (stack.length) {
    const top = stack[stack.length - 1];
    errors.push(`${relative(ROOT, file)}: unclosed "${top.ch}" at offset ${top.at}`);
  }
};

/* -------------------------------------------------------------- 1. balance */

const files = walk(LIB);
const sources = new Map();

for (const file of files) {
  const source = readFileSync(file, "utf8");
  sources.set(file, source);
  checkedFiles += 1;
  const stripped = strip(source);
  balance(stripped, file);
}

/* -------------------------------------------------------------- 2. imports */

for (const [file, source] of sources) {
  for (const match of source.matchAll(/^\s*(?:import|export)\s+'([^']+)'/gm)) {
    const spec = match[1];
    let target = null;

    // `app_localizations.dart` is generated by `flutter gen-l10n` and is deliberately
    // not committed; its absence is expected, not a broken import.
    if (spec.endsWith("l10n/app_localizations.dart")) continue;

    if (spec.startsWith("package:grid_and_glory/")) {
      target = join(LIB, spec.slice("package:grid_and_glory/".length));
    } else if (spec.startsWith(".")) {
      target = resolve(dirname(file), spec);
    } else {
      continue; // package:flutter, package:riverpod, dart:io …
    }

    if (!existsSync(target)) {
      errors.push(`${relative(ROOT, file)}: import "${spec}" does not resolve`);
    }
  }
}

/* -------------------------------------------------------------- 3. l10n keys */

const enArb = JSON.parse(readFileSync(join(LIB, "l10n", "app_en.arb"), "utf8"));
const arArb = JSON.parse(readFileSync(join(LIB, "l10n", "app_ar.arb"), "utf8"));
const enKeys = new Set(Object.keys(enArb).filter((k) => !k.startsWith("@")));
const arKeys = new Set(Object.keys(arArb).filter((k) => !k.startsWith("@")));

const usedKeys = new Map();
for (const [file, source] of sources) {
  // Comments are removed (a doc example must not demand an ARB key) but string
  // literals are kept, because `'${l10n.accuracy}: …'` is a genuine usage.
  for (const match of stripComments(source).matchAll(/\bl10n\.([A-Za-z][A-Za-z0-9]*)/g)) {
    const key = match[1];
    if (!usedKeys.has(key)) usedKeys.set(key, new Set());
    usedKeys.get(key).add(relative(ROOT, file));
  }
}

for (const [key, where] of usedKeys) {
  if (!enKeys.has(key)) {
    errors.push(`l10n.${key} used in ${[...where].join(", ")} but missing from app_en.arb`);
  }
  if (!arKeys.has(key)) {
    errors.push(`l10n.${key} used in ${[...where].join(", ")} but missing from app_ar.arb`);
  }
}

for (const key of enKeys) {
  if (!arKeys.has(key)) errors.push(`app_ar.arb is missing "${key}"`);
}
for (const key of arKeys) {
  if (!enKeys.has(key)) errors.push(`app_en.arb is missing "${key}"`);
}
for (const key of enKeys) {
  if (!usedKeys.has(key)) warnings.push(`ARB key "${key}" is never used`);
}

/* --------------------------------------------------- 4. placeholder parity */

const placeholdersOf = (arb, key) => {
  const meta = arb[`@${key}`];
  return new Set(Object.keys(meta?.placeholders ?? {}));
};

for (const key of enKeys) {
  const a = placeholdersOf(enArb, key);
  const b = placeholdersOf(arArb, key);
  const missing = [...a].filter((p) => !b.has(p));
  const extra = [...b].filter((p) => !a.has(p));
  if (missing.length) errors.push(`"${key}" has placeholder(s) ${missing} in en but not ar`);
  if (extra.length) errors.push(`"${key}" has placeholder(s) ${extra} in ar but not en`);

  // A placeholder declared but not present in the string is a silent "{count}" on screen.
  for (const p of a) {
    if (!String(enArb[key]).includes(`{${p}}`)) {
      errors.push(`"${key}" declares placeholder "${p}" but the en string does not use it`);
    }
    if (!String(arArb[key]).includes(`{${p}}`)) {
      errors.push(`"${key}" declares placeholder "${p}" but the ar string does not use it`);
    }
  }
}

/* --------------------------------------------------- 5. directional layout */

const RTL_VIOLATIONS = [
  { re: /EdgeInsets\.only\(\s*(left|right)\s*:/g, what: "EdgeInsets.only(left/right)" },
  { re: /EdgeInsets\.fromLTRB\(/g, what: "EdgeInsets.fromLTRB" },
  { re: /Positioned\(\s*(left|right)\s*:/g, what: "Positioned(left/right)" },
  { re: /Alignment\.center(Left|Right)/g, what: "Alignment.centerLeft/Right" },
  { re: /BorderRadius\.only\([^)]*\b(topLeft|topRight|bottomLeft|bottomRight)\b/g, what: "BorderRadius.only(corner)" },
];

for (const [file, source] of sources) {
  const stripped = strip(source);
  for (const { re, what } of RTL_VIOLATIONS) {
    for (const match of stripped.matchAll(re)) {
      errors.push(
        `${relative(ROOT, file)}: ${what} — use the directional variant or the app breaks in Arabic`,
      );
    }
  }
}

/* --------------------------------------------------------------- 6. report */

console.log(`\nGrid & Glory — Flutter structural check (${checkedFiles} Dart files, ${enKeys.size} l10n keys)`);

if (warnings.length) {
  console.log(`\n⚠ ${warnings.length} warning(s)`);
  for (const w of warnings) console.log(`  - ${w}`);
}

if (errors.length) {
  console.log(`\n✖ ${errors.length} error(s)`);
  for (const e of errors) console.log(`  - ${e}`);
  console.log("\nFAILED — this is a structural approximation, not dart analyze.\n");
  process.exit(1);
}

console.log("\n✓ PASSED — balance, imports, l10n keys, placeholder parity, RTL layout rules");
console.log("  (structural only: run `flutter analyze` once an SDK is available)\n");

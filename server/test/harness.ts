/**
 * test/harness.ts — zero-dependency test runner.
 *
 * Node executes TypeScript directly, so the server tests need no build step and no
 * test framework. `node server/test/scoring.test.ts` is the whole instruction.
 *
 * Engine tests are synchronous (the engine has no I/O). Tests that genuinely need to
 * await something — a real socket handshake — register with `testAsync` and the file
 * must `await runDeferred()` before `summarize()`. That is explicit on purpose: an
 * un-awaited async test silently reports success, which is worse than no test.
 */

import assert from "node:assert/strict";

let passed = 0;
const failures: Array<{ name: string; error: unknown }> = [];
const started = Date.now();

export const test = (name: string, fn: () => void): void => {
  try {
    const result = fn() as unknown;
    if (result instanceof Promise) {
      throw new Error("async test rejected — the engine under test must stay synchronous");
    }
    passed += 1;
  } catch (error) {
    failures.push({ name, error });
  }
};

const deferred: Array<{ name: string; fn: () => Promise<void> }> = [];

/** Register an async test. The file MUST `await runDeferred()` before `summarize()`. */
export const testAsync = (name: string, fn: () => Promise<void>): void => {
  deferred.push({ name, fn });
};

export const runDeferred = async (): Promise<void> => {
  for (const t of deferred) {
    try {
      await t.fn();
      passed += 1;
    } catch (error) {
      failures.push({ name: t.name, error });
    }
  }
};

export const summarize = (suite: string): void => {
  const ms = Date.now() - started;
  if (failures.length === 0) {
    console.log(`\n✓ ${suite}: ${passed} passed in ${ms} ms`);
    return;
  }
  console.log(`\n✖ ${suite}: ${failures.length} failed, ${passed} passed in ${ms} ms`);
  for (const f of failures) {
    console.log(`\n  ✖ ${f.name}`);
    const err = f.error;
    if (err instanceof Error) {
      console.log(String(err.message).split("\n").map((l) => `      ${l}`).join("\n"));
    } else {
      console.log(`      ${String(err)}`);
    }
  }
  process.exitCode = 1;
};

export { assert };

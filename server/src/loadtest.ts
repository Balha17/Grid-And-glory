/**
 * loadtest.ts — how much match can one process actually simulate?
 *
 * docs/01-technical-architecture.md claims "~1 200 concurrent matches per node at p99
 * tick jitter < 15 ms". That number was an estimate. This script measures the part that
 * is measurable without a network: the cost of advancing N live matches one tick.
 *
 *   node server/src/loadtest.ts --matches=200
 *
 * Scope, stated honestly:
 *   INCLUDED  matchmaking pass, room advancement, scoring, rendering, token signing,
 *             gateway routing
 *   EXCLUDED  socket I/O, JSON serialisation, TLS, GC pressure from real payloads
 *
 * So this is a CEILING, not a capacity plan. If the engine cannot do it, the node cannot.
 */

import { Gateway } from "./gateway.ts";
import { loadBank } from "./bank-loader.ts";
import type { Connection } from "./connection.ts";

const argValue = (name: string, fallback: number): number => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? Number(hit.split("=")[1]) : fallback;
};

const MATCHES = Math.max(1, argValue("matches", 200));
const PLAYERS = MATCHES * 2;
const TICK_MS = 50;
const MAX_TICKS = 40_000;

/** Keeps only what a bot needs to answer, so a 2 000-player run does not hold 400 MB. */
class BotConnection implements Connection {
  readonly id: string;
  sent = 0;
  roundsDelivered = 0;
  pending: { token: string; questionId: string; roundNo: number } | null = null;

  constructor(id: string) {
    this.id = id;
  }

  send(type: string, payload: unknown): void {
    this.sent += 1;
    if (type === "round.question") this.roundsDelivered += 1;
    if (type !== "round.question" && type !== "shoot.question") return;
    const p = payload as {
      token: string;
      roundNo: number;
      youAreShooting?: boolean;
      view: { questionId: string };
    };
    if (type === "shoot.question" && p.youAreShooting !== true) return;
    this.pending = { token: p.token, questionId: p.view.questionId, roundNo: p.roundNo };
  }

  close(): void {}
}

const bank = await loadBank();
const answerKey = new Map(bank.questions.map((q) => [q.id, q]));
const clock = { now: 1_000_000 };
const gateway = new Gateway({ bank, clock: () => clock.now });

const frame = (type: string, payload: unknown): string =>
  JSON.stringify({ v: 1, type, seq: 0, ts: 0, payload });

const bots: BotConnection[] = [];
for (let i = 0; i < PLAYERS; i += 1) {
  const conn = new BotConnection(`bot_${i}`);
  bots.push(conn);
  gateway.handleConnection(conn);
  gateway.handleFrame(
    conn,
    frame("hello", {
      deviceId: `device_${i}`,
      // Alternate locales: half the matches are cross-language by construction.
      locale: i % 2 === 0 ? "en" : "ar",
      region: "EU",
    }),
  );
  gateway.handleFrame(conn, frame("queue.join", {}));
}

console.log(`\nGrid & Glory — engine load test`);
console.log(`players ${PLAYERS}  •  matches ${MATCHES}  •  tick ${TICK_MS} ms (virtual)\n`);

/* ---------------------------------------------------------------- pairing */

clock.now += 300;
const pairStart = performance.now();
gateway.tick(clock.now);
const pairMs = performance.now() - pairStart;
const afterPair = gateway.stats();

console.log(`pairing      ${pairMs.toFixed(1)} ms for ${afterPair.matchesStarted} matches`);
console.log(`             ${(pairMs / Math.max(1, afterPair.matchesStarted)).toFixed(2)} ms per match created`);

if (afterPair.liveMatches === 0) {
  console.error("\nnothing paired — this run measures nothing\n");
  process.exit(1);
}

/* ------------------------------------------------------------- simulation */

const lcg = (seed: number) => {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
};

const tickCost: number[] = [];
let ticks = 0;
let roundsServed = 0;
let answersSent = 0;

const simStart = performance.now();

while (gateway.stats().liveMatches > 0 && ticks < MAX_TICKS) {
  clock.now += TICK_MS;
  const t0 = performance.now();
  gateway.tick(clock.now);
  tickCost.push(performance.now() - t0);

  for (let i = 0; i < bots.length; i += 1) {
    const bot = bots[i];
    if (!bot.pending) continue;
    const doc = answerKey.get(bot.pending.questionId);
    if (!doc) {
      bot.pending = null;
      continue;
    }
    const random = lcg(i * 7919 + bot.pending.roundNo);
    const correct = random() < 0.72;
    const optionId = correct
      ? doc.answerOptionId
      : (doc.options.find((o) => o.id !== doc.answerOptionId)?.id ?? doc.options[0].id);
    gateway.handleFrame(bot, frame("round.answer", {
      token: bot.pending.token,
      optionId,
      clientMs: clock.now,
    }));
    bot.pending = null;
    answersSent += 1;
    roundsServed += 1;
  }

  ticks += 1;
}

const simMs = performance.now() - simStart;
const final = gateway.stats();

/* ------------------------------------------------------------------ report */

const sorted = [...tickCost].sort((a, b) => a - b);
const mean = tickCost.reduce((s, v) => s + v, 0) / (tickCost.length || 1);
const p50 = sorted[Math.floor(sorted.length * 0.5)] ?? 0;
const p95 = sorted[Math.floor(sorted.length * 0.95)] ?? 0;
const p99 = sorted[Math.floor(sorted.length * 0.99)] ?? 0;
const max = sorted[sorted.length - 1] ?? 0;

const perMatchTickUs = (mean / Math.max(1, MATCHES)) * 1000;

console.log(`\nsimulation   ${simMs.toFixed(0)} ms wall for ${ticks} ticks`);
console.log(`matches      ${final.matchesStarted} started, ${final.liveMatches} still live`);
const rounds = bots.reduce((s, b) => s + b.roundsDelivered, 0) / 2;
console.log(`rounds       ${Math.round(rounds)} served  •  ${(rounds / Math.max(1, final.matchesStarted)).toFixed(1)} per match  •  ${answersSent} answers`);
console.log(`frames       ${bots.reduce((s, b) => s + b.sent, 0).toLocaleString()} outbound\n`);

console.log(`tick cost    mean ${mean.toFixed(2)} ms  •  p50 ${p50.toFixed(2)}  •  p95 ${p95.toFixed(2)}  •  p99 ${p99.toFixed(2)}  •  max ${max.toFixed(2)}`);
console.log(`per match    ${perMatchTickUs.toFixed(1)} µs of a tick`);

/*
 * Capacity must be derived from p99, not the mean.
 *
 * The tick is a DEADLINE, not an average: one slow tick delays every answer in the
 * process, and the mean is dominated by ticks where nothing happens to transition.
 * Sizing on the mean is how a service looks healthy in a graph and jitters in a match.
 */
const budgetMs = 50;
const perMatchP99Ms = p99 / Math.max(1, MATCHES);
const perMatchMeanMs = mean / Math.max(1, MATCHES);
const ceiling = budgetMs / Math.max(0.000001, perMatchP99Ms);
const typical = budgetMs / Math.max(0.000001, perMatchMeanMs);

console.log(`\ncapacity     p99 ${(perMatchP99Ms * 1000).toFixed(1)} µs/match  →  ~${Math.round(ceiling).toLocaleString()} matches/core at 100% CPU`);
console.log(`             mean ${(perMatchMeanMs * 1000).toFixed(1)} µs/match →  ~${Math.round(typical).toLocaleString()} matches/core (optimistic)`);
console.log(`             ~${Math.round(ceiling / 2).toLocaleString()} matches/core at a sane 50% utilisation`);
console.log(`\nnote: engine only — no sockets, no JSON, no GC. Treat as a ceiling, not a plan.\n`);

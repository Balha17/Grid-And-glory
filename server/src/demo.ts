/**
 * demo.ts — play one full match and print the play-by-play.
 *
 * The fastest way to sanity-check a rules change: the output is the game as a player
 * experiences it, produced by the same engine that runs in production.
 *
 *   node server/src/demo.ts
 */

import { MatchRoom } from "./match-room.ts";
import { drawPool, loadBank } from "./bank-loader.ts";
import type { Outbound, PlayerRef, QuestionView } from "./types.ts";

const bank = await loadBank();

const ALICE: PlayerRef = {
  playerId: "p_alice",
  displayName: "Alice",
  locale: "en",
  region: "EU",
  rating: 1_240,
};

const OMAR: PlayerRef = {
  playerId: "p_omar",
  displayName: "عمر",
  locale: "ar",
  region: "MENA",
  rating: 1_205,
};

const pad = (n: number, w = 2): string => String(n).padStart(w, " ");
const clock = (ms: number): string => `${(ms / 1000).toFixed(1).padStart(6)}s`;

/** Deterministic bots: decent, not perfect, and worse on harder questions. */
const lcg = (seed: number) => {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
};

const random = lcg(0x9e3779b9);
const accuracyFor = (playerId: string, difficulty: number): number => {
  const base = playerId === ALICE.playerId ? 0.88 : 0.76;
  return Math.max(0.2, base - (difficulty - 2) * 0.12);
};

const room = new MatchRoom({
  matchId: "m_demo_0001",
  players: [ALICE, OMAR],
  pool: drawPool(bank.questions, 18, 424242),
  shotPool: bank.shotQuestions,
  catalog: bank.catalog,
});

let now = 0;
let tokens: Record<string, string> = {};
const firstViews: Record<string, QuestionView> = {};
let printedSplit = false;
let roundToAnswer = -1;
let shooterToAnswer: string | null = null;
const seen: Record<string, number> = {};

const log = (line: string): void => {
  console.log(`${clock(now)}  ${line}`);
};

const handle = (out: Outbound[]): void => {
  for (const env of out) {
    const p = env.payload as Record<string, unknown>;
    seen[env.type] = (seen[env.type] ?? 0) + 1;
    const goals = p.goals as Record<string, number> | undefined;
    const zones = p.zones as Record<string, number> | undefined;

    switch (env.type) {
      case "match.start":
        if (env.to === ALICE.playerId) {
          log(`🟢 KICKOFF  ${ALICE.displayName} (EN) vs ${OMAR.displayName} (AR) — same question, two languages`);
        }
        break;

      case "round.question": {
        tokens[env.to as string] = p.token as string;

        // Show the core feature once: the same question, rendered twice.
        if ((p.roundNo as number) === 1) {
          firstViews[env.to as string] = p.view as QuestionView;
          if (!printedSplit && firstViews[ALICE.playerId] && firstViews[OMAR.playerId]) {
            printedSplit = true;
            const en = firstViews[ALICE.playerId];
            const ar = firstViews[OMAR.playerId];
            console.log(`\n  ── one question, two locales (id ${en.questionId}) ──`);
            console.log(`   EN [${en.dir}] ${en.prompt}`);
            console.log(`   AR [${ar.dir}] ${ar.prompt}`);
            console.log(`   EN options: ${en.options.map((o) => o.text).join(" · ")}`);
            console.log(`   AR options: ${ar.options.map((o) => o.text).join(" · ")}\n`);
          }
        }

        if (env.to !== ALICE.playerId) break;
        roundToAnswer = p.roundNo as number;
        const view = p.view as QuestionView;
        const prompt = view.prompt.length > 58 ? `${view.prompt.slice(0, 55)}…` : view.prompt;
        log(`R${pad(p.roundNo as number)} [${view.format}/${view.difficulty}] ${prompt}`);
        break;
      }

      case "round.reveal": {
        if (env.to !== ALICE.playerId) break;
        const delta = p.delta as number;
        const sign = delta > 0 ? `+${delta}` : `${delta}`;
        const mark = p.outcome === "correct" ? "✓" : p.outcome === "wrong" ? "✗" : "…";
        const verdict = p.fastest ? "fastest" : p.outcome === "correct" ? "slower" : String(p.outcome);
        const turn = p.opponentOutcome === "correct" ? "" : "  ⇄ turnover";
        log(
          `     ${mark} ${verdict.padEnd(8)} ${sign.padStart(2)} zone   ` +
            `A:Z${zones?.[ALICE.playerId]} B:Z${zones?.[OMAR.playerId]}   ` +
            `"${p.correctOptionText}"${turn}`,
        );
        break;
      }

      case "shoot.question": {
        tokens[env.to as string] = p.token as string;
        shooterToAnswer = p.shooterId as string;
        if (env.to !== ALICE.playerId) break;
        const shooter = p.youAreShooting ? "Alice" : "عمر";
        log(`🎯 SHOOTING CHANCE — ${shooter} shoots (difficulty ${p.difficulty}, 5 s, clock stopped)`);
        break;
      }

      case "shoot.reveal":
        if (env.to !== ALICE.playerId) break;
        log(
          `     ${p.scored ? "⚽ GOAL" : "🧤 SAVED"}   ` +
            `A:${goals?.[ALICE.playerId]} B:${goals?.[OMAR.playerId]}   ` +
            `shooter back to Z${zones?.[p.shooterId as string]}`,
        );
        break;

      case "match.half":
        log(`⏸  HALF TIME   A:${goals?.[ALICE.playerId]} B:${goals?.[OMAR.playerId]} — stats card for 6 s`);
        break;

      case "match.second_half":
        log("🟢 SECOND HALF — possession swapped, clock reset to 45:00");
        break;

      case "match.end":
        if (env.to !== ALICE.playerId) break;
        log(`🏁 FULL TIME   ${String(p.outcome).toUpperCase()} for Alice (decided by ${p.decidedBy})`);
        break;

      default:
        break;
    }
  }
};

handle(room.start(now));

const STEP_MS = 100;
let guard = 0;

while (!room.isFinished && guard < 30_000) {
  guard += 1;
  now += STEP_MS;
  handle(room.advance(now));

  // --- normal round: both players answer, at slightly different speeds
  if (room.phaseName === "question_open" && roundToAnswer !== -1) {
    roundToAnswer = -1;
    const audit = room.audit;
    const doc = audit ? bank.questions.find((q) => q.id === audit.questionId) : undefined;
    if (audit && doc) {
      for (const player of [ALICE, OMAR]) {
        const token = tokens[player.playerId];
        if (!token) continue;
        const correct = random() < accuracyFor(player.playerId, doc.difficulty);
        const optionId = correct
          ? audit.answerOptionId
          : (doc.options.find((o) => o.id !== audit.answerOptionId)?.id ?? "opt_x");
        handle(room.submitAnswer(player.playerId, { token, optionId }, now));
        // a human does not answer both players in the same millisecond
        if (player.playerId === OMAR.playerId) now += 420;
      }
    }
  }

  // --- shooting chance: only the nominated shooter can answer
  if (room.phaseName === "shooting_chance" && shooterToAnswer) {
    const shooter = shooterToAnswer;
    shooterToAnswer = null;
    const audit = room.audit;
    const doc = audit ? bank.questions.find((q) => q.id === audit.questionId) : undefined;
    const token = tokens[shooter];
    if (audit && doc && token) {
      const correct = random() < 0.62;
      const optionId = correct
        ? audit.answerOptionId
        : (doc.options.find((o) => o.id !== audit.answerOptionId)?.id ?? "opt_x");
      handle(room.submitAnswer(shooter, { token, optionId }, now));
    }
  }
}

const goals = room.result.goals;
console.log(
  `\n  FULL TIME   ${ALICE.displayName} ${goals[ALICE.playerId]} – ${goals[OMAR.playerId]} ${OMAR.displayName}`,
);
console.log(`  zones       A:Z${room.result.zones[ALICE.playerId]}  B:Z${room.result.zones[OMAR.playerId]}`);
console.log(
  `  messages    ${seen["round.question"] ? seen["round.question"] / 2 : 0} questions · ` +
    `${(seen["shoot.question"] ?? 0) / 2} shots · ` +
    `${(seen["match.half"] ?? 0) / 2} half-time`,
);
console.log(`  transitions ${room.eventLog.length} recorded server-side\n`);

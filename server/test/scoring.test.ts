/**
 * The rulebook as executable assertions. Every row of product spec §2.3 and every
 * tiebreak in §2.5 appears here exactly once.
 */

import { assert, summarize, test } from "./harness.ts";
import {
  clampZone,
  decideMatch,
  eloDelta,
  isShotAvailable,
  resolveRound,
  zoneAfterShot,
} from "../src/scoring.ts";
import { PITCH, SCORE } from "../src/config.ts";
import type { SubmittedAnswer } from "../src/types.ts";

const TIMING = { windowOpensAt: 1_000, windowEndsAt: 10_000 };
const A = "p_a";
const B = "p_b";

const answer = (playerId: string, optionId: string, receivedAt: number): SubmittedAnswer => ({
  playerId,
  optionId,
  receivedAt,
});

const resolve = (a: SubmittedAnswer | undefined, b: SubmittedAnswer | undefined) =>
  resolveRound({
    answerOptionId: "opt_right",
    timing: TIMING,
    answers: new Map(
      [a, b].filter((x): x is SubmittedAnswer => x !== undefined).map((x) => [x.playerId, x]),
    ),
    playerIds: [A, B],
  });

/* ---------------------------------------------------------------- movement */

test("both correct: earlier answerer gets +2, later gets +1", () => {
  const r = resolve(answer(A, "opt_right", 2_000), answer(B, "opt_right", 3_200));
  assert.equal(r.results[A].delta, SCORE.FAST);
  assert.equal(r.results[B].delta, SCORE.SLOW);
  assert.deepEqual(r.fastestIds, [A]);
  assert.equal(r.jitterTie, false);
});

test("answers within the jitter grace both count as fastest", () => {
  const r = resolve(answer(A, "opt_right", 2_000), answer(B, "opt_right", 2_000 + SCORE.JITTER_GRACE_MS - 1));
  assert.equal(r.results[A].delta, SCORE.FAST);
  assert.equal(r.results[B].delta, SCORE.FAST, "a coin flip must not decide the round");
  assert.equal(r.jitterTie, true);
});

test("answers exactly at the jitter grace boundary are NOT tied", () => {
  const r = resolve(answer(A, "opt_right", 2_000), answer(B, "opt_right", 2_000 + SCORE.JITTER_GRACE_MS));
  assert.equal(r.results[A].delta, SCORE.FAST);
  assert.equal(r.results[B].delta, SCORE.SLOW);
  assert.equal(r.jitterTie, false);
});

test("correct vs wrong: +2 for the correct player, turnover for the other", () => {
  const r = resolve(answer(A, "opt_right", 4_000), answer(B, "opt_wrong", 2_000));
  assert.equal(r.results[A].delta, SCORE.FAST, "answering faster is worthless if it is wrong");
  assert.equal(r.results[B].delta, SCORE.TURNOVER);
  assert.equal(r.results[B].outcome, "wrong");
});

test("sole correct answer is automatically the fastest", () => {
  const r = resolve(answer(A, "opt_right", 9_500), undefined);
  assert.equal(r.results[A].delta, SCORE.FAST);
  assert.equal(r.results[B].outcome, "no_answer");
  assert.equal(r.results[B].delta, SCORE.TURNOVER);
});

test("a lone correct answer at the last millisecond still gets +2", () => {
  const r = resolve(answer(A, "opt_right", TIMING.windowEndsAt), undefined);
  assert.equal(r.results[A].delta, SCORE.FAST);
  assert.equal(r.results[A].late, false);
});

/* ------------------------------------------------------------------ timing */

test("late-but-in-window-grace answer counts for correctness but cannot be fastest", () => {
  const r = resolve(answer(A, "opt_right", TIMING.windowEndsAt + 100), undefined);
  assert.equal(r.results[A].outcome, "correct");
  assert.equal(r.results[A].late, true);
  assert.equal(r.results[A].delta, SCORE.SLOW, "late answers never earn the speed bonus");
  assert.deepEqual(r.fastestIds, []);
});

test("an on-time answer beats a late one regardless of correctness order", () => {
  const r = resolve(answer(A, "opt_right", TIMING.windowEndsAt - 200), answer(B, "opt_right", TIMING.windowEndsAt + 20));
  assert.equal(r.results[A].delta, SCORE.FAST);
  assert.equal(r.results[B].delta, SCORE.SLOW);
  assert.deepEqual(r.fastestIds, [A]);
});

test("an answer past window + grace is discarded as no answer", () => {
  const late = TIMING.windowEndsAt + SCORE.LATE_GRACE_MS + 1;
  const r = resolve(answer(A, "opt_right", late), undefined);
  assert.equal(r.results[A].outcome, "no_answer");
  assert.equal(r.results[A].delta, SCORE.TURNOVER);
  assert.equal(r.results[A].late, true, "recorded as late for telemetry even though discarded");
});

test("nobody answers: both lose a zone", () => {
  const r = resolve(undefined, undefined);
  assert.equal(r.results[A].delta, SCORE.TURNOVER);
  assert.equal(r.results[B].delta, SCORE.TURNOVER);
});

test("both wrong: both lose a zone, nobody is rewarded", () => {
  const r = resolve(answer(A, "opt_wrong", 1_500), answer(B, "opt_also_wrong", 1_600));
  assert.equal(r.results[A].delta, SCORE.TURNOVER);
  assert.equal(r.results[B].delta, SCORE.TURNOVER);
  assert.deepEqual(r.fastestIds, []);
});

/* -------------------------------------------------------------------- pitch */

test("zones clamp at the goal line and at the back of the net", () => {
  assert.equal(clampZone(7), PITCH.ZONE_MAX);
  assert.equal(clampZone(-3), PITCH.ZONE_MIN);
  assert.equal(clampZone(3), 3);
});

test("a Shooting Chance is only available at zone 5 and off cooldown", () => {
  assert.equal(isShotAvailable({ zone: 5, goals: 0, cooldownUntil: 0 }, 10_000), true);
  assert.equal(isShotAvailable({ zone: 4, goals: 0, cooldownUntil: 0 }, 10_000), false);
  assert.equal(isShotAvailable({ zone: 5, goals: 0, cooldownUntil: 20_000 }, 10_000), false);
});

test("after a goal you restart at zone 2; after a miss, zone 3", () => {
  assert.equal(zoneAfterShot(true), PITCH.ZONE_AFTER_GOAL);
  assert.equal(zoneAfterShot(false), PITCH.ZONE_AFTER_MISS);
  assert.ok(zoneAfterShot(true) < zoneAfterShot(false), "scoring should not be punished more than missing");
});

/* ------------------------------------------------------------------ result */

const leg = (playerId: string, goals: number, zone: number, correct: number, correctTimeMs: number) => ({
  playerId,
  goals,
  zone,
  correct,
  correctTimeMs,
  rating: 1_000,
});

test("match is decided by goals first", () => {
  const r = decideMatch({ matchId: "m1", players: [leg(A, 2, 1, 4, 9_000), leg(B, 1, 5, 9, 1_000)] });
  assert.equal(r.outcomeByPlayer[A], "win");
  assert.equal(r.decidedBy, "goals");
});

test("equal goals: zone decides", () => {
  const r = decideMatch({ matchId: "m1", players: [leg(A, 1, 4, 5, 9_000), leg(B, 1, 3, 2, 1_000)] });
  assert.equal(r.outcomeByPlayer[A], "win");
  assert.equal(r.decidedBy, "zone");
});

test("equal goals and zone: correct answers decide", () => {
  const r = decideMatch({ matchId: "m1", players: [leg(A, 1, 3, 6, 9_000), leg(B, 1, 3, 5, 1_000)] });
  assert.equal(r.outcomeByPlayer[A], "win");
  assert.equal(r.decidedBy, "correct");
});

test("everything equal but time: the faster correct answerer wins", () => {
  const r = decideMatch({ matchId: "m1", players: [leg(A, 1, 3, 5, 4_000), leg(B, 1, 3, 5, 8_000)] });
  assert.equal(r.outcomeByPlayer[A], "win", "lower total correct-answer time wins");
  assert.equal(r.decidedBy, "time");
});

test("identical scorelines are a draw", () => {
  const r = decideMatch({ matchId: "m1", players: [leg(A, 1, 3, 5, 4_000), leg(B, 1, 3, 5, 4_000)] });
  assert.equal(r.outcomeByPlayer[A], "draw");
  assert.deepEqual(r.ranking, []);
  assert.equal(r.decidedBy, "draw");
});

test("Elo: equal ratings move symmetrically, and a newcomer's K is larger", () => {
  const win = eloDelta(1_000, 1_000, 1, 50);
  const loss = eloDelta(1_000, 1_000, 0, 50);
  assert.equal(win, -loss, "zero-sum at equal ratings");
  assert.ok(Math.abs(eloDelta(1_000, 1_000, 1, 2)) > Math.abs(win), "provisional players move faster");
});

summarize("scoring");

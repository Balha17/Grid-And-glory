/**
 * scoring.ts — the pure heart of the game.
 *
 * No timers, no I/O, no randomness. Given the question's answer key and what each
 * player submitted (with server timestamps), it returns exactly what the pitch does.
 * Every rule in docs/00-product-spec.md §2.3 is one branch in here, which is why the
 * unit test file can prove the whole rulebook.
 */

import { PITCH, SCORE } from "./config.ts";
import type {
  PlayerId,
  PlayerRoundResult,
  RoundResolution,
  SubmittedAnswer,
} from "./types.ts";

export const clampZone = (zone: number): number =>
  Math.min(PITCH.ZONE_MAX, Math.max(PITCH.ZONE_MIN, zone));

export interface RoundTiming {
  /** Server ms when the window opened (same instant the client saw the question). */
  windowOpensAt: number;
  /** Server ms when the window closes. */
  windowEndsAt: number;
}

export interface ResolveInput {
  answerOptionId: string;
  timing: RoundTiming;
  answers: Map<PlayerId, SubmittedAnswer>;
  playerIds: [PlayerId, PlayerId];
}

/**
 * Classify one player's submission.
 *
 * The three-way split that matters: correctness, lateness, and eligibility for the
 * speed bonus. A late-but-correct answer is still worth a zone; it just cannot be
 * the fastest, because it arrived after the clock the other player was racing.
 */
const classify = (
  playerId: PlayerId,
  answer: SubmittedAnswer | undefined,
  input: ResolveInput,
): PlayerRoundResult => {
  if (!answer) {
    return { outcome: "no_answer", delta: SCORE.TURNOVER, late: false, elapsedMs: null, fastest: false };
  }

  const { windowOpensAt, windowEndsAt } = input.timing;
  const elapsedMs = answer.receivedAt - windowOpensAt;

  // Outside the window + grace: the server never saw an answer in time.
  if (answer.receivedAt > windowEndsAt + SCORE.LATE_GRACE_MS) {
    return { outcome: "no_answer", delta: SCORE.TURNOVER, late: true, elapsedMs, fastest: false };
  }

  const correct = answer.optionId === input.answerOptionId;
  if (!correct) {
    return { outcome: "wrong", delta: SCORE.TURNOVER, late: false, elapsedMs, fastest: false };
  }

  return {
    outcome: "correct",
    delta: SCORE.SLOW, // provisional; promoted to FAST below if it wins the speed race
    late: answer.receivedAt > windowEndsAt,
    elapsedMs,
    fastest: false,
  };
};

/**
 * Resolve a round.
 *
 * Order of operations is load-bearing:
 *   1. classify both players
 *   2. among *eligible* correct answers (on time), find the fastest
 *   3. if the two eligible answers are inside the jitter grace, BOTH are fastest
 *   4. promote fastest -> +2, leave the other correct at +1, everyone else -1
 */
export const resolveRound = (input: ResolveInput): RoundResolution => {
  const [aId, bId] = input.playerIds;

  const results: Record<PlayerId, PlayerRoundResult> = {
    [aId]: classify(aId, input.answers.get(aId), input),
    [bId]: classify(bId, input.answers.get(bId), input),
  };

  // Eligible = correct AND inside the window. Late answers are excluded by design.
  const eligible = [aId, bId]
    .map((id) => ({ id, result: results[id], answer: input.answers.get(id) }))
    .filter((e) => e.result.outcome === "correct" && !e.result.late)
    .sort((x, y) => (x.answer!.receivedAt - y.answer!.receivedAt));

  const fastestIds: PlayerId[] = [];
  let jitterTie = false;

  if (eligible.length === 1) {
    fastestIds.push(eligible[0].id);
  } else if (eligible.length === 2) {
    const gap = eligible[1].answer!.receivedAt - eligible[0].answer!.receivedAt;
    if (gap < SCORE.JITTER_GRACE_MS) {
      // Unseparably close: punishing the coin flip would make a fair game feel rigged.
      jitterTie = true;
      fastestIds.push(eligible[0].id, eligible[1].id);
    } else {
      fastestIds.push(eligible[0].id);
    }
  }

  for (const id of fastestIds) {
    results[id] = { ...results[id], fastest: true, delta: SCORE.FAST };
  }

  return { results, fastestIds, jitterTie };
};

/* ------------------------------------------------------------- shot gating */

export interface ShotGate {
  zone: number;
  goals: number;
  cooldownUntil: number;
}

export const isShotAvailable = (gate: ShotGate, now: number): boolean =>
  gate.zone >= PITCH.ZONE_MAX && now >= gate.cooldownUntil;

/** Zone after a Shooting Chance resolves. */
export const zoneAfterShot = (scored: boolean): number =>
  scored ? PITCH.ZONE_AFTER_GOAL : PITCH.ZONE_AFTER_MISS;

/* ------------------------------------------------------------------ result */

export interface MatchResultInput {
  matchId: string;
  players: Array<{
    playerId: PlayerId;
    goals: number;
    zone: number;
    correct: number;
    correctTimeMs: number;
    rating: number;
  }>;
}

export type MatchOutcome = "win" | "loss" | "draw";

export interface MatchResult {
  matchId: string;
  /** Ordered winner-first; empty on a draw. */
  ranking: PlayerId[];
  outcomeByPlayer: Record<PlayerId, MatchOutcome>;
  decidedBy: "goals" | "zone" | "correct" | "time" | "draw";
}

/**
 * Lexicographic tiebreak, per product spec §2.5.
 * Goals -> zone -> correct answers -> total correct-answer time (lower wins) -> draw.
 */
export const decideMatch = (input: MatchResultInput): MatchResult => {
  const [a, b] = input.players;

  const compare = (x: typeof a, y: typeof b): number => {
    if (x.goals !== y.goals) return x.goals > y.goals ? 1 : -1;
    if (x.zone !== y.zone) return x.zone > y.zone ? 1 : -1;
    if (x.correct !== y.correct) return x.correct > y.correct ? 1 : -1;
    // Fewer milliseconds spent on correct answers wins. Guard: 0 correct -> nothing to compare.
    if (x.correctTimeMs !== y.correctTimeMs && x.correct > 0 && y.correct > 0) {
      return x.correctTimeMs < y.correctTimeMs ? 1 : -1;
    }
    return 0;
  };

  const delta = compare(a, b);
  const decidedBy: MatchResult["decidedBy"] =
    delta === 0
      ? "draw"
      : a.goals !== b.goals
        ? "goals"
        : a.zone !== b.zone
          ? "zone"
          : a.correct !== b.correct
            ? "correct"
            : "time";

  if (delta === 0) {
    return {
      matchId: input.matchId,
      ranking: [],
      outcomeByPlayer: { [a.playerId]: "draw", [b.playerId]: "draw" },
      decidedBy,
    };
  }

  const winner = delta > 0 ? a : b;
  const loser = delta > 0 ? b : a;
  return {
    matchId: input.matchId,
    ranking: [winner.playerId, loser.playerId],
    outcomeByPlayer: { [winner.playerId]: "win", [loser.playerId]: "loss" },
    decidedBy,
  };
};

/**
 * Elo with a K that decays as a player accumulates matches.
 * Ratings are cosmetic in MVP (no matchmaking gate beyond the window), but the
 * ladder has to feel earned, so K starts high and settles.
 */
export const eloDelta = (
  ratingA: number,
  ratingB: number,
  scoreA: number,
  matchesPlayedA: number,
): number => {
  const k = matchesPlayedA < 10 ? 40 : matchesPlayedA < 30 ? 28 : 20;
  const expected = 1 / (1 + 10 ** ((ratingB - ratingA) / 400));
  return Math.round(k * (scoreA - expected));
};

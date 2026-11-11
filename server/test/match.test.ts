/**
 * Full-match simulation against the REAL question bank.
 *
 * Two bots with different accuracy play a complete match — two halves, Shooting
 * Chances, half-time — and the test asserts the invariants that matter in production:
 * the match ends, the pitch stays legal, the wire never carries the answer key, and
 * the two players receive different locales of the same question.
 */

import { assert, summarize, test } from "./harness.ts";
import { MatchRoom } from "../src/match-room.ts";
import { renderQuestion } from "../src/render.ts";
import { drawPool, loadBank } from "../src/bank-loader.ts";
import type { Outbound, PlayerRef, QuestionView } from "../src/types.ts";

const bank = await loadBank();

const ALICE: PlayerRef = {
  playerId: "p_alice",
  displayName: "Alice",
  locale: "en",
  region: "EU",
  rating: 1_200,
};

const BOB: PlayerRef = {
  playerId: "p_bob",
  displayName: "بوب",
  locale: "ar",
  region: "MENA",
  rating: 1_180,
};

/** Deterministic PRNG so a failing simulation is reproducible from its seed. */
const lcg = (seed: number) => {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
};

interface SimOptions {
  aliceAccuracy: number;
  bobAccuracy: number;
  seed: number;
  stepMs?: number;
}

interface SimResult {
  room: MatchRoom;
  counts: Record<string, number>;
  ends: Outbound[];
  firstView: Record<string, QuestionView>;
  firstTokens: Record<string, string>;
  maxZoneSeen: number;
  minZoneSeen: number;
  leakedAnswerKey: boolean;
  roundQuestionIds: string[];
  steps: number;
}

const simulate = (options: SimOptions): SimResult => {
  const stepMs = options.stepMs ?? 100;
  const random = lcg(options.seed);

  const room = new MatchRoom({
    matchId: `m_sim_${options.seed}`,
    players: [ALICE, BOB],
    pool: drawPool(bank.questions, 18, options.seed),
    shotPool: bank.shotQuestions,
    catalog: bank.catalog,
  });

  const counts: Record<string, number> = {};
  const ends: Outbound[] = [];
  const firstView: Record<string, QuestionView> = {};
  const firstTokens: Record<string, string> = {};
  const tokens: Record<string, string> = {};
  let currentRound = 0;
  let shooterId: string | null = null;
  const answered = new Set<string>();
  let maxZoneSeen = 0;
  let minZoneSeen = 5;
  let leakedAnswerKey = false;
  const roundQuestionIds: string[] = [];

  const consume = (out: Outbound[]): void => {
    for (const env of out) {
      counts[env.type] = (counts[env.type] ?? 0) + 1;

      const json = JSON.stringify(env.payload);
      if (env.type === "round.question" || env.type === "shoot.question") {
        if (json.includes("answerOptionId") || json.includes("correctOptionId")) {
          leakedAnswerKey = true;
        }
      }

      if (env.type === "round.question" || env.type === "shoot.question") {
        const payload = env.payload as {
          token: string;
          view: QuestionView;
          roundNo?: number;
        };
        tokens[env.to as string] = payload.token;
        if (!firstView[env.to as string]) {
          firstView[env.to as string] = payload.view;
          firstTokens[env.to as string] = payload.token;
        }
        if (typeof payload.roundNo === "number") currentRound = payload.roundNo;
      }

      if (env.type === "shoot.question") {
        const payload = env.payload as { shooterId: string };
        shooterId = payload.shooterId;
      }

      if (env.type === "round.question" && env.to === ALICE.playerId) {
        roundQuestionIds.push((env.payload as { view: QuestionView }).view.questionId);
      }

      if (env.type === "match.end") ends.push(env);
    }
  };

  let now = 1_000_000;
  consume(room.start(now));

  let steps = 0;
  while (!room.isFinished && steps < 20_000) {
    steps += 1;
    now += stepMs;
    consume(room.advance(now));

    for (const zone of Object.values(room.result.zones)) {
      maxZoneSeen = Math.max(maxZoneSeen, zone);
      minZoneSeen = Math.min(minZoneSeen, zone);
    }

    const audit = room.audit;
    if (!audit) continue;

    if (room.phaseName === "question_open") {
      const key = `round:${currentRound}`;
      if (answered.has(key)) continue;
      answered.add(key);

      for (const player of [ALICE, BOB]) {
        const accuracy = player.playerId === ALICE.playerId ? options.aliceAccuracy : options.bobAccuracy;
        const token = tokens[player.playerId];
        if (!token) continue;
        const correct = random() < accuracy;
        const optionId = correct
          ? audit.answerOptionId
          : (bank.questions.find((q) => q.id === audit.questionId)?.options.find((o) => o.id !== audit.answerOptionId)?.id ?? "opt_none");
        consume(room.submitAnswer(player.playerId, { token, optionId }, now));
      }
    }

    if (room.phaseName === "shooting_chance" && shooterId) {
      const key = `shot:${currentRound}:${shooterId}`;
      if (answered.has(key)) continue;
      answered.add(key);
      const token = tokens[shooterId];
      if (!token) continue;
      const correct = random() < 0.6;
      const optionId = correct
        ? audit.answerOptionId
        : (bank.questions.find((q) => q.id === audit.questionId)?.options.find((o) => o.id !== audit.answerOptionId)?.id ?? "opt_none");
      consume(room.submitAnswer(shooterId, { token, optionId }, now));
    }
  }

  return {
    room,
    counts,
    ends,
    firstView,
    firstTokens,
    maxZoneSeen,
    minZoneSeen,
    leakedAnswerKey,
    roundQuestionIds,
    steps,
  };
};

const strongVsWeak = simulate({ aliceAccuracy: 0.92, bobAccuracy: 0.35, seed: 20_261_110 });

test("a full match reaches full time on its own", () => {
  assert.equal(strongVsWeak.room.isFinished, true, "match must terminate without external intervention");
  assert.equal(strongVsWeak.counts["match.end"], 2, "both players receive match.end");
  assert.ok(strongVsWeak.steps < 20_000, "no runaway loop");
});

test("the match actually plays two halves and at least one Shooting Chance", () => {
  // NOTE: counts are per-RECIPIENT. Every broadcast is emitted once per player, so a
  // single second-half kickoff is 2 envelopes, not 1.
  assert.equal(strongVsWeak.counts["match.second_half"], 2, "exactly one second-half kickoff, fanned out to 2 players");
  assert.ok((strongVsWeak.counts["match.half"] ?? 0) >= 2, "half-time interstitial fires");
  assert.ok((strongVsWeak.counts["shoot.question"] ?? 0) >= 2, "reaching zone 5 must trigger a shot");
  assert.ok((strongVsWeak.counts["round.question"] ?? 0) >= 16, "a match should ask a real number of questions");
});

test("no question is ever asked twice in the same match", () => {
  const ids = strongVsWeak.roundQuestionIds;
  assert.ok(ids.length >= 8, `expected a real match, got ${ids.length} questions`);
  const unique = new Set(ids);
  assert.equal(
    unique.size,
    ids.length,
    `a question repeated within one match: ${ids.filter((id, i) => ids.indexOf(id) !== i).join(", ")}`,
  );
});

test("the pitch never leaves 0..5", () => {
  assert.ok(strongVsWeak.minZoneSeen >= 0, `zone underflowed to ${strongVsWeak.minZoneSeen}`);
  assert.ok(strongVsWeak.maxZoneSeen <= 5, `zone overflowed to ${strongVsWeak.maxZoneSeen}`);
});

test("the answer key never appears in a question payload", () => {
  assert.equal(strongVsWeak.leakedAnswerKey, false, "a sniffing proxy must not be able to read the answer");
});

test("cross-language: same question, different rendering", () => {
  const en = strongVsWeak.firstView[ALICE.playerId];
  const ar = strongVsWeak.firstView[BOB.playerId];

  assert.equal(en?.locale, "en");
  assert.equal(en?.dir, "ltr");
  assert.equal(ar?.locale, "ar");
  assert.equal(ar?.dir, "rtl", "the server declares direction so the client cannot guess");
  assert.equal(en?.questionId, ar?.questionId, "both players face the SAME question");
  assert.notEqual(en?.prompt, ar?.prompt, "…rendered in their own language");
  assert.equal(en?.options.length, ar?.options.length);

  const enOrder = en?.options.map((o) => o.id).join(",");
  const arOrder = ar?.options.map((o) => o.id).join(",");
  assert.notEqual(enOrder, arOrder, "option order is shuffled per player, so no peeking by position");
  assert.deepEqual(
    en?.options.map((o) => o.id).sort(),
    ar?.options.map((o) => o.id).sort(),
    "shuffling must not add or drop options",
  );
});

test("question tokens are bound to the player", () => {
  assert.notEqual(
    strongVsWeak.firstTokens[ALICE.playerId],
    strongVsWeak.firstTokens[BOB.playerId],
    "a token minted for one player must not authorise the other",
  );
});

test("every career-path question renders its complete chronological club sequence", () => {
  const careerQuestions = bank.questions.filter((q) => q.format === "career_path");
  assert.ok(careerQuestions.length > 0, "the bank contains career-path questions");
  for (const question of careerQuestions) {
    const view = renderQuestion(question, "en", {
      catalog: bank.catalog,
      assetUrl: (assetId) => `https://assets.invalid/${assetId}.webp`,
      seed: `career-test:${question.id}`,
    });
    const clubs = view.formatData.clubs as Array<{ id: string; name: string }>;
    const ids = question.formatData?.clubIds as string[];
    assert.equal(clubs.length, ids.length, `${question.id} must render every club`);
    assert.ok(clubs.every((club) => club.name.length > 0 && club.name !== club.id),
      `${question.id} must show readable club names, not missing ids`);
  }
});

test("a stronger player beats a weaker one over a full match", () => {
  const goals = strongVsWeak.room.result.goals;
  assert.ok(
    goals[ALICE.playerId] > goals[BOB.playerId],
    `expected the 92% player to outscore the 35% player, got ${JSON.stringify(goals)}`,
  );
});

/* -------------------------------------------------------- connection handling */

const buildRoom = (seed: number): MatchRoom =>
  new MatchRoom({
    matchId: `m_conn_${seed}`,
    players: [ALICE, BOB],
    pool: drawPool(bank.questions, 18, seed),
    shotPool: bank.shotQuestions,
    catalog: bank.catalog,
  });

test("disconnect past the grace period forfeits the match", () => {
  const room = buildRoom(7);
  let now = 5_000_000;
  room.start(now);
  now += 500;
  room.advance(now);

  const notice = room.disconnect(ALICE.playerId, now);
  assert.equal(notice[0].type, "opponent.connection", "the opponent is told, not left guessing");

  now += 25_000 + 1;
  const out = room.advance(now);
  assert.equal(room.isFinished, true);
  const endForBob = out.find((e) => e.type === "match.end" && e.to === BOB.playerId);
  assert.ok(endForBob, "match ends");
  assert.equal((endForBob!.payload as { outcome: string }).outcome, "win");
  assert.equal((endForBob!.payload as { decidedBy: string }).decidedBy, "forfeit");
});

test("a player who lets the question timer expire receives a wrong verdict", () => {
  const room = buildRoom(71);
  let now = 5_500_000;
  room.start(now);
  now += 1_100;
  const questionFrames = room.advance(now);
  const question = questionFrames.find((e) => e.type === "round.question" && e.to === ALICE.playerId);
  assert.ok(question, "the question opens");
  const deadline = (question!.payload as { windowEndsAt: number }).windowEndsAt;
  const reveal = room.advance(deadline);
  const result = reveal.find((e) => e.type === "round.reveal" && e.to === ALICE.playerId);
  assert.ok(result, "the deadline produces a reveal");
  assert.equal((result!.payload as { outcome: string }).outcome, "wrong");
  assert.equal(room.players[ALICE.playerId].wrong, 1, "timeout is included in incorrect answers");
  assert.equal(room.players[ALICE.playerId].noAnswer, 1, "timeout is still tracked separately");
});

test("a reconnect inside the grace period resumes instead of forfeiting", () => {
  const room = buildRoom(8);
  let now = 6_000_000;
  room.start(now);
  now += 500;
  room.advance(now);

  room.disconnect(BOB.playerId, now);
  now += 5_000;
  const out = room.reconnect(BOB.playerId, now);

  assert.equal(room.isFinished, false, "5 s is not a forfeit");
  const sync = out.find((e) => e.type === "state.sync");
  assert.ok(sync, "the returning player is resynchronised");
  const payload = sync!.payload as { zones: Record<string, number>; serverNow: number; live: unknown };
  assert.ok(payload.zones, "snapshot carries pitch state");
  assert.equal(payload.serverNow, now, "snapshot carries authoritative time");
});

test("both players disconnecting voids the match rather than awarding a win", () => {
  const room = buildRoom(9);
  let now = 7_000_000;
  room.start(now);
  now += 500;
  room.advance(now);

  room.disconnect(ALICE.playerId, now);
  room.disconnect(BOB.playerId, now);

  now += 25_000 + 1;
  const out = room.advance(now);
  const ends = out.filter((e) => e.type === "match.end");
  assert.equal(ends.length, 2);
  for (const e of ends) {
    assert.equal((e.payload as { ratingDelta: number }).ratingDelta, 0, "a void match moves no rating");
  }
});

/* ------------------------------------------------------------- anti-cheat path */

test("an answer with a forged token is rejected and not recorded", () => {
  const room = buildRoom(11);
  let now = 8_000_000;
  room.start(now);
  now += 1_100; // past the intro, question is open
  const out = room.advance(now);

  const question = out.find((e) => e.type === "round.question" && e.to === ALICE.playerId);
  assert.ok(question, "question should be open");

  const forged = room.submitAnswer(
    ALICE.playerId,
    { token: "eyJmYWtlIjoxfQ.deadbeef", optionId: "opt_x" },
    now,
  );
  const error = forged.find((e) => e.type === "error");
  assert.ok(error, "forged token must be refused");
  assert.equal((error!.payload as { code: string }).code, "BAD_TOKEN");

  // The round is still open for a legitimate answer.
  const legit = room.submitAnswer(
    ALICE.playerId,
    { token: (question!.payload as { token: string }).token, optionId: "opt_arg" },
    now + 10,
  );
  assert.ok(legit.some((e) => e.type === "round.answer_ack"), "a valid token still works");
});

test("a duplicate answer is idempotent: first write wins", () => {
  const room = buildRoom(12);
  let now = 9_000_000;
  room.start(now);
  now += 1_100;
  const out = room.advance(now);
  const question = out.find((e) => e.type === "round.question" && e.to === ALICE.playerId);
  const token = (question!.payload as { token: string }).token;

  room.submitAnswer(ALICE.playerId, { token, optionId: "opt_a" }, now + 10);
  const retry = room.submitAnswer(ALICE.playerId, { token, optionId: "opt_b" }, now + 20);
  const ack = retry.find((e) => e.type === "round.answer_ack");
  assert.equal((ack!.payload as { duplicate: boolean }).duplicate, true);
});

summarize("match");

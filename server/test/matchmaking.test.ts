/**
 * Matchmaking invariants. The headline test is #1: two players who share nothing but
 * a love of football — different language, different region — are paired. If that ever
 * regresses, the product's premise is gone.
 */

import { assert, summarize, test } from "./harness.ts";
import { Matchmaker } from "../src/matchmaking.ts";
import type { PlayerRef, Region } from "../src/types.ts";

const player = (
  playerId: string,
  locale: "en" | "ar",
  region: Region,
  rating = 1_200,
): PlayerRef => ({ playerId, displayName: playerId, locale, region, rating });

test("an English speaker and an Arabic speaker are paired — locale is never a filter", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("en_player", "en", "EU"), 0, 40);
  mm.enqueue(player("ar_player", "ar", "EU"), 0, 45);

  const pairs = mm.tick(1_000);
  assert.equal(pairs.length, 1, "cross-language pairing must succeed immediately");
  assert.equal(pairs[0].players[0].player.locale !== pairs[0].players[1].player.locale, true);
  assert.equal(mm.size, 0, "both tickets consumed");
});

test("a language-segregating implementation would fail this: 2 EN + 1 AR still pairs someone across languages", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("en1", "en", "EU", 1_200), 0, 40);
  mm.enqueue(player("en2", "en", "EU", 1_200), 0, 40);
  mm.enqueue(player("ar1", "ar", "EU", 1_200), 0, 40);

  const pairs = mm.tick(1_000);
  assert.equal(pairs.length, 1, "only 2 of 3 pair in one pass");
  assert.equal(mm.size, 1, "the third player keeps waiting");
});

test("the rating window starts narrow and widens with waiting", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("a", "en", "EU", 1_000), 0, 40);
  mm.enqueue(player("b", "ar", "EU", 1_200), 0, 40);

  assert.equal(mm.tick(0).length, 0, "200 rating gap exceeds the initial ±150 window");
  assert.equal(mm.tick(2_000).length, 1, "after 2 s the window is ±225 and the pair is legal");
});

test("a huge rating gap still resolves eventually rather than starving the ticket", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("low", "en", "EU", 800), 0, 40);
  mm.enqueue(player("high", "ar", "EU", 1_200), 0, 40);

  assert.equal(mm.tick(0).length, 0);
  assert.equal(mm.tick(8_000).length, 1, "±150 + 4 steps = ±450 covers a 400 gap by 8 s");
});

test("cross-region pairing is withheld for 8 s, then allowed", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("eu", "en", "EU"), 0, 40);
  mm.enqueue(player("mena", "ar", "MENA"), 0, 90);

  assert.equal(mm.tick(5_000).length, 0, "region affinity is honoured first");
  const pairs = mm.tick(8_000);
  assert.equal(pairs.length, 1);
  assert.equal(pairs[0].crossRegion, true);
  assert.equal(pairs[0].reason, "cross-region-fallback");
});

test("the latency ceiling is absolute: an unplayable pair never matches", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("far1", "en", "APAC"), 0, 300);
  mm.enqueue(player("far2", "ar", "MENA"), 0, 260);

  assert.equal(mm.tick(60_000).length, 0, "260 ms RTT cannot be covered by a 120 ms jitter grace");
  assert.equal(mm.size, 2, "both remain queued for a viable partner");
});

test("the longest-waiting player is never jumped", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("first", "en", "EU"), 0, 40);
  mm.enqueue(player("second", "ar", "EU"), 1_000, 40);
  mm.enqueue(player("third", "en", "EU"), 1_500, 40);

  const pairs = mm.tick(2_000);
  const names = pairs[0].players.map((p) => p.player.playerId);
  assert.ok(names.includes("first"), `the oldest ticket must be served first, got ${names}`);
  assert.deepEqual(names.sort(), ["first", "second"]);
  assert.equal(mm.size, 1, "third keeps waiting");
});

test("enqueueing twice is idempotent — a double tap on PLAY must not duplicate the ticket", () => {
  const mm = new Matchmaker();
  const first = mm.enqueue(player("a", "en", "EU"), 0, 40);
  const second = mm.enqueue(player("a", "en", "EU"), 500, 40);
  assert.equal(first.ticket, second.ticket);
  assert.equal(mm.size, 1);
});

test("cancelling removes the ticket so the opponent is not paired into a ghost match", () => {
  const mm = new Matchmaker();
  mm.enqueue(player("a", "en", "EU"), 0, 40);
  mm.enqueue(player("b", "ar", "EU"), 0, 40);
  assert.equal(mm.cancel("b"), true);
  assert.equal(mm.tick(10_000).length, 0);
  assert.equal(mm.cancel("b"), false, "cancelling twice is a no-op, not an error");
});

test("pairings carry the quality telemetry needed to tune the queue", () => {
  const mm = new Matchmaker();
  // Same region on purpose: this test isolates telemetry, not the cross-region gate.
  mm.enqueue(player("a", "en", "EU", 1_100), 0, 40);
  mm.enqueue(player("b", "ar", "EU", 1_250), 3_000, 80);

  const pairs = mm.tick(9_000);
  assert.equal(pairs.length, 1);
  assert.equal(pairs[0].mmrGap, 150);
  assert.equal(pairs[0].rttMs, 80, "the worse of the two RTTs is what the match must survive");
  assert.ok(pairs[0].waitMs >= 9_000, "wait is measured from the older ticket");
  assert.ok(pairs[0].matchId.startsWith("m_"));
});

summarize("matchmaking");

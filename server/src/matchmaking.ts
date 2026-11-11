/**
 * matchmaking.ts — cross-language pairing.
 *
 * The one rule that defines the product: **locale is never a filter.** An English
 * player and an Arabic player are matched against each other and receive the same
 * question, rendered per locale. A queue that grouped by language would silently
 * destroy the game's entire premise and split the player base in two.
 *
 * What IS a filter: rating gap (widening with wait) and a latency ceiling.
 *
 * This class is the in-process model of the Redis-backed queue. The production
 * equivalent is one sorted set per (region, mmrBucket) plus a global fallback, and
 * this pairwise scan is replaced by a single Lua script — see the comment at the
 * bottom for the exact atomicity contract it must preserve.
 */

import { MATCHMAKING } from "./config.ts";
import type { PlayerRef } from "./types.ts";

export interface QueueEntry {
  ticket: string;
  player: PlayerRef;
  joinedAt: number;
  /** Measured round-trip to this region's node. Used as a hard ceiling. */
  rttMs: number;
}

export interface Pairing {
  matchId: string;
  players: [QueueEntry, QueueEntry];
  waitMs: number;
  mmrGap: number;
  rttMs: number;
  crossRegion: boolean;
  /** Why this pair was chosen — surfaced in match quality telemetry. */
  reason: "same-region" | "cross-region-fallback";
}

const pairCost = (a: QueueEntry, b: QueueEntry, now: number): number | null => {
  const waitA = now - a.joinedAt;
  const waitB = now - b.joinedAt;
  const shortestWait = Math.min(waitA, waitB);

  // Rating window widens for the player who has waited longer; the pair is legal
  // only if BOTH sides accept the gap, otherwise a patient player gets sandbagged.
  const windowA = MATCHMAKING.BASE_MMR_WINDOW + Math.floor(waitA / MATCHMAKING.SPREAD_INTERVAL_MS) * MATCHMAKING.MMR_WINDOW_STEP;
  const windowB = MATCHMAKING.BASE_MMR_WINDOW + Math.floor(waitB / MATCHMAKING.SPREAD_INTERVAL_MS) * MATCHMAKING.MMR_WINDOW_STEP;
  const allowed = Math.min(windowA, windowB);

  const gap = Math.abs(a.player.rating - b.player.rating);
  if (gap > allowed) return null;

  const rtt = Math.max(a.rttMs, b.rttMs);
  if (rtt > MATCHMAKING.MAX_RTT_MS) return null;

  const sameRegion = a.player.region === b.player.region;
  const crossAllowed =
    shortestWait >= MATCHMAKING.CROSS_REGION_AFTER_MS || sameRegion;
  if (!crossAllowed) return null;

  // Lower is better. Rating accuracy dominates, latency is second, waiting is a discount
  // so the oldest ticket is never starved by a fresh, perfectly-matched newcomer.
  return (
    gap * 1.0 +
    rtt * 0.35 +
    (sameRegion ? 0 : 180) -
    Math.min(shortestWait, 20_000) * 0.03
  );
};

export class Matchmaker {
  private readonly queue = new Map<string, QueueEntry>();
  private sequence = 0;

  enqueue(player: PlayerRef, now: number, rttMs: number): QueueEntry {
    const existing = this.queue.get(player.playerId);
    if (existing) return existing; // idempotent: double-tap on PLAY must not double-queue
    this.sequence += 1;
    const entry: QueueEntry = {
      ticket: `t_${now.toString(36)}_${this.sequence.toString(36)}`,
      player,
      joinedAt: now,
      rttMs,
    };
    this.queue.set(player.playerId, entry);
    return entry;
  }

  cancel(playerId: string): boolean {
    return this.queue.delete(playerId);
  }

  get size(): number {
    return this.queue.size;
  }

  tickets(): QueueEntry[] {
    return [...this.queue.values()];
  }

  /**
   * Run one pairing pass. O(n²) over the queue, which is intentional: at >2 000 waiting
   * players this is replaced by bucketed Redis lookups, and the quadratic behaviour is
   * a useful alarm that we have outgrown the simple model.
   */
  tick(now: number): Pairing[] {
    const pairings: Pairing[] = [];
    const claimed = new Set<string>();

    // Oldest first: nobody is served ahead of someone who has waited longer.
    const ordered = [...this.queue.values()].sort((a, b) => a.joinedAt - b.joinedAt);

    for (const a of ordered) {
      if (claimed.has(a.player.playerId)) continue;

      let best: QueueEntry | null = null;
      let bestCost = Number.POSITIVE_INFINITY;

      for (const b of ordered) {
        if (b.player.playerId === a.player.playerId || claimed.has(b.player.playerId)) continue;
        const cost = pairCost(a, b, now);
        if (cost !== null && cost < bestCost) {
          best = b;
          bestCost = cost;
        }
      }

      if (!best) continue;

      claimed.add(a.player.playerId);
      claimed.add(best.player.playerId);

      const sameRegion = a.player.region === best.player.region;
      pairings.push({
        matchId: `m_${now.toString(36)}_${a.ticket.slice(-4)}${best.ticket.slice(-4)}`,
        players: [a, best],
        waitMs: now - Math.min(a.joinedAt, best.joinedAt),
        mmrGap: Math.abs(a.player.rating - best.player.rating),
        rttMs: Math.max(a.rttMs, best.rttMs),
        crossRegion: !sameRegion,
        reason: sameRegion ? "same-region" : "cross-region-fallback",
      });
    }

    for (const p of pairings) {
      for (const entry of p.players) this.queue.delete(entry.player.playerId);
    }
    return pairings;
  }
}

/**
 * PRODUCTION CONTRACT (Redis).
 *
 * The in-process version is safe because a single node owns the loop. Across nodes the
 * claim must be atomic, or two nodes pair the same player into two matches and one of
 * them is a phantom game against a player who is already elsewhere. The Lua script:
 *
 *   -- KEYS[1] = queue:{region}:{bucket}   KEYS[2] = queue:global
 *   -- ARGV[1] = playerId  ARGV[2] = now  ARGV[3] = ttl
 *   local a = redis.call('ZPOPMIN', KEYS[1])
 *   if not a[1] then a = redis.call('ZPOPMIN', KEYS[2]) end
 *   if not a[1] then return nil end
 *   redis.call('SET', 'match-claim:' .. ARGV[1], a[1], 'NX', 'EX', 10)
 *   return a[1]
 *
 * The `SET ... NX` is the real lock: ZPOPMIN is atomic but does not prevent the *same
 * player* being popped twice if their ticket exists in two queues (region + global).
 * If the claim fails, the popped entry is pushed back and the loop retries.
 *
 * Invariants the transport must preserve, regardless of implementation:
 *   1. a ticket is consumed at most once (claim is atomic and expiring)
 *   2. a pairing is only announced after BOTH tickets are claimed
 *   3. if match creation fails, both tickets return to the queue with their original
 *      joinedAt — otherwise a failed match resets the player's wait and starves them
 */

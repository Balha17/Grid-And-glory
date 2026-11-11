/**
 * Single source of truth for every tunable in the match. If a number appears in
 * docs/00-product-spec.md and in code, it lives HERE and the doc quotes it.
 *
 * All durations are milliseconds.
 */

export const MATCH = {
  /** Regulation time: 2 halves x 45 s. */
  HALF_MS: 45_000,
  HALVES: 2,

  /** A normal round = intro + question window + reveal (clock runs through all three). */
  ROUND_INTRO_MS: 1_000,
  ANSWER_WINDOW_MS: 9_000,
  REVEAL_MS: 850,

  /** A Shooting Chance runs on stoppage time: the clock is frozen while it plays. */
  SHOOT_WINDOW_MS: 5_000,
  SHOOT_REVEAL_MS: 2_200,
  SHOT_COOLDOWN_MS: 8_000,

  /** Half-time interstitial. Clock frozen. */
  HALF_TIME_MS: 6_000,

  /** The final round of a half is never shorter than this, even in a blowout. */
  LAST_ROUND_FLOOR_MS: 2_500,

  /**
   * Minimum match-clock charged per round, on top of the fixed intro and reveal.
   *
   * Without this, answering instantly makes a round cost only intro+reveal (2.4 s), and a
   * script could farm ~19 questions per half instead of ~6 — more questions meaning more
   * chances to score. This bounds a half to roughly 6–8 rounds regardless of input speed,
   * while still rewarding a fast human with a marginally longer half.
   */
  MIN_ROUND_CLOCK_MS: 3_500,
} as const;

export const PITCH = {
  ZONE_MIN: 0,
  ZONE_MAX: 5,
  /** Zone the scorer restarts from — a goal should not be immediately repeatable. */
  ZONE_AFTER_GOAL: 2,
  /** Zone after a saved/ missed shot. */
  ZONE_AFTER_MISS: 3,
} as const;

export const SCORE = {
  /** Both correct: the earlier answer. */
  FAST: 2,
  /** Both correct: the later answer. */
  SLOW: 1,
  /** Wrong answer or no answer: turnover. */
  TURNOVER: -1,
  /**
   * If two correct answers land within this window we cannot separate skill from
   * network asymmetry, so BOTH are treated as fastest. See product spec §2.3.
   */
  JITTER_GRACE_MS: 120,
  /**
   * An answer arriving after the window but inside this grace still counts for
   * correctness, but can never earn the +2.
   */
  LATE_GRACE_MS: 150,
} as const;

export const MATCHMAKING = {
  /** Starting rating window. */
  BASE_MMR_WINDOW: 150,
  /** Window grows by this every SPREAD_INTERVAL_MS waited. */
  MMR_WINDOW_STEP: 75,
  SPREAD_INTERVAL_MS: 2_000,
  /** After this long, region preference is dropped and cross-region pairing is allowed. */
  CROSS_REGION_AFTER_MS: 8_000,
  /** Refuse a pairing above this round-trip — the jitter grace cannot cover it. */
  MAX_RTT_MS: 190,
  /** Locale is NEVER a filter: cross-language play is the product. */
  TICK_MS: 250,
} as const;

export const MATCH_LIMITS = {
  /**
   * Drawn once per match. Must exceed the ~16 rounds a fast match can produce, because a
   * question may never be asked twice in the same match (product spec §3.2).
   */
  POOL_SIZE: 24,
  /** Hard stop for a runaway loop in advance(); also a defensive bound in prod. */
  MAX_TRANSITIONS_PER_TICK: 64,
  RECONNECT_GRACE_MS: 25_000,
} as const;

/** Difficulty curve. Index = round number (1-based); last value caps all later rounds. */
export const DIFFICULTY_CURVE = [0, 2, 2, 3, 3, 4, 5, 5, 5, 5] as const;
export const DIFFICULTY_FOR_SHOT = [4, 5] as const;

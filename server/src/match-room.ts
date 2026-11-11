/**
 * match-room.ts — the authoritative match actor.
 *
 * Design rule: the room has NO timers of its own. It is a pure state machine that the
 * host loop advances with an explicit `now` (server epoch ms). That one decision is why
 * an entire 90-second match — including a Shooting Chance and a half-time — can be
 * simulated in microseconds by a unit test, and why a crash can be recovered by
 * replaying the same sequence with the same `now` values.
 *
 * One room per match. Single writer. No awaits, no I/O in the hot path.
 */

import {
  DIFFICULTY_CURVE,
  MATCH,
  MATCH_LIMITS,
  PITCH,
} from "./config.ts";
import {
  clampZone,
  decideMatch,
  eloDelta,
  resolveRound as scoreRound,
  zoneAfterShot,
} from "./scoring.ts";
import { directionOf, renderQuestion, renderReveal } from "./render.ts";
import { signQuestionToken, verifyQuestionToken } from "./token.ts";
import type {
  EntityCatalog,
  Locale,
  Outbound,
  Phase,
  PlayerId,
  PlayerRef,
  PlayerState,
  QuestionDoc,
  QuestionView,
  SubmittedAnswer,
} from "./types.ts";

/** What the client sends with an answer. */
export interface AnswerInput {
  token: string;
  optionId: string;
  /** Client clock at tap. Telemetry / anti-cheat only — never used to score. */
  clientMs?: number;
}

export interface MatchRoomOptions {
  matchId: string;
  players: [PlayerRef, PlayerRef];
  /** Normal-play questions, pre-drawn for this match. */
  pool: QuestionDoc[];
  /** Difficulty 4–5 questions reserved for Shooting Chances. */
  shotPool: QuestionDoc[];
  catalog: EntityCatalog;
  assetUrl?: (assetId: string) => string;
}

export interface MatchEvent {
  at: number;
  type: string;
  detail: Record<string, unknown>;
}

interface LiveQuestion {
  doc: QuestionDoc;
  views: Record<PlayerId, QuestionView>;
  tokens: Record<PlayerId, string>;
  answers: Map<PlayerId, SubmittedAnswer>;
  windowOpensAt: number;
  windowEndsAt: number;
  /** Only set for a Shooting Chance. */
  shooterId?: PlayerId;
}

const DEFAULT_ASSET_URL = (assetId: string): string =>
  `https://cdn.gridandglory.gg/v1/${assetId}.webp`;

export class MatchRoom {
  readonly matchId: string;
  readonly players: Record<PlayerId, PlayerState>;

  private readonly refs: Record<PlayerId, PlayerRef>;
  private readonly order: [PlayerId, PlayerId];
  private readonly pool: QuestionDoc[];
  private readonly shotPool: QuestionDoc[];
  private readonly catalog: EntityCatalog;
  private readonly assetUrl: (assetId: string) => string;

  private phase: Phase = "kickoff";
  private phaseEndsAt = 0;
  private half: 1 | 2 = 1;
  private halfRemainingMs: number = MATCH.HALF_MS;
  private roundNo = 0;
  private currentWindowMs: number = MATCH.ANSWER_WINDOW_MS;
  private pendingDoc: QuestionDoc | null = null;
  private pendingViews: Record<PlayerId, QuestionView> = {} as Record<PlayerId, QuestionView>;
  private live: LiveQuestion | null = null;
  private cooldownUntil = 0;
  private readonly usedQuestionIds = new Set<string>();
  private readonly usedShotIds = new Set<string>();
  private finished = false;
  private forfeitedBy: PlayerId | null = null;
  private voided = false;
  private readonly events: MatchEvent[] = [];

  constructor(options: MatchRoomOptions) {
    this.matchId = options.matchId;
    this.pool = options.pool;
    this.shotPool = options.shotPool;
    this.catalog = options.catalog;
    this.assetUrl = options.assetUrl ?? DEFAULT_ASSET_URL;

    const [a, b] = options.players;
    this.order = [a.playerId, b.playerId];
    this.refs = { [a.playerId]: a, [b.playerId]: b };

    const base = (p: PlayerRef, possession: boolean): PlayerState => ({
      playerId: p.playerId,
      locale: p.locale,
      zone: PITCH.ZONE_MIN,
      goals: 0,
      correct: 0,
      wrong: 0,
      noAnswer: 0,
      correctTimeMs: 0,
      possession,
      lastAnswerAt: null,
      connected: true,
      disconnectedAt: null,
    });

    this.players = {
      [a.playerId]: base(a, true),
      [b.playerId]: base(b, false),
    };
  }

  /* -------------------------------------------------------------- lifecycle */

  start(now: number): Outbound[] {
    const out: Outbound[] = [];
    this.emitBoth(out, "match.start", (id) => ({
      matchId: this.matchId,
      half: 1,
      halfMs: MATCH.HALF_MS,
      you: id,
      opponent: this.publicPlayer(this.other(id)),
      serverNow: now,
      zones: this.zones(),
      goals: this.goals(),
    }));
    this.startRound(now, out);
    return out;
  }

  /**
   * Advance the machine to `now`. Safe to call at any cadence; call every 50 ms in
   * production. Returns everything that must be sent as a result.
   */
  advance(now: number): Outbound[] {
    const out: Outbound[] = [];
    if (this.finished) return out;

    this.enforceReconnectGrace(now, out);
    if (this.finished) return out;

    let guard = 0;
    while (guard < MATCH_LIMITS.MAX_TRANSITIONS_PER_TICK) {
      guard += 1;
      if (this.phaseEndsAt === 0 || now < this.phaseEndsAt) break;
      const at = this.phaseEndsAt;

      switch (this.phase) {
        case "round_intro":
          this.openQuestion(at, out);
          break;
        case "question_open":
          // Nobody finished early: the window itself expires.
          this.chargeRoundClock(at);
          this.resolveCurrentRound(at, out);
          break;
        case "round_reveal":
          this.halfRemainingMs = Math.max(0, this.halfRemainingMs - MATCH.REVEAL_MS);
          this.afterRound(at, out);
          break;
        case "shooting_chance":
          this.resolveShot(at, out);
          break;
        case "shot_reveal":
          this.afterRound(at, out);
          break;
        case "half_time":
          this.beginSecondHalf(at, out);
          break;
        default:
          this.phaseEndsAt = 0;
      }
    }
    return out;
  }

  /* ---------------------------------------------------------------- answers */

  submitAnswer(playerId: PlayerId, input: AnswerInput, now: number): Outbound[] {
    const out: Outbound[] = [];
    if (this.finished || !this.live) return out;

    const live = this.live;

    // A Shooting Chance is a solo moment: the defender cannot answer.
    if (this.phase === "shooting_chance" && live.shooterId && live.shooterId !== playerId) {
      return out;
    }
    if (this.phase !== "question_open" && this.phase !== "shooting_chance") return out;

    // Idempotency: first write wins. A retried packet must not double-count.
    if (live.answers.has(playerId)) {
      out.push({ to: playerId, type: "round.answer_ack", payload: { duplicate: true } });
      return out;
    }

    const verdict = verifyQuestionToken(input.token, now);
    if (!verdict.ok) {
      this.events.push({ at: now, type: "token.reject", detail: { playerId, reason: verdict.reason } });
      out.push({ to: playerId, type: "error", payload: { code: "BAD_TOKEN", reason: verdict.reason } });
      return out;
    }
    const claims = verdict.claims;
    if (
      claims.matchId !== this.matchId ||
      claims.playerId !== playerId ||
      claims.questionId !== live.doc.id
    ) {
      out.push({ to: playerId, type: "error", payload: { code: "TOKEN_MISMATCH" } });
      return out;
    }

    live.answers.set(playerId, {
      playerId,
      optionId: input.optionId,
      receivedAt: now,
      clientMs: input.clientMs,
    });
    this.players[playerId].lastAnswerAt = now;

    out.push({
      to: playerId,
      type: "round.answer_ack",
      payload: { questionId: live.doc.id, receivedAt: now, windowEndsAt: live.windowEndsAt },
    });
    // Tell the opponent *that* an answer landed — never what it was.
    out.push({ to: this.other(playerId), type: "round.opponent_answered", payload: {} });

    if (this.phase === "shooting_chance") {
      this.resolveShot(now, out);
    } else if (live.answers.size === 2) {
      this.chargeRoundClock(now);
      this.resolveCurrentRound(now, out);
    }

    return out;
  }

  /* ------------------------------------------------------------- round flow */

  /**
   * Deduct the match clock for a round that just resolved.
   * Charges `max(actual, MIN_ROUND_CLOCK_MS)` — see the constant for why the floor exists.
   */
  private chargeRoundClock(resolvedAt: number): void {
    const live = this.live;
    if (!live) return;
    const actual = Math.max(0, resolvedAt - live.windowOpensAt);
    const charge = Math.max(actual, MATCH.MIN_ROUND_CLOCK_MS);
    this.halfRemainingMs = Math.max(0, this.halfRemainingMs - charge);
  }

  private startRound(now: number, out: Outbound[]): void {
    this.roundNo += 1;
    this.live = null;
    this.phase = "round_intro";
    this.phaseEndsAt = now + MATCH.ROUND_INTRO_MS;

    // The final round of a half is shortened, never skipped below the floor.
    const budget = this.halfRemainingMs - MATCH.ROUND_INTRO_MS - MATCH.REVEAL_MS;
    this.currentWindowMs = Math.min(
      MATCH.ANSWER_WINDOW_MS,
      Math.max(MATCH.LAST_ROUND_FLOOR_MS, budget),
    );

    // Draw now (not at open) so the intro can preload a blur asset, and so the
    // question shown at open is exactly the one the intro advertised.
    this.pendingDoc = this.drawQuestion(
      DIFFICULTY_CURVE[Math.min(this.roundNo, DIFFICULTY_CURVE.length - 1)],
    );
    this.pendingViews = {} as Record<PlayerId, QuestionView>;
    for (const id of this.order) {
      this.pendingViews[id] = renderQuestion(this.pendingDoc, this.players[id].locale, {
        catalog: this.catalog,
        assetUrl: this.assetUrl,
        seed: `${this.matchId}:${this.roundNo}:${id}`,
      });
    }

    this.emitBoth(out, "round.intro", (id) => ({
      roundNo: this.roundNo,
      half: this.half,
      halfRemainingMs: this.halfRemainingMs,
      windowMs: this.currentWindowMs,
      serverNow: now,
      view: this.pendingViews[id],
    }));

    const assetId = this.pendingDoc.media?.[0]?.assetId;
    if (assetId) {
      const url = this.assetUrl(assetId);
      this.emitBoth(out, "round.preload", () => ({ assetUrl: url }));
    }
  }

  private openQuestion(now: number, out: Outbound[]): void {
    this.halfRemainingMs = Math.max(0, this.halfRemainingMs - MATCH.ROUND_INTRO_MS);

    const doc = this.pendingDoc ?? this.drawQuestion(2);
    this.pendingDoc = null;
    const windowEndsAt = now + this.currentWindowMs;

    const live: LiveQuestion = {
      doc,
      views: {} as Record<PlayerId, QuestionView>,
      tokens: {} as Record<PlayerId, string>,
      answers: new Map(),
      windowOpensAt: now,
      windowEndsAt,
    };

    for (const id of this.order) {
      live.views[id] = this.pendingViews[id] ?? renderQuestion(doc, this.players[id].locale, {
        catalog: this.catalog,
        assetUrl: this.assetUrl,
        seed: `${this.matchId}:${this.roundNo}:${id}`,
      });
      live.tokens[id] = signQuestionToken({
        matchId: this.matchId,
        roundNo: this.roundNo,
        playerId: id,
        questionId: doc.id,
        exp: windowEndsAt + 2_000,
      });
    }

    this.pendingViews = {} as Record<PlayerId, QuestionView>;
    this.live = live;
    this.phase = "question_open";
    this.phaseEndsAt = windowEndsAt;

    for (const id of this.order) {
      out.push({
        to: id,
        type: "round.question",
        payload: {
          roundNo: this.roundNo,
          token: live.tokens[id],
          // Absolute deadline, never a duration: a client that joins late is still correct.
          windowEndsAt,
          serverNow: now,
          view: live.views[id],
          zones: this.zones(),
          possession: this.possessionId(),
        },
      });
    }
  }

  private resolveCurrentRound(at: number, out: Outbound[]): void {
    const live = this.live;
    if (!live) return;

    const resolution = scoreRound({
      answerOptionId: live.doc.answerOptionId,
      timing: { windowOpensAt: live.windowOpensAt, windowEndsAt: live.windowEndsAt },
      answers: live.answers,
      playerIds: this.order,
    });

    const zoneBefore = this.zones();

    for (const id of this.order) {
      const result = resolution.results[id];
      const state = this.players[id];
      state.zone = clampZone(state.zone + result.delta);
      if (result.outcome === "correct") {
        state.correct += 1;
        state.correctTimeMs += result.elapsedMs ?? 0;
      } else if (result.outcome === "wrong") {
        state.wrong += 1;
      } else {
        state.noAnswer += 1;
      }
    }

    const outcomes = Object.fromEntries(this.order.map((id) => [id, resolution.results[id]]));
    this.applyPossession(outcomes, resolution.fastestIds);

    this.events.push({
      at,
      type: "round.resolve",
      detail: {
        roundNo: this.roundNo,
        half: this.half,
        questionId: live.doc.id,
        outcomes: Object.fromEntries(this.order.map((id) => [id, resolution.results[id].outcome])),
        deltas: Object.fromEntries(this.order.map((id) => [id, resolution.results[id].delta])),
        zones: this.zones(),
        jitterTie: resolution.jitterTie,
        lag: Object.fromEntries(
          this.order.map((id) => [id, live.answers.get(id)?.clientMs ?? null]),
        ),
      },
    });

    for (const id of this.order) {
      const result = resolution.results[id];
      const correctText =
        live.views[id].options.find((o) => o.id === live.doc.answerOptionId)?.text ?? "";

      out.push({
        to: id,
        type: "round.reveal",
        payload: {
          ...renderReveal(
            live.doc,
            this.players[id].locale,
            { catalog: this.catalog, assetUrl: this.assetUrl, seed: `${this.matchId}:${this.roundNo}:${id}` },
            { delta: result.delta, zone: this.players[id].zone, correctOptionText: correctText },
          ),
          roundNo: this.roundNo,
          outcome: result.outcome,
          fastest: result.fastest,
          late: result.late,
          elapsedMs: result.elapsedMs,
          opponentOutcome: resolution.results[this.other(id)].outcome,
          zones: this.zones(),
          goals: this.goals(),
          possession: this.possessionId(),
          zoneBefore: zoneBefore[id],
        },
      });
    }

    this.phase = "round_reveal";
    this.phaseEndsAt = at + MATCH.REVEAL_MS;
  }

  /** After a reveal: a queued shot, then the half boundary, then the next round. */
  private afterRound(at: number, out: Outbound[]): void {
    const shooter = this.pickShooter(at);
    if (shooter) {
      this.startShot(shooter, at, out);
      return;
    }

    if (this.halfRemainingMs <= 0) {
      if (this.half === 1) this.startHalfTime(at, out);
      else this.finish(at, out);
      return;
    }
    this.startRound(at, out);
  }

  /* -------------------------------------------------------- shooting chance */

  private pickShooter(at: number): PlayerId | null {
    if (at < this.cooldownUntil) return null;
    const eligible = this.order.filter((id) => this.players[id].zone >= PITCH.ZONE_MAX);
    if (!eligible.length) return null;
    // Whoever got there first shoots first; the other's chance survives to the next boundary.
    eligible.sort((x, y) => (this.players[x].lastAnswerAt ?? 0) - (this.players[y].lastAnswerAt ?? 0));
    return eligible[0];
  }

  private startShot(shooterId: PlayerId, now: number, out: Outbound[]): void {
    const doc = this.drawShotQuestion();
    const windowEndsAt = now + MATCH.SHOOT_WINDOW_MS;
    const shotNo = this.roundNo + 1;

    const live: LiveQuestion = {
      doc,
      views: {} as Record<PlayerId, QuestionView>,
      tokens: {} as Record<PlayerId, string>,
      answers: new Map(),
      windowOpensAt: now,
      windowEndsAt,
      shooterId,
    };

    for (const id of this.order) {
      live.views[id] = renderQuestion(doc, this.players[id].locale, {
        catalog: this.catalog,
        assetUrl: this.assetUrl,
        seed: `${this.matchId}:shot:${shotNo}:${id}`,
      });
      live.tokens[id] = signQuestionToken({
        matchId: this.matchId,
        roundNo: shotNo,
        playerId: id,
        questionId: doc.id,
        exp: windowEndsAt + 2_000,
      });
    }

    this.live = live;
    this.phase = "shooting_chance";
    this.phaseEndsAt = windowEndsAt; // clock frozen: nothing is deducted here

    for (const id of this.order) {
      out.push({
        to: id,
        type: "shoot.question",
        payload: {
          shooterId,
          youAreShooting: id === shooterId,
          token: live.tokens[id],
          windowEndsAt,
          serverNow: now,
          view: live.views[id],
          zones: this.zones(),
          goals: this.goals(),
          difficulty: doc.difficulty,
        },
      });
    }
  }

  private resolveShot(at: number, out: Outbound[]): void {
    const live = this.live;
    if (!live?.shooterId) return;
    const shooterId = live.shooterId;
    const answer = live.answers.get(shooterId);
    const inTime = !!answer && answer.receivedAt <= live.windowEndsAt;
    const scored = inTime && answer.optionId === live.doc.answerOptionId;

    const shooter = this.players[shooterId];
    if (scored) {
      shooter.goals += 1;
      shooter.correct += 1;
      shooter.correctTimeMs += answer!.receivedAt - live.windowOpensAt;
    } else if (answer && inTime) {
      shooter.wrong += 1;
    } else {
      shooter.noAnswer += 1;
    }

    shooter.zone = clampZone(zoneAfterShot(scored));
    shooter.lastAnswerAt = at;

    // The ball always goes back to the opponent after a shot: goal or save.
    this.setPossession(this.other(shooterId));
    this.cooldownUntil = at + MATCH.SHOT_COOLDOWN_MS;

    this.events.push({
      at,
      type: "shot.resolve",
      detail: { shooterId, scored, questionId: live.doc.id, zones: this.zones(), goals: this.goals() },
    });

    for (const id of this.order) {
      const view = live.views[id];
      const correctText = view.options.find((o) => o.id === live.doc.answerOptionId)?.text ?? "";
      const locale: Locale = this.players[id].locale;

      out.push({
        to: id,
        type: "shoot.reveal",
        payload: {
          shooterId,
          scored,
          correctOptionId: live.doc.answerOptionId,
          correctOptionText: correctText,
          explainer: live.doc.explainer[locale],
          zones: this.zones(),
          goals: this.goals(),
          dir: directionOf(locale),
          possession: this.possessionId(),
        },
      });
    }

    this.phase = "shot_reveal";
    this.phaseEndsAt = at + MATCH.SHOOT_REVEAL_MS;
  }

  /* -------------------------------------------------------------- half / end */

  private startHalfTime(at: number, out: Outbound[]): void {
    this.phase = "half_time";
    this.phaseEndsAt = at + MATCH.HALF_TIME_MS;
    this.emitBoth(out, "match.half", (id) => ({
      half: 1,
      goals: this.goals(),
      zones: this.zones(),
      stats: this.statsFor(id),
      opponentStats: this.statsFor(this.other(id)),
    }));
  }

  private beginSecondHalf(at: number, out: Outbound[]): void {
    this.half = 2;
    this.halfRemainingMs = MATCH.HALF_MS;
    this.roundNo = 0;
    // NOTE: usedQuestionIds is deliberately NOT cleared here. A question may never be
    // asked twice in one match, and half two used to re-draw half one's questions.
    this.setPossession(this.other(this.possessionId()));
    this.emitBoth(out, "match.second_half", () => ({
      half: 2,
      halfMs: MATCH.HALF_MS,
      serverNow: at,
      zones: this.zones(),
      goals: this.goals(),
      possession: this.possessionId(),
    }));
    this.startRound(at, out);
  }

  private finish(at: number, out: Outbound[]): void {
    this.finished = true;
    this.phase = "ended";
    this.phaseEndsAt = 0;

    const legs = this.order.map((id) => {
      const s = this.players[id];
      return {
        playerId: id,
        goals: s.goals,
        zone: s.zone,
        correct: s.correct,
        correctTimeMs: s.correctTimeMs,
        rating: this.refs[id].rating,
      };
    });

    const decided = decideMatch({
      matchId: this.matchId,
      players: legs as Parameters<typeof decideMatch>[0]["players"],
    });

    // A forfeit or a void overrides the pitch result — it is not a draw.
    const outcomes: Record<PlayerId, "win" | "loss" | "draw"> = this.voided
      ? { [this.order[0]]: "draw", [this.order[1]]: "draw" }
      : this.forfeitedBy
        ? {
            [this.forfeitedBy]: "loss",
            [this.other(this.forfeitedBy)]: "win",
          }
        : decided.outcomeByPlayer;

    const ratingDeltas: Record<PlayerId, number> = {};
    for (const id of this.order) {
      if (this.voided) {
        ratingDeltas[id] = 0;
        continue;
      }
      const own = outcomes[id];
      const score = own === "win" ? 1 : own === "draw" ? 0.5 : 0;
      // 12 = provisional placed-player count; production reads player_stats.
      ratingDeltas[id] = eloDelta(this.refs[id].rating, this.refs[this.other(id)].rating, score, 12);
    }

    for (const id of this.order) {
      out.push({
        to: id,
        type: "match.end",
        payload: {
          matchId: this.matchId,
          outcome: outcomes[id],
          decidedBy: this.forfeitedBy ? "forfeit" : this.voided ? "void" : decided.decidedBy,
          goals: this.goals(),
          zones: this.zones(),
          stats: this.statsFor(id),
          opponentStats: this.statsFor(this.other(id)),
          ratingDelta: ratingDeltas[id],
          serverNow: at,
        },
      });
    }

    this.events.push({
      at,
      type: "match.end",
      detail: {
        decidedBy: this.forfeitedBy ? "forfeit" : decided.decidedBy,
        goals: this.goals(),
        zones: this.zones(),
      },
    });
  }

  /* ------------------------------------------------------------- connection */

  disconnect(playerId: PlayerId, now: number): Outbound[] {
    const out: Outbound[] = [];
    const state = this.players[playerId];
    if (!state || !state.connected) return out;
    state.connected = false;
    state.disconnectedAt = now;
    out.push({
      to: this.other(playerId),
      type: "opponent.connection",
      payload: { connected: false, graceMs: MATCH_LIMITS.RECONNECT_GRACE_MS },
    });
    if (this.order.every((id) => !this.players[id].connected)) this.voided = true;
    return out;
  }

  reconnect(playerId: PlayerId, now: number): Outbound[] {
    const out: Outbound[] = [];
    const state = this.players[playerId];
    if (!state || state.connected) return out;
    state.connected = true;
    state.disconnectedAt = null;
    out.push({ to: playerId, type: "state.sync", payload: this.snapshot(now, playerId) });
    out.push({ to: this.other(playerId), type: "opponent.connection", payload: { connected: true } });
    return out;
  }

  private enforceReconnectGrace(now: number, out: Outbound[]): void {
    for (const id of this.order) {
      const state = this.players[id];
      if (state.connected || state.disconnectedAt === null) continue;
      if (now - state.disconnectedAt < MATCH_LIMITS.RECONNECT_GRACE_MS) continue;
      this.forfeitedBy = id;
      this.finish(now, out);
      return;
    }
  }

  /** Full snapshot for `state.sync` after a reconnect. */
  snapshot(now: number, viewer?: PlayerId): Record<string, unknown> {
    const liveOpen = this.phase === "question_open" || this.phase === "shooting_chance";
    return {
      matchId: this.matchId,
      phase: this.phase,
      half: this.half,
      halfRemainingMs: this.halfRemainingMs,
      roundNo: this.roundNo,
      zones: this.zones(),
      goals: this.goals(),
      possession: this.possessionId(),
      cooldownUntil: this.cooldownUntil,
      serverNow: now,
      // A reconnecting player mid-question can re-enter, but the deadline is unchanged:
      // reconnecting must never buy time.
      live: liveOpen && this.live
        ? {
            windowEndsAt: this.live.windowEndsAt,
            waitingOnOpponent: viewer ? !this.live.answers.has(viewer) : true,
          }
        : null,
    };
  }

  /* ---------------------------------------------------------------- helpers */

  private other(id: PlayerId): PlayerId {
    return this.order[0] === id ? this.order[1] : this.order[0];
  }

  private zones(): Record<PlayerId, number> {
    return Object.fromEntries(this.order.map((id) => [id, this.players[id].zone]));
  }

  private goals(): Record<PlayerId, number> {
    return Object.fromEntries(this.order.map((id) => [id, this.players[id].goals]));
  }

  private possessionId(): PlayerId {
    return this.order.find((id) => this.players[id].possession) ?? this.order[0];
  }

  private setPossession(id: PlayerId): void {
    for (const p of this.order) this.players[p].possession = p === id;
  }

  private applyPossession(
    results: Record<PlayerId, { outcome: string }>,
    fastestIds: PlayerId[],
  ): void {
    const correctIds = this.order.filter((id) => results[id].outcome === "correct");
    if (correctIds.length === 1) {
      this.setPossession(correctIds[0]);
      return;
    }
    if (correctIds.length === 2 && fastestIds.length === 1) {
      // Both scored, but the quicker one came away with the ball.
      this.setPossession(fastestIds[0]);
    }
    // Both wrong: nobody won the ball. Jitter tie: a coin flip must not decide possession.
  }

  private publicPlayer(id: PlayerId): Record<string, unknown> {
    const ref = this.refs[id];
    return {
      playerId: id,
      displayName: ref.displayName,
      locale: ref.locale,
      dir: directionOf(ref.locale),
      region: ref.region,
      rating: ref.rating,
    };
  }

  private statsFor(id: PlayerId): Record<string, unknown> {
    const s = this.players[id];
    const answered = s.correct + s.wrong;
    return {
      goals: s.goals,
      zone: s.zone,
      correct: s.correct,
      wrong: s.wrong,
      noAnswer: s.noAnswer,
      accuracy: answered === 0 ? null : Number((s.correct / answered).toFixed(3)),
      avgCorrectMs: s.correct === 0 ? null : Math.round(s.correctTimeMs / s.correct),
    };
  }

  private drawQuestion(targetDifficulty: number): QuestionDoc {
    if (!this.pool.length) throw new Error(`match ${this.matchId}: question pool is empty`);
    const unused = this.pool.filter((q) => !this.usedQuestionIds.has(q.id));
    const source = unused.length ? unused : this.pool;

    // Closest difficulty; ties keep the earlier draw (stable, therefore replayable).
    let best = source[0];
    let bestGap = Math.abs(best.difficulty - targetDifficulty);
    for (const q of source) {
      const gap = Math.abs(q.difficulty - targetDifficulty);
      if (gap < bestGap) {
        best = q;
        bestGap = gap;
      }
    }
    this.usedQuestionIds.add(best.id);
    return best;
  }

  private drawShotQuestion(): QuestionDoc {
    // Exclude anything already asked in normal play: a question may appear once per match.
    const unused = this.shotPool.filter(
      (q) => !this.usedShotIds.has(q.id) && !this.usedQuestionIds.has(q.id),
    );
    const source = unused.length ? unused : this.shotPool;
    if (!source.length) {
      // Degrade rather than crash a live match: reuse the hardest normal question.
      const fallback = this.pool.slice().sort((a, b) => b.difficulty - a.difficulty)[0];
      if (!fallback) throw new Error(`match ${this.matchId}: shot pool is empty`);
      return fallback;
    }
    const q = source[0];
    this.usedShotIds.add(q.id);
    return q;
  }

  private emitBoth(
    out: Outbound[],
    type: string,
    payloadFor: (id: PlayerId) => Record<string, unknown>,
  ): void {
    for (const id of this.order) {
      out.push({ to: id, type, payload: payloadFor(id) });
    }
  }

  /* ---------------------------------------------------------- introspection */

  get phaseName(): Phase {
    return this.phase;
  }

  get clock(): { half: 1 | 2; remainingMs: number; roundNo: number } {
    return { half: this.half, remainingMs: this.halfRemainingMs, roundNo: this.roundNo };
  }

  get eventLog(): readonly MatchEvent[] {
    return this.events;
  }

  get isFinished(): boolean {
    return this.finished;
  }

  /**
   * Server-side answer key for the live question. For replay/audit tooling and the
   * bot used in tests — it is never part of any outbound message.
   */
  get audit(): { questionId: string; answerOptionId: string; phase: Phase } | null {
    return this.live
      ? { questionId: this.live.doc.id, answerOptionId: this.live.doc.answerOptionId, phase: this.phase }
      : null;
  }

  get result(): { goals: Record<PlayerId, number>; zones: Record<PlayerId, number> } {
    return { goals: this.goals(), zones: this.zones() };
  }
}

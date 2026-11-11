/**
 * gateway.ts — the protocol layer: session, queue, match lifecycle, dispatch.
 *
 * Deliberately transport-agnostic. It speaks `Connection`, never a socket, and it is
 * driven by an explicit `tick(now)` rather than its own interval. Consequences:
 *
 *   - the full two-player protocol is testable in milliseconds with a virtual clock
 *   - the same object can be driven by a 50 ms production loop or a 10 000× replay
 *   - swapping `ws` for `uWebSockets.js` touches one file (`index.ts`), not this one
 *
 * Everything competitive is decided by `MatchRoom`; this file only routes.
 */

import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";

import { MATCH_LIMITS, MATCHMAKING } from "./config.ts";
import { Matchmaker } from "./matchmaking.ts";
import { MatchRoom } from "./match-room.ts";
import { drawPool, type LoadedBank } from "./bank-loader.ts";
import type { Connection } from "./connection.ts";
import type { Locale, Outbound, PlayerRef, Region } from "./types.ts";

const PROTOCOL_VERSION = 1;
const SESSION_SECRET = process.env.SESSION_SECRET ?? "dev-session-secret-change-me";
const MAX_FRAME_BYTES = 16 * 1024;
const RATE_BURST = 30;
const RATE_PER_SECOND = 10;

const VALID_LOCALES: readonly Locale[] = ["en", "ar"];
const VALID_REGIONS: readonly Region[] = ["EU", "MENA", "NA", "APAC", "SA"];

const PSEUDONYM_STEMS = [
  "Striker", "Keeper", "Winger", "Sweeper", "Pivot",
  "Playmaker", "Poacher", "Anchor", "Fullback", "Libero",
];

export interface GatewayOptions {
  bank: LoadedBank;
  /** Injectable for tests; production passes Date.now. */
  clock?: () => number;
  onMatchEnd?: (summary: {
    matchId: string;
    players: Array<{ playerId: string; outcome: string; ratingDelta: number }>;
  }) => void;
}

interface BotState {
  playerId: string;
  token: string | null;
  questionId: string | null;
  answerAt: number;
  accuracy: number;
}

interface Session {
  player: PlayerRef;
  connId: string;
  matchId: string | null;
  queuedAt: number | null;
  /** Simple token bucket; resets per second. */
  tokens: number;
  lastRefill: number;
}

export interface GatewayStats {
  connections: number;
  sessions: number;
  queued: number;
  liveMatches: number;
  matchesStarted: number;
}

/* ------------------------------------------------------------------ tokens */

const b64url = (value: string): string => Buffer.from(value, "utf8").toString("base64url");

export const signSessionToken = (playerId: string): string => {
  const body = b64url(playerId);
  const mac = createHmac("sha256", SESSION_SECRET).update(body).digest("base64url").slice(0, 22);
  return `${body}.${mac}`;
};

const verifySessionToken = (token: string): string | null => {
  const [body, mac] = token.split(".");
  if (!body || !mac) return null;
  const expected = createHmac("sha256", SESSION_SECRET).update(body).digest("base64url").slice(0, 22);
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  return Buffer.from(body, "base64url").toString("utf8");
};

const playerIdForDevice = (deviceId: string): string =>
  `p_${createHash("sha256").update(deviceId).digest("base64url").slice(0, 12)}`;

const seedFrom = (value: string): number =>
  Number.parseInt(createHash("sha256").update(value).digest("hex").slice(0, 8), 16);

/**
 * Pseudonym, not a name. No signup, no PII, and no free-text field to moderate in a
 * 90-second cross-language game.
 */
const sanitizeDisplayName = (value: unknown): string | null => {
  if (typeof value !== "string") return null;
  const clean = Array.from(value.normalize("NFKC").replace(/[\\u0000-\\u001F\\u007F]/g, "").replace(/\\s+/g, " ").trim()).slice(0, 18).join("");
  return clean.length >= 2 ? clean : null;
};

const pseudonymFor = (playerId: string): string => {
  const hash = createHash("sha256").update(playerId).digest();
  const stem = PSEUDONYM_STEMS[hash[0] % PSEUDONYM_STEMS.length];
  const number = 1000 + ((hash[1] << 8 | hash[2]) % 9000);
  return `${stem}-${number}`;
};

/* ----------------------------------------------------------------- gateway */

export class Gateway {
  private readonly bank: LoadedBank;
  private readonly clock: () => number;
  private readonly onMatchEnd: GatewayOptions["onMatchEnd"];
  private readonly matchmaker = new Matchmaker();

  private readonly sessions = new Map<string, Session>();
  private readonly sessionByConn = new Map<string, string>();
  private readonly connByPlayer = new Map<string, Connection>();
  private readonly rooms = new Map<string, MatchRoom>();
  private readonly botsByMatch = new Map<string, BotState>();
  private readonly ratings = new Map<string, number>();

  private lastMatchPass = Number.NEGATIVE_INFINITY;
  private matchesStarted = 0;

  constructor(options: GatewayOptions) {
    this.bank = options.bank;
    this.clock = options.clock ?? (() => Date.now());
    this.onMatchEnd = options.onMatchEnd;
  }

  /* ------------------------------------------------------------ connection */

  handleConnection(conn: Connection): void {
    // Clock sync is offered before hello so the client can estimate an offset while
    // the player is still reading the home screen.
    conn.send("welcome", {
      protocolVersion: PROTOCOL_VERSION,
      serverNow: this.clock(),
      sessionToken: null,
    });
  }

  handleFrame(conn: Connection, raw: unknown): void {
    const now = this.clock();

    if (typeof raw === "string" && Buffer.byteLength(raw, "utf8") > MAX_FRAME_BYTES) {
      conn.send("error", { code: "FRAME_TOO_LARGE" });
      conn.close(1009, "frame too large");
      return;
    }

    let frame: { v?: number; type?: string; payload?: unknown };
    try {
      frame = typeof raw === "string" ? JSON.parse(raw) : (raw as typeof frame);
    } catch {
      conn.send("error", { code: "BAD_FRAME" });
      return;
    }

    if (!frame || typeof frame.type !== "string") {
      conn.send("error", { code: "BAD_FRAME" });
      return;
    }

    const payload = (frame.payload ?? {}) as Record<string, unknown>;
    const playerId = this.sessionByConn.get(conn.id);
    const session = playerId ? this.sessions.get(playerId) : undefined;

    // `hello` is the only frame allowed before a session exists.
    if (frame.type === "hello") {
      this.handleHello(conn, payload, now);
      return;
    }

    if (!session) {
      conn.send("error", { code: "NOT_HELLO" });
      return;
    }

    if (!this.takeToken(session, now)) {
      conn.send("error", { code: "RATE_LIMITED" });
      return;
    }

    switch (frame.type) {
      case "queue.join":
        this.handleQueueJoin(session, now);
        return;
      case "bot.join":
        this.handleBotJoin(session, now);
        return;
      case "queue.leave":
        this.handleQueueLeave(session);
        return;
      case "round.answer":
        this.handleAnswer(session, payload, now);
        return;
      case "match.forfeit":
        this.handleForfeit(session, now);
        return;
      case "ping":
        conn.send("pong", { c0: payload.c0 ?? null, serverNow: now });
        return;
      case "match.ready":
        return;
      default:
        conn.send("error", { code: "UNKNOWN_TYPE", type: frame.type });
    }
  }

  handleDisconnect(conn: Connection): void {
    const now = this.clock();
    const playerId = this.sessionByConn.get(conn.id);
    this.sessionByConn.delete(conn.id);
    if (!playerId) return;

    const session = this.sessions.get(playerId);
    if (!session) return;

    // Only clear the routing entry if THIS connection is the live one; a reconnect may
    // already have replaced it.
    if (this.connByPlayer.get(playerId) === conn) this.connByPlayer.delete(playerId);

    this.matchmaker.cancel(playerId);
    if (session.queuedAt !== null) session.queuedAt = null;

    const room = session.matchId ? this.rooms.get(session.matchId) : undefined;
    if (room && !room.isFinished) this.dispatch(room.disconnect(playerId, now), now);
  }

  /* ---------------------------------------------------------------- hello */

  private handleHello(conn: Connection, payload: Record<string, unknown>, now: number): void {
    const locale = String(payload.locale ?? "en") as Locale;
    const region = String(payload.region ?? "EU") as Region;

    if (!VALID_LOCALES.includes(locale)) {
      conn.send("error", { code: "BAD_LOCALE", allowed: VALID_LOCALES });
      return;
    }
    if (!VALID_REGIONS.includes(region)) {
      conn.send("error", { code: "BAD_REGION", allowed: VALID_REGIONS });
      return;
    }

    const token = typeof payload.sessionToken === "string" ? payload.sessionToken : null;
    const resumedId = token ? verifySessionToken(token) : null;
    const deviceId = typeof payload.deviceId === "string" ? payload.deviceId : null;
    const playerId = resumedId ?? (deviceId ? playerIdForDevice(deviceId) : `p_${randomUUID()}`);

    let session = this.sessions.get(playerId);
    const requestedName = sanitizeDisplayName(payload.displayName);
    if (session) {
      // Reconnect: hand the player to the new connection and try to rejoin the match.
      this.sessionByConn.delete(session.connId);
      session.connId = conn.id;
      session.player.locale = locale;
      session.player.region = region;
      if (requestedName) session.player.displayName = requestedName;
    } else {
      session = {
        player: {
          playerId,
          displayName: requestedName ?? pseudonymFor(playerId),
          locale,
          region,
          rating: this.ratings.get(playerId) ?? 1000,
        },
        connId: conn.id,
        matchId: null,
        queuedAt: null,
        tokens: RATE_BURST,
        lastRefill: now,
      };
      this.sessions.set(playerId, session);
    }

    this.sessionByConn.set(conn.id, playerId);
    this.connByPlayer.set(playerId, conn);

    conn.send("hello.ack", {
      playerId,
      displayName: session.player.displayName,
      sessionToken: signSessionToken(playerId),
      locale,
      dir: locale === "ar" ? "rtl" : "ltr",
      serverNow: now,
      resumed: Boolean(resumedId),
    });

    // A resumed session may still own a live match.
    const room = session.matchId ? this.rooms.get(session.matchId) : undefined;
    if (room && !room.isFinished) this.dispatch(room.reconnect(playerId, now), now);
    else session.matchId = null;
  }

  /* ----------------------------------------------------------- queueing */

  private handleQueueJoin(session: Session, now: number): void {
    if (session.matchId) {
      this.send(session.player.playerId, "error", { code: "ALREADY_IN_MATCH" });
      return;
    }
    if (session.queuedAt !== null) {
      // Idempotent: a double tap on PLAY must not create two tickets.
      this.send(session.player.playerId, "queue.joined", { ticket: null, alreadyQueued: true });
      return;
    }
    const entry = this.matchmaker.enqueue(session.player, now, 0);
    session.queuedAt = now;
    this.send(session.player.playerId, "queue.joined", {
      ticket: entry.ticket,
      estimateMs: 6_000,
      queued: this.matchmaker.size,
    });
  }

  private handleBotJoin(session: Session, now: number): void {
    if (session.matchId) {
      this.send(session.player.playerId, "error", { code: "ALREADY_IN_MATCH" });
      return;
    }
    this.matchmaker.cancel(session.player.playerId);
    session.queuedAt = null;
    this.createBotMatch(session, now);
  }

  private createBotMatch(session: Session, now: number): void {
    const player = session.player;
    const botId = `bot_${randomUUID()}`;
    const bot: PlayerRef = {
      playerId: botId,
      displayName: "AI Rookie",
      locale: player.locale,
      region: player.region,
      rating: player.rating,
    };
    const matchId = `m_ai_${randomUUID().replaceAll("-", "").slice(0, 12)}`;
    const room = new MatchRoom({
      matchId,
      players: [player, bot],
      pool: drawPool(this.bank.questions, MATCH_LIMITS.POOL_SIZE, seedFrom(matchId)),
      shotPool: this.bank.shotQuestions,
      catalog: this.bank.catalog,
    });

    const waitMs = session.queuedAt === null ? 0 : now - session.queuedAt;
    session.matchId = matchId;
    session.queuedAt = null;
    this.rooms.set(matchId, room);
    this.botsByMatch.set(matchId, {
      playerId: botId,
      token: null,
      questionId: null,
      answerAt: 0,
      // Each match gets a reproducible but slightly different bot skill (58–78%).
      accuracy: 0.58 + (seedFrom(`${matchId}:skill`) % 21) / 100,
    });
    this.matchesStarted += 1;

    this.send(player.playerId, "match.found", {
      matchId,
      you: player.playerId,
      youColor: "blue",
      opponentColor: "red",
      opponent: {
        displayName: bot.displayName,
        locale: bot.locale,
        dir: bot.locale === "ar" ? "rtl" : "ltr",
        rating: bot.rating,
        isBot: true,
      },
      crossRegion: false,
      waitMs,
      isBot: true,
      serverNow: now,
    });
    this.dispatch(room.start(now), now);
  }

  private handleForfeit(session: Session, now: number): void {
    const room = session.matchId ? this.rooms.get(session.matchId) : undefined;
    if (!room || room.isFinished) {
      this.send(session.player.playerId, "error", { code: "NOT_IN_MATCH" });
      return;
    }
    this.dispatch(room.forfeit(session.player.playerId, now), now);
    this.retire(room);
  }

  private handleQueueLeave(session: Session): void {
    this.matchmaker.cancel(session.player.playerId);
    session.queuedAt = null;
    this.send(session.player.playerId, "queue.left", {});
  }

  /* ------------------------------------------------------------ answers */

  private handleAnswer(session: Session, payload: Record<string, unknown>, now: number): void {
    const room = session.matchId ? this.rooms.get(session.matchId) : undefined;
    if (!room || room.isFinished) {
      this.send(session.player.playerId, "error", { code: "NOT_IN_MATCH" });
      return;
    }
    const token = typeof payload.token === "string" ? payload.token : "";
    const optionId = typeof payload.optionId === "string" ? payload.optionId : "";
    if (!token || !optionId) {
      this.send(session.player.playerId, "error", { code: "BAD_ANSWER" });
      return;
    }
    const clientMs = typeof payload.clientMs === "number" ? payload.clientMs : undefined;
    this.dispatch(room.submitAnswer(session.player.playerId, { token, optionId, clientMs }, now), now);
  }

  /* --------------------------------------------------------------- tick */

  /**
   * Drive the world to `now`. Call every 50 ms in production.
   * Matchmaking runs on its own coarser cadence (250 ms).
   */
  tick(now: number): void {
    if (now - this.lastMatchPass >= MATCHMAKING.TICK_MS) {
      this.lastMatchPass = now;
      for (const pairing of this.matchmaker.tick(now)) this.createMatch(pairing, now);
    }

    // A real player always gets the first chance at a human opponent. After 15 seconds,
    // an unmatched ticket becomes a bot match so matchmaking cannot wait forever.
    for (const entry of this.matchmaker.tickets()) {
      if (now - entry.joinedAt < 15_000) continue;
      const session = this.sessions.get(entry.player.playerId);
      if (!session || session.queuedAt === null || !this.connByPlayer.has(entry.player.playerId)) {
        this.matchmaker.cancel(entry.player.playerId);
        continue;
      }
      this.matchmaker.cancel(entry.player.playerId);
      session.queuedAt = null;
      this.createBotMatch(session, now);
    }

    for (const room of [...this.rooms.values()]) {
      const out = room.advance(now);
      if (out.length) this.dispatch(out, now);
      this.advanceBot(room, now);
      if (room.isFinished) this.retire(room);
    }
  }

  /* ------------------------------------------------------------- matches */

  private createMatch(
    pairing: ReturnType<Matchmaker["tick"]>[number],
    now: number,
  ): void {
    const [a, b] = pairing.players;
    const sessions = [a, b].map((entry) => this.sessions.get(entry.player.playerId));

    // A player can vanish between the pairing pass and match creation.
    if (sessions.some((s) => !s)) {
      for (const entry of pairing.players) {
        if (this.sessions.has(entry.player.playerId)) this.matchmaker.cancel(entry.player.playerId);
      }
      return;
    }

    const [sa, sb] = sessions as [Session, Session];
    const room = new MatchRoom({
      matchId: pairing.matchId,
      players: [sa.player, sb.player],
      pool: drawPool(this.bank.questions, MATCH_LIMITS.POOL_SIZE, seedFrom(pairing.matchId)),
      shotPool: this.bank.shotQuestions,
      catalog: this.bank.catalog,
    });

    this.rooms.set(pairing.matchId, room);
    this.matchesStarted += 1;

    for (const [self, other] of [
      [sa, sb],
      [sb, sa],
    ] as Array<[Session, Session]>) {
      self.matchId = pairing.matchId;
      self.queuedAt = null;
      this.send(self.player.playerId, "match.found", {
        matchId: pairing.matchId,
        you: self.player.playerId,
        youColor: self === sa ? "blue" : "red",
        opponentColor: self === sa ? "red" : "blue",
        opponent: {
          displayName: other.player.displayName,
          locale: other.player.locale,
          dir: other.player.locale === "ar" ? "rtl" : "ltr",
          rating: other.player.rating,
        },
        crossRegion: pairing.crossRegion,
        waitMs: pairing.waitMs,
        serverNow: now,
      });
    }

    this.dispatch(room.start(now), now);
  }

  private advanceBot(room: MatchRoom, now: number): void {
    const bot = this.botsByMatch.get(room.matchId);
    if (!bot || !bot.token || now < bot.answerAt || room.isFinished) return;

    const audit = room.audit;
    if (!audit || audit.questionId !== bot.questionId) {
      bot.token = null;
      bot.questionId = null;
      return;
    }

    const question = [...this.bank.questions, ...this.bank.shotQuestions]
      .find((item) => item.id === audit.questionId);
    if (!question) {
      bot.token = null;
      return;
    }

    const roll = seedFrom(`${room.matchId}:${audit.questionId}:skill`) % 1_000 / 1_000;
    const correct = roll < bot.accuracy;
    const optionId = correct
      ? audit.answerOptionId
      : (question.options.find((option) => option.id !== audit.answerOptionId)?.id
        ?? question.options[0]?.id
        ?? audit.answerOptionId);
    const token = bot.token;
    bot.token = null;
    bot.questionId = null;
    this.dispatch(room.submitAnswer(bot.playerId, { token, optionId }, now), now);
  }

  private retire(room: MatchRoom): void {
    this.rooms.delete(room.matchId);
    this.botsByMatch.delete(room.matchId);
    const summary: Array<{ playerId: string; outcome: string; ratingDelta: number }> = [];
    for (const playerId of Object.keys(room.players)) {
      const session = this.sessions.get(playerId);
      if (session && session.matchId === room.matchId) session.matchId = null;
      summary.push({ playerId, outcome: "unknown", ratingDelta: 0 });
    }
    this.onMatchEnd?.({ matchId: room.matchId, players: summary });
  }

  /* ------------------------------------------------------------ dispatch */

  private dispatch(out: Outbound[], now: number): void {
    for (const env of out) {
      const botMatch = [...this.botsByMatch.entries()].find(([, bot]) => bot.playerId === env.to);
      if (botMatch) {
        const [matchId, bot] = botMatch;
        if (env.type === "round.question" || env.type === "shoot.question") {
          const payload = env.payload as {
            token?: string;
            youAreShooting?: boolean;
            view?: { questionId?: string };
          };
          const isBotQuestion = env.type === "round.question" || payload.youAreShooting === true;
          if (isBotQuestion && typeof payload.token === "string" && typeof payload.view?.questionId === "string") {
            const delay = 700 + seedFrom(`${matchId}:${payload.view.questionId}:delay`) % 2_200;
            bot.token = payload.token;
            bot.questionId = payload.view.questionId;
            bot.answerAt = now + delay;
          }
        }
        continue;
      }
      if (env.to === "all") {
        for (const conn of this.connByPlayer.values()) conn.send(env.type, env.payload);
        continue;
      }

      const conn = this.connByPlayer.get(env.to);
      const sessionForRecipient = this.sessions.get(env.to);
      const isBotMatch = Boolean(sessionForRecipient?.matchId && this.botsByMatch.has(sessionForRecipient.matchId));
      if (conn) {
        if (env.type === "match.end" && isBotMatch && typeof env.payload === "object" && env.payload !== null) {
          conn.send(env.type, { ...(env.payload as Record<string, unknown>), ratingDelta: 0 });
        } else {
          conn.send(env.type, env.payload);
        }
      }

      if (env.type === "match.end") {
        const payload = env.payload as { outcome?: string; ratingDelta?: number };
        const delta = payload.ratingDelta ?? 0;
        const session = this.sessions.get(env.to);
        if (session && !isBotMatch) {
          const next = (this.ratings.get(env.to) ?? session.player.rating) + delta;
          this.ratings.set(env.to, next);
          session.player.rating = next;
        }
      }
    }
    void now;
  }

  private send(playerId: string, type: string, payload: unknown): void {
    this.connByPlayer.get(playerId)?.send(type, payload);
  }

  private takeToken(session: Session, now: number): boolean {
    const elapsed = Math.max(0, now - session.lastRefill);
    if (elapsed >= 1_000) {
      session.tokens = RATE_BURST;
      session.lastRefill = now;
    } else {
      session.tokens = Math.min(RATE_BURST, session.tokens + (elapsed / 1_000) * RATE_PER_SECOND);
    }
    if (session.tokens < 1) return false;
    session.tokens -= 1;
    return true;
  }

  stats(): GatewayStats {
    return {
      connections: this.connByPlayer.size,
      sessions: this.sessions.size,
      queued: this.matchmaker.size,
      liveMatches: this.rooms.size,
      matchesStarted: this.matchesStarted,
    };
  }
}

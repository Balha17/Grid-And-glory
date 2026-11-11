/**
 * Protocol-level tests: a real gateway, two in-memory connections, a virtual clock.
 *
 * This is the test that would have caught every integration bug the engine tests cannot:
 * wrong routing, a missing fan-out, a session that survives a reconnect incorrectly, or
 * an answer key leaking through the transport rather than through the renderer.
 */

import { assert, runDeferred, summarize, test, testAsync } from "./harness.ts";
import { Gateway } from "../src/gateway.ts";
import { MemoryConnection } from "../src/connection.ts";
import { loadBank } from "../src/bank-loader.ts";
import type { QuestionDoc } from "../src/types.ts";

const bank = await loadBank();
const byId = new Map<string, QuestionDoc>(bank.questions.map((q) => [q.id, q]));

const frame = (type: string, payload: unknown): string =>
  JSON.stringify({ v: 1, type, seq: 0, ts: 0, payload });

const lcg = (seed: number) => {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
};

interface Harness {
  gateway: Gateway;
  clock: { now: number };
  connect(id: string): MemoryConnection;
  hello(conn: MemoryConnection, locale: "en" | "ar", region?: string, deviceId?: string): void;
  join(conn: MemoryConnection): void;
}

const build = (): Harness => {
  const clock = { now: 1_000_000 };
  const gateway = new Gateway({ bank, clock: () => clock.now });
  const sessions = new Map<MemoryConnection, string>();

  const hello = (
    conn: MemoryConnection,
    locale: "en" | "ar",
    region = "EU",
    deviceId = conn.id,
  ): void => {
    gateway.handleFrame(conn, frame("hello", { deviceId, locale, region }));
    const ack = conn.last("hello.ack");
    assert.ok(ack, `hello.ack missing for ${conn.id}`);
    sessions.set(conn, (ack!.payload as { playerId: string }).playerId);
  };

  return {
    gateway,
    clock,
    connect(id: string) {
      const conn = new MemoryConnection(id, () => clock.now);
      gateway.handleConnection(conn);
      return conn;
    },
    hello,
    join(conn) {
      gateway.handleFrame(conn, frame("queue.join", {}));
    },
  };
};

/* --------------------------------------------------------------- handshake */

test("a new connection is greeted with server time before it says anything", () => {
  const h = build();
  const a = h.connect("c1");
  const welcome = a.last("welcome");
  assert.ok(welcome, "welcome frame is sent on connect");
  assert.equal((welcome!.payload as { protocolVersion: number }).protocolVersion, 1);
  assert.equal(typeof (welcome!.payload as { serverNow: number }).serverNow, "number");
});

test("hello issues a pseudonym, a locale-correct direction and a session token", () => {
  const h = build();
  const a = h.connect("c1");
  h.hello(a, "ar", "MENA", "device-a");

  const ack = a.last("hello.ack")!.payload as Record<string, unknown>;
  assert.equal(ack.locale, "ar");
  assert.equal(ack.dir, "rtl", "the server declares direction so the client never guesses");
  assert.match(String(ack.displayName), /-[0-9]{4}$/, "pseudonym, not a user-supplied name");
  assert.ok(typeof ack.sessionToken === "string" && String(ack.sessionToken).includes("."));
  assert.equal(ack.resumed, false);
});

test("the same device id always resolves to the same player", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "same-device");
  h.hello(b, "en", "EU", "same-device");
  const idA = (a.last("hello.ack")!.payload as { playerId: string }).playerId;
  const idB = (b.last("hello.ack")!.payload as { playerId: string }).playerId;
  assert.equal(idA, idB, "reinstall with the same device id keeps the profile");
});

test("frames before hello are refused rather than silently dropped", () => {
  const h = build();
  const a = h.connect("c1");
  h.join(a);
  assert.equal((a.last("error")!.payload as { code: string }).code, "NOT_HELLO");
});

/* -------------------------------------------------------------- pairing */

test("an English player and an Arabic player are matched and told about each other", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);

  h.clock.now += 300;
  h.gateway.tick(h.clock.now);

  const foundA = a.last("match.found");
  const foundB = b.last("match.found");
  assert.ok(foundA && foundB, "both players are notified");

  const opponentOfA = (foundA!.payload as { opponent: { locale: string; dir: string } }).opponent;
  assert.equal(opponentOfA.locale, "ar", "the English player is told they face an Arabic speaker");
  assert.equal(opponentOfA.dir, "rtl");

  const matchA = (foundA!.payload as { matchId: string }).matchId;
  const matchB = (foundB!.payload as { matchId: string }).matchId;
  assert.equal(matchA, matchB, "both are in the same match");
  assert.equal(a.has("match.start"), true);
  assert.equal(b.has("match.start"), true);
});

test("a queued player who disconnects is removed from the queue, not left as a ghost", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);

  h.gateway.handleDisconnect(b);
  h.clock.now += 1_000;
  h.gateway.tick(h.clock.now);

  assert.equal(h.gateway.stats().liveMatches, 0, "no match is created against a disconnected ticket");
  assert.equal(h.gateway.stats().queued, 1, "the remaining player stays queued");
});

/* ------------------------------------------------------------ full match */

interface MatchRun {
  aFrames: number;
  bFrames: number;
  leakedAnswerKey: boolean;
  steps: number;
}

const playMatch = (h: Harness, a: MemoryConnection, b: MemoryConnection): MatchRun => {
  const random = lcg(99);
  const answered = new Set<string>();
  let leakedAnswerKey = false;
  let steps = 0;

  h.clock.now += 300;
  h.gateway.tick(h.clock.now);

  const cursors = new Map<MemoryConnection, number>([
    [a, 0],
    [b, 0],
  ]);

  const pump = (conn: MemoryConnection, accuracy: number): void => {
    let guard = 0;
    while (guard < 500) {
      guard += 1;
      const frames = conn.sent;
      let index = cursors.get(conn) ?? 0;
      if (index >= frames.length) break;
      const f = frames[index];
      cursors.set(conn, index + 1);
      index += 1;

      if (f.type !== "round.question" && f.type !== "shoot.question") continue;

      const payload = f.payload as {
        token: string;
        roundNo: number;
        youAreShooting?: boolean;
        view: { questionId: string; options: Array<{ id: string }> };
      };

      // The answer key must never be on the wire. Check every question frame.
      const serialized = JSON.stringify(payload);
      if (serialized.includes("answerOptionId")) leakedAnswerKey = true;

      if (f.type === "shoot.question" && payload.youAreShooting !== true) continue;

      const key = `${payload.roundNo}:${payload.view.questionId}`;
      if (answered.has(key)) continue;
      answered.add(key);

      const doc = byId.get(payload.view.questionId);
      if (!doc) throw new Error(`unknown question ${payload.view.questionId}`);

      const pickCorrect = random() < accuracy;
      const optionId = pickCorrect
        ? doc.answerOptionId
        : (doc.options.find((o) => o.id !== doc.answerOptionId)?.id ?? doc.options[0].id);

      h.gateway.handleFrame(conn, frame("round.answer", { token: payload.token, optionId }));
    }
  };

  while (!a.has("match.end") && steps < 4_000) {
    steps += 1;
    h.clock.now += 50;
    h.gateway.tick(h.clock.now);
    pump(a, 0.95);
    pump(b, 0.45);
  }

  return { aFrames: a.sent.length, bFrames: b.sent.length, leakedAnswerKey, steps };
};

test("two players play a complete match over the protocol", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);

  const run = playMatch(h, a, b);

  assert.equal(a.has("match.end"), true, "the stronger player receives full time");
  assert.equal(b.has("match.end"), true);
  assert.equal(run.leakedAnswerKey, false, "no question frame carries the answer key");
  assert.ok(a.all("round.question").length >= 8, "a real number of rounds was played");
  assert.ok(b.all("shoot.question").length >= 1, "reaching zone 5 produced a Shooting Chance");

  const endA = a.last("match.end")!.payload as { outcome: string; goals: Record<string, string> };
  const endB = b.last("match.end")!.payload as { outcome: string };
  assert.equal(endA.outcome, "win");
  assert.equal(endB.outcome, "loss");
  assert.ok(Number(Object.values(endA.goals)[0]) >= 1, "the accurate player scored");
});

test("the match is retired from the gateway once it ends", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);
  playMatch(h, a, b);

  assert.equal(h.gateway.stats().liveMatches, 0, "finished rooms are freed, not leaked");
  assert.equal(h.gateway.stats().matchesStarted, 1);
});

/* --------------------------------------------------------------- answers */

test("a forged answer token is refused in transit", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);
  h.clock.now += 300;
  h.gateway.tick(h.clock.now);
  h.clock.now += 1_100;
  h.gateway.tick(h.clock.now);

  h.gateway.handleFrame(a, frame("round.answer", { token: "forged.token", optionId: "opt_x" }));
  const error = a.last("error");
  assert.ok(error, "the answer is rejected");
  assert.equal((error!.payload as { code: string }).code, "BAD_TOKEN");
});

test("answering outside a match is rejected instead of crashing the gateway", () => {
  const h = build();
  const a = h.connect("c1");
  h.hello(a, "en", "EU", "dev-a");
  h.gateway.handleFrame(a, frame("round.answer", { token: "x.y", optionId: "opt_a" }));
  assert.equal((a.last("error")!.payload as { code: string }).code, "NOT_IN_MATCH");
});

test("a burst of frames is rate limited rather than processed", () => {
  const h = build();
  const a = h.connect("c1");
  h.hello(a, "en", "EU", "dev-a");

  for (let i = 0; i < 60; i += 1) {
    h.gateway.handleFrame(a, frame("ping", { c0: i }));
  }
  const limited = a.sent.filter(
    (f) => f.type === "error" && (f.payload as { code: string }).code === "RATE_LIMITED",
  );
  assert.ok(limited.length > 0, "flooding is cut off");
  assert.ok(a.all("pong").length <= 30, "the burst budget is bounded");
});

/* ------------------------------------------------------------- reconnect */

test("a dropped player can resume the same match with their session token", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);
  h.clock.now += 300;
  h.gateway.tick(h.clock.now);

  const token = (a.last("hello.ack")!.payload as { sessionToken: string }).sessionToken;
  const matchId = (a.last("match.found")!.payload as { matchId: string }).matchId;

  h.gateway.handleDisconnect(a);
  const notice = b.last("opponent.connection")!.payload as { connected: boolean; graceMs: number };
  assert.equal(notice.connected, false);
  assert.equal(notice.graceMs, 25_000);

  // Same human, new socket, inside the grace window.
  const a2 = h.connect("c1b");
  h.gateway.handleFrame(a2, frame("hello", { sessionToken: token, locale: "en", region: "EU" }));

  const ack = a2.last("hello.ack")!.payload as { resumed: boolean; playerId: string };
  assert.equal(ack.resumed, true, "identity is restored from the token, not re-created");
  const sync = a2.last("state.sync");
  assert.ok(sync, "the returning player is resynchronised");
  assert.equal((sync!.payload as { matchId: string }).matchId, matchId);

  h.clock.now += 2_000;
  h.gateway.tick(h.clock.now);
  assert.equal(a2.has("match.end"), false, "the match is still live, not forfeited");
});

test("reconnecting after the grace window does not resurrect a forfeited match", () => {
  const h = build();
  const a = h.connect("c1");
  const b = h.connect("c2");
  h.hello(a, "en", "EU", "dev-a");
  h.hello(b, "ar", "EU", "dev-b");
  h.join(a);
  h.join(b);
  h.clock.now += 300;
  h.gateway.tick(h.clock.now);

  const token = (a.last("hello.ack")!.payload as { sessionToken: string }).sessionToken;

  h.gateway.handleDisconnect(a);
  h.clock.now += 26_000;
  h.gateway.tick(h.clock.now);
  assert.equal(b.has("match.end"), true, "the opponent wins by forfeit");

  const a2 = h.connect("c1b");
  h.gateway.handleFrame(a2, frame("hello", { sessionToken: token, locale: "en", region: "EU" }));
  assert.equal(a2.has("state.sync"), false, "there is no match to sync into");
  assert.equal(a2.has("match.end"), false, "and no stale result is replayed");
});

/* ----------------------------------------------------- real socket smoke */

testAsync("the real HTTP/WebSocket transport accepts a client and completes a handshake", async () => {
  const { createGameServer } = await import("../src/server.ts");
  const { WebSocket } = await import("ws");

  const server = await createGameServer({ bank, port: 0, host: "127.0.0.1" });
  try {
    const socket = new WebSocket(`ws://127.0.0.1:${server.port}/ws`);
    const inbox: Array<{ type: string; payload: Record<string, unknown> }> = [];

    const waitFor = (type: string): Promise<{ type: string; payload: Record<string, unknown> }> =>
      new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`timed out waiting for ${type}`)), 4_000);
        const check = (): void => {
          const found = inbox.find((f) => f.type === type);
          if (found) {
            clearTimeout(timer);
            resolve(found);
          } else {
            setTimeout(check, 20);
          }
        };
        check();
      });

    socket.on("message", (data) => {
      inbox.push(JSON.parse(data.toString()));
    });

    await new Promise<void>((resolve, reject) => {
      socket.once("open", () => resolve());
      socket.once("error", reject);
    });

    await waitFor("welcome");
    socket.send(JSON.stringify({ v: 1, type: "hello", payload: { deviceId: "smoke-1", locale: "ar", region: "MENA" } }));

    const ack = await waitFor("hello.ack");
    assert.equal(ack.payload.dir, "rtl");
    assert.ok(String(ack.payload.sessionToken).includes("."));

    const health = await fetch(`http://127.0.0.1:${server.port}/healthz`);
    assert.equal(health.status, 200);
    const body = (await health.json()) as { ok: boolean; sessions: number };
    assert.equal(body.ok, true);
    assert.ok(body.sessions >= 1);

    socket.close();
  } finally {
    await server.close();
  }
});

await runDeferred();
summarize("gateway");

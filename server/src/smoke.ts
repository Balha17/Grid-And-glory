/**
 * smoke.ts — drive two real clients through a real match over a real socket.
 *
 *   npm run serve            # terminal 1
 *   npm run smoke            # terminal 2
 *
 * Unlike the unit tests (which use in-memory connections and a virtual clock), this
 * exercises the actual HTTP upgrade, JSON framing, gateway routing and teardown. It is
 * also the quickest way to see the cross-language guarantee from the outside: the two
 * clients are told the same matchId and receive different scripts of the same question.
 */

import { WebSocket } from "ws";

const URL = process.env.URL ?? "ws://127.0.0.1:8080/ws";
const DEADLINE_MS = 240_000;

const send = (socket: WebSocket, type: string, payload: unknown): void => {
  if (socket.readyState !== socket.OPEN) return;
  socket.send(JSON.stringify({ v: 1, type, seq: 0, ts: Date.now(), payload }));
};

const log = (who: string, message: string): void => {
  console.log(`${new Date().toISOString().slice(11, 23)}  ${who.padEnd(3)}  ${message}`);
};

interface Bot {
  label: string;
  socket: WebSocket;
  rounds: number;
}

const connect = (locale: "en" | "ar", label: string): Bot => {
  const socket = new WebSocket(URL);
  const bot: Bot = { label, socket, rounds: 0 };
  const answered = new Set<string>();

  socket.on("open", () => {
    send(socket, "hello", {
      deviceId: `smoke-${locale}`,
      locale,
      // Same region on purpose: cross-region would add 8 s of queueing, and this
      // smoke test is about the protocol, not the matchmaker's latency policy.
      region: "EU",
    });
  });

  socket.on("message", (data) => {
    const frame = JSON.parse(data.toString()) as { type: string; payload: Record<string, unknown> };
    const payload = frame.payload ?? {};

    switch (frame.type) {
      case "welcome":
        break;

      case "hello.ack":
        log(label, `connected as ${String(payload.displayName)} (${String(payload.dir)})`);
        send(socket, "queue.join", {});
        break;

      case "queue.joined":
        log(label, "queued");
        break;

      case "match.found": {
        const opponent = payload.opponent as { displayName: string; locale: string };
        log(label, `matched vs ${opponent.displayName} [${opponent.locale}] match=${String(payload.matchId)}`);
        break;
      }

      case "round.question":
      case "shoot.question": {
        const view = payload.view as { questionId: string; format: string; options: Array<{ id: string }> };
        const roundNo = Number(payload.roundNo ?? 0);
        // Round numbers restart at half time, so they cannot be the identity of a round.
        // The token is unique per (match, round, player, expiry).
        const key = String(payload.token);
        if (answered.has(key)) break;
        answered.add(key);

        if (frame.type === "shoot.question" && payload.youAreShooting !== true) break;

        bot.rounds += 1;
        // Answer like a human: a beat of hesitation, then the first option that feels right.
        const delay = 350 + Math.floor(Math.random() * 900);
        setTimeout(() => {
          const pick = view.options[Math.floor(Math.random() * view.options.length)];
          send(socket, "round.answer", {
            token: payload.token,
            optionId: pick.id,
            clientMs: Date.now(),
          });
        }, delay);
        break;
      }

      case "round.reveal":
        if (bot.rounds % 4 === 0) {
          log(label, `R${String(payload.roundNo)} ${String(payload.outcome)} (${String(payload.delta)}) → zone ${String(payload.zone)}`);
        }
        break;

      case "shoot.reveal":
        log(label, payload.scored === true ? "⚽ GOAL" : "🧤 saved");
        break;

      case "match.second_half":
        log(label, "second half");
        break;

      case "match.end": {
        const goals = payload.goals as Record<string, number>;
        log(label, `FULL TIME ${String(payload.outcome)} (${String(payload.decidedBy)}) goals=${JSON.stringify(goals)}`);
        socket.close();
        break;
      }

      case "error":
        log(label, `error ${String(payload.code)}`);
        break;

      default:
        break;
    }
  });

  socket.on("error", (err) => log(label, `socket error: ${err.message}`));

  return bot;
};

const bots = [connect("en", "EN"), connect("ar", "AR")];

const timer = setTimeout(() => {
  log("--", "deadline exceeded — is the server running?");
  for (const bot of bots) bot.socket.close();
  process.exitCode = 1;
}, DEADLINE_MS);

let finished = 0;
for (const bot of bots) {
  bot.socket.on("close", () => {
    finished += 1;
    if (finished === bots.length) {
      clearTimeout(timer);
      console.log(`\n  finished: ${bots.map((b) => `${b.label}(${b.rounds} rounds)`).join(", ")}`);
    }
  });
}

/**
 * token.ts — binds a served question to a player and a round without revealing the key.
 *
 * Why bother: the client sends this token back with the answer. A modified client
 * cannot claim to have answered a different question, and the server can reject
 * tokens minted for another match/round/expiry. It is a tamper seal, not encryption —
 * the answer itself is simply never put on the wire before the reveal.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

const SECRET = process.env.QUESTION_TOKEN_SECRET ?? "dev-only-secret-change-in-production";
const b64url = (input: string | Buffer): string =>
  Buffer.from(input).toString("base64url");

export interface TokenClaims {
  matchId: string;
  roundNo: number;
  playerId: string;
  questionId: string;
  /** Absolute expiry, server ms. */
  exp: number;
}

export const signQuestionToken = (claims: TokenClaims): string => {
  const body = b64url(
    [claims.matchId, claims.roundNo, claims.playerId, claims.questionId, claims.exp].join("|"),
  );
  const mac = createHmac("sha256", SECRET).update(body).digest("base64url");
  return `${body}.${mac}`;
};

export type TokenVerdict = { ok: true; claims: TokenClaims } | { ok: false; reason: string };

export const verifyQuestionToken = (token: string, now: number): TokenVerdict => {
  const [body, mac] = token.split(".");
  if (!body || !mac) return { ok: false, reason: "malformed" };

  const expected = createHmac("sha256", SECRET).update(body).digest("base64url");
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return { ok: false, reason: "bad-signature" };

  const [matchId, roundNo, playerId, questionId, exp] = Buffer.from(body, "base64url")
    .toString("utf8")
    .split("|");

  const claims: TokenClaims = {
    matchId,
    roundNo: Number(roundNo),
    playerId,
    questionId,
    exp: Number(exp),
  };

  if (!Number.isFinite(claims.exp)) return { ok: false, reason: "bad-expiry" };
  if (now > claims.exp) return { ok: false, reason: "expired" };
  return { ok: true, claims };
};

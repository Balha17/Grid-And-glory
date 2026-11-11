/**
 * index.ts — process entry point.
 *
 *   PORT=8080 node server/src/index.ts
 *   curl localhost:8080/healthz
 */

import { loadBank } from "./bank-loader.ts";
import { createGameServer } from "./server.ts";

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? "0.0.0.0";

const bank = await loadBank();
const server = await createGameServer({ bank, port, host });

console.log(
  `Grid & Glory gateway listening on ws://${host}:${server.port}/ws ` +
    `(${bank.questions.length} questions, ${bank.shotQuestions.length} shot-pool)`,
);

const shutdown = async (signal: string): Promise<void> => {
  console.log(`${signal} received — draining`);
  // Give in-flight matches a moment to finish rather than dropping players mid-round.
  await new Promise((resolve) => setTimeout(resolve, 2_000));
  await server.close();
  process.exit(0);
};

process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));

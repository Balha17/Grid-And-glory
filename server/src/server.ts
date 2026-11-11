/**
 * server.ts — the real transport adapter. The only file that knows `ws` exists.
 *
 * Everything competitive lives in Gateway → MatchRoom; this file converts sockets into
 * `Connection`s, runs the 50 ms host loop, and exposes a health endpoint.
 */

import { createServer, type Server } from "node:http";
import { WebSocketServer } from "ws";

import { Gateway } from "./gateway.ts";
import type { LoadedBank } from "./bank-loader.ts";
import type { Connection } from "./connection.ts";

export interface GameServerOptions {
  bank: LoadedBank;
  port?: number;
  host?: string;
  /** Host-loop cadence. 50 ms adds at most 50 ms to a 180 ms budget. */
  tickMs?: number;
}

export interface GameServer {
  port: number;
  gateway: Gateway;
  close(): Promise<void>;
}

export const createGameServer = async (options: GameServerOptions): Promise<GameServer> => {
  const gateway = new Gateway({ bank: options.bank });
  const httpServer: Server = createServer((req, res) => {
    if (req.url === "/healthz") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, ...gateway.stats() }));
      return;
    }
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "not_found" }));
  });

  const wss = new WebSocketServer({ server: httpServer, path: "/ws", maxPayload: 16 * 1024 });

  wss.on("connection", (socket) => {
    let isOpen = true;
    const conn: Connection = {
      id: `c_${Math.random().toString(36).slice(2, 10)}`,
      send(type, payload) {
        if (!isOpen || socket.readyState !== socket.OPEN) return;
        socket.send(JSON.stringify({ v: 1, type, payload }));
      },
      close(code, reason) {
        isOpen = false;
        socket.close(code, reason);
      },
    };

    gateway.handleConnection(conn);

    socket.on("message", (data) => {
      gateway.handleFrame(conn, data.toString());
    });

    // `close` fires after `error` in most cases; guard so a player is only detached once.
    socket.on("close", () => {
      if (!isOpen) return;
      isOpen = false;
      gateway.handleDisconnect(conn);
    });

    socket.on("error", () => {
      if (!isOpen) return;
      isOpen = false;
      gateway.handleDisconnect(conn);
    });
  });

  const interval = setInterval(() => gateway.tick(Date.now()), options.tickMs ?? 50);

  const port = await new Promise<number>((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(options.port ?? 0, options.host ?? "127.0.0.1", () => {
      const address = httpServer.address();
      resolve(typeof address === "object" && address ? address.port : 0);
    });
  });

  return {
    port,
    gateway,
    close: async () => {
      clearInterval(interval);
      await new Promise<void>((resolve) => wss.close(() => resolve()));
      await new Promise<void>((resolve) => httpServer.close(() => resolve()));
    },
  };
};

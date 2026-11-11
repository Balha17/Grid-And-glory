/**
 * Transport seam.
 *
 * The gateway never touches a socket. It talks to this interface, which is why the whole
 * protocol — pairing, match lifecycle, reconnect — can be tested with in-memory
 * connections and a virtual clock, in milliseconds instead of ninety seconds.
 *
 * `server/src/index.ts` adapts a real `ws` socket to this shape; `MemoryConnection`
 * adapts a test.
 */

export interface Connection {
  readonly id: string;
  send(type: string, payload: unknown): void;
  close(code?: number, reason?: string): void;
}

export interface SentFrame {
  type: string;
  payload: unknown;
  at: number;
}

/** In-memory connection used by tests and by the load simulator. */
export class MemoryConnection implements Connection {
  readonly id: string;
  readonly sent: SentFrame[] = [];
  closed = false;
  closeCode: number | undefined;

  private readonly clock: () => number;

  constructor(id: string, clock: () => number = () => 0) {
    this.id = id;
    this.clock = clock;
  }

  send(type: string, payload: unknown): void {
    if (this.closed) return;
    this.sent.push({ type, payload, at: this.clock() });
  }

  close(code?: number): void {
    this.closed = true;
    this.closeCode = code;
  }

  /** Most recent frame of a given type, or undefined. */
  last(type: string): SentFrame | undefined {
    for (let i = this.sent.length - 1; i >= 0; i -= 1) {
      if (this.sent[i].type === type) return this.sent[i];
    }
    return undefined;
  }

  all(type: string): SentFrame[] {
    return this.sent.filter((f) => f.type === type);
  }

  has(type: string): boolean {
    return this.sent.some((f) => f.type === type);
  }
}

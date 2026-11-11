/**
 * Domain types. Deliberately free of framework imports so the match engine can be
 * unit-tested with plain node and reused if the transport changes.
 */

export type Locale = "en" | "ar";
export type TextDirection = "ltr" | "rtl";

export type Region = "EU" | "MENA" | "NA" | "APAC" | "SA";

export type QuestionFormat =
  | "mc"
  | "career_path"
  | "emoji_story"
  | "blur_reveal"
  | "stat_highlow";

/** A bilingual pair. The atomic unit of the whole content model. */
export interface Localized {
  en: string;
  ar: string;
}

export interface QuestionOption {
  id: string;
  en: string;
  ar: string;
}

/** Mirrors db/schema/question-bank.schema.json. */
export interface QuestionDoc {
  id: string;
  format: QuestionFormat;
  difficulty: number;
  region: string;
  prompt: Localized;
  options: QuestionOption[];
  answerOptionId: string;
  explainer: Localized;
  formatData?: Record<string, unknown>;
  media?: Array<{ assetId: string; role: string }>;
}

export interface EntityCatalog {
  clubs: Map<string, Localized>;
  people: Map<string, Localized>;
  nations: Map<string, Localized>;
  competitions: Map<string, Localized>;
}

/* ------------------------------------------------------------------ players */

export interface PlayerRef {
  playerId: string;
  displayName: string;
  locale: Locale;
  region: Region;
  rating: number;
}

export type PlayerId = string;

export interface PlayerState {
  playerId: string;
  locale: Locale;
  /** 0 = own goal line, 5 = opponent's goal mouth. */
  zone: number;
  goals: number;
  correct: number;
  wrong: number;
  noAnswer: number;
  /** Sum of answer latency across CORRECT answers — the "clinical" tiebreak. */
  correctTimeMs: number;
  /** Exactly one player holds the ball at any time. */
  possession: boolean;
  /** Server time of this player's most recent answer. Orders queued Shooting Chances. */
  lastAnswerAt: number | null;
  connected: boolean;
  disconnectedAt: number | null;
}

/* ------------------------------------------------------------------- rounds */

export interface SubmittedAnswer {
  playerId: PlayerId;
  optionId: string;
  /** Server receive time. The ONLY authority for speed. */
  receivedAt: number;
  /** Client-reported time. Telemetry / anti-cheat only, never used to score. */
  clientMs?: number;
}

export type AnswerOutcome = "correct" | "wrong" | "no_answer";

export interface PlayerRoundResult {
  outcome: AnswerOutcome;
  delta: number;
  /** Arrived after the window (but within grace): counts, cannot be fastest. */
  late: boolean;
  /** Time from window open to receipt. null when no answer was recorded. */
  elapsedMs: number | null;
  fastest: boolean;
}

export interface RoundResolution {
  results: Record<PlayerId, PlayerRoundResult>;
  fastestIds: PlayerId[];
  /** true when the jitter grace fired — useful for telemetry, invisible to players. */
  jitterTie: boolean;
}

/* ------------------------------------------------------------------ phases */

export type Phase =
  | "kickoff"
  | "round_intro"
  | "question_open"
  | "round_reveal"
  | "shooting_chance"
  | "shot_reveal"
  | "half_time"
  | "ended";

/* -------------------------------------------------------------- rendering */

export interface RenderedOption {
  id: string;
  text: string;
}

/**
 * Everything a client needs to draw one question in ONE locale.
 * Note what is absent: `answerOptionId`, and for stat_highlow the `values`.
 */
export interface QuestionView {
  questionId: string;
  format: QuestionFormat;
  difficulty: number;
  locale: Locale;
  dir: TextDirection;
  prompt: string;
  options: RenderedOption[];
  explainer: string;
  formatData: Record<string, unknown>;
  media: Array<{ assetId: string; url: string; alt: string }>;
}

/* ---------------------------------------------------------------- outbound */

export type Outbound =
  | { to: PlayerId | "all"; type: string; payload: unknown };

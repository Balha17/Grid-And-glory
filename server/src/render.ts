/**
 * render.ts — turns one canonical question into one player's private view.
 *
 * This is where "cross-language matchmaking" actually happens: the same question
 * row, rendered twice, with a per-player option order and a direction flag. The
 * answer key never enters this module's output.
 */

import type { EntityCatalog, Locale, QuestionDoc, QuestionView, RenderedOption, TextDirection } from "./types.ts";

export const directionOf = (locale: Locale): TextDirection => (locale === "ar" ? "rtl" : "ltr");

/** FNV-1a → 32-bit seed. Stable across processes and languages. */
const seedOf = (str: string): number => {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
};

const mulberry32 = (seed: number): (() => number) => {
  let s = seed;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

/**
 * Deterministic shuffle. Determinism matters: a disputed match must be replayable
 * byte-for-byte from (matchId, roundNo, playerId).
 */
export const shuffleWith = <T>(items: readonly T[], seed: string): T[] => {
  const random = mulberry32(seedOf(seed));
  const out = [...items];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
};

const pick = (pair: { en: string; ar: string } | undefined, locale: Locale): string =>
  pair ? pair[locale] : "";

const resolveEntity = (catalog: EntityCatalog, id: string): string | null => {
  const table = id.startsWith("p_")
    ? catalog.people
    : id.startsWith("c_")
      ? catalog.clubs
      : id.startsWith("n_")
        ? catalog.nations
        : null;
  const found = table?.get(id);
  return found ? found.en : null;
};

export interface RenderContext {
  catalog: EntityCatalog;
  /** Injected so the renderer never depends on the CDN client directly. */
  assetUrl: (assetId: string) => string;
  /** Seed suffix: `${matchId}:${roundNo}:${playerId}` for per-player option shuffling. */
  seed: string;
}

const renderFormatData = (
  doc: QuestionDoc,
  locale: Locale,
  ctx: RenderContext,
): Record<string, unknown> => {
  const data = doc.formatData ?? {};

  switch (doc.format) {
    case "career_path": {
      const clubIds = (data.clubIds as string[] | undefined) ?? [];
      return {
        type: "career_path",
        order: data.order ?? "chronological",
        showYears: data.showYears === true,
        // Club names are resolved from the shared catalog so the Arabic rendering of
        // "Real Madrid" can never drift between two questions.
        clubs: clubIds.map((id) => ({
          id,
          name: ctx.catalog.clubs.get(id)?.[locale] ?? resolveEntity(ctx.catalog, id) ?? id,
        })),
      };
    }

    case "emoji_story":
      return {
        type: "emoji_story",
        // Already bidi-isolated in the bank; the client must NOT re-order it.
        emoji: data.emoji,
        revealMode: data.revealMode ?? "all_at_once",
        emojiIntervalMs: data.emojiIntervalMs ?? 0,
        subject: data.subject,
      };

    case "blur_reveal": {
      const media = doc.media?.[0];
      return {
        type: "blur_reveal",
        revealMs: data.revealMs,
        initialBlurSigma: data.initialBlurSigma,
        finalBlurSigma: data.finalBlurSigma ?? 0,
        curve: data.curve ?? "easeOut",
        image: media
          ? { assetId: media.assetId, url: ctx.assetUrl(media.assetId) }
          : null,
      };
    }

    case "stat_highlow":
      // `values` is deliberately dropped. Sending it here would hand the answer
      // to anyone with a proxy — the whole format would be over before it began.
      return {
        type: "stat_highlow",
        statLabel: pick(data.statLabel as { en: string; ar: string }, locale),
        direction: data.direction,
        unit: pick(data.unit as { en: string; ar: string }, locale),
      };

    default:
      return { type: "mc" };
  }
};

/** The question as one player sees it. Contains no answer key. */
export const renderQuestion = (doc: QuestionDoc, locale: Locale, ctx: RenderContext): QuestionView => {
  const options: RenderedOption[] = shuffleWith(doc.options, `${ctx.seed}:opts`).map((option) => ({
    id: option.id,
    text: pick(option, locale),
  }));

  return {
    questionId: doc.id,
    format: doc.format,
    difficulty: doc.difficulty,
    locale,
    dir: directionOf(locale),
    prompt: pick(doc.prompt, locale),
    options,
    explainer: pick(doc.explainer, locale),
    formatData: renderFormatData(doc, locale, ctx),
    media: (doc.media ?? []).map((m) => ({
      assetId: m.assetId,
      url: ctx.assetUrl(m.assetId),
      alt: "",
    })),
    ...(doc.image_path ? { imagePath: doc.image_path } : {}),
  };
};

/**
 * The reveal view: adds the answer key, per-player deltas and the localized explainer.
 * Only ever built AFTER resolution.
 */
export const renderReveal = (
  doc: QuestionDoc,
  locale: Locale,
  ctx: RenderContext,
  extra: { delta: number; zone: number; correctOptionText: string; scoredGoal?: boolean },
): Record<string, unknown> => ({
  questionId: doc.id,
  correctOptionId: doc.answerOptionId,
  correctOptionText: extra.correctOptionText,
  explainer: pick(doc.explainer, locale),
  delta: extra.delta,
  zone: extra.zone,
  dir: directionOf(locale),
  ...(extra.scoredGoal === undefined ? {} : { scoredGoal: extra.scoredGoal }),
});

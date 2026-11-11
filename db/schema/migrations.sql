-- =============================================================================
--  Grid & Glory — PostgreSQL 16 schema (MVP)
--  Apply with: psql "$DATABASE_URL" -f db/schema/migrations.sql
--
--  Design notes that explain the shape (read docs/02-database-schema.md):
--   * A question is ONE row with both locales. There is no "ar variant" row, so the
--     two players can never be served divergent content for the same question id.
--   * The bilingual document lives in JSONB; the columns that are queried for
--     selection (format, difficulty, region, status) are promoted to real columns,
--     with a CHECK that keeps them in sync with the document.
--   * Matches are append-only. Nothing is ever UPDATEd except the finalise marker.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------- reference --

CREATE TABLE IF NOT EXISTS seasons (
  id          integer PRIMARY KEY,
  name        text        NOT NULL,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  CONSTRAINT season_window CHECK (ends_at > starts_at)
);

-- ------------------------------------------------------------------ players --

CREATE TABLE IF NOT EXISTS players (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name  text        NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 24),
  locale        text        NOT NULL DEFAULT 'en' CHECK (locale IN ('en', 'ar')),
  country_code  char(2),
  region        text        NOT NULL DEFAULT 'EU' CHECK (region IN ('EU', 'MENA', 'NA', 'APAC', 'SA')),
  is_guest      boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- Soft delete: Google Play requires in-app account deletion, but a 30-day purge
  -- window protects against accidental loss and keeps match history referentially sane.
  deleted_at    timestamptz
);

CREATE INDEX IF NOT EXISTS players_region_idx ON players (region) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS player_identities (
  provider    text        NOT NULL CHECK (provider IN ('guest', 'apple', 'google')),
  subject     text        NOT NULL,
  player_id   uuid        NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, subject)
);

CREATE INDEX IF NOT EXISTS player_identities_player_idx ON player_identities (player_id);

CREATE TABLE IF NOT EXISTS player_settings (
  player_id      uuid PRIMARY KEY REFERENCES players (id) ON DELETE CASCADE,
  locale         text    NOT NULL DEFAULT 'en' CHECK (locale IN ('en', 'ar')),
  -- MENA sports UIs overwhelmingly use Western digits in scores/minutes; offer the
  -- choice rather than forcing one, but default to the least surprising.
  numeral_style  text    NOT NULL DEFAULT 'western' CHECK (numeral_style IN ('western', 'arabic_indic')),
  haptics        boolean NOT NULL DEFAULT true,
  reduced_motion boolean NOT NULL DEFAULT false,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS player_ratings (
  player_id         uuid PRIMARY KEY REFERENCES players (id) ON DELETE CASCADE,
  season_id         integer NOT NULL REFERENCES seasons (id),
  rating            integer NOT NULL DEFAULT 1000 CHECK (rating BETWEEN 0 AND 4000),
  -- Glicko-2 fields, carried from day one so the switch is a config change, not a migration.
  rating_deviation  integer NOT NULL DEFAULT 350,
  volatility        numeric(6, 4) NOT NULL DEFAULT 0.0600,
  matches_played    integer NOT NULL DEFAULT 0,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------- questions --

CREATE TABLE IF NOT EXISTS questions (
  id                 text PRIMARY KEY CHECK (id ~ '^q_(mc|career|emoji|blur|stat)_[a-z0-9_]+$'),
  format             text NOT NULL CHECK (format IN ('mc', 'career_path', 'emoji_story', 'blur_reveal', 'stat_highlow')),
  difficulty         smallint NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  region             text NOT NULL CHECK (region IN ('GLOBAL', 'MENA', 'AFRICA', 'EUROPE', 'SOUTH_AMERICA', 'ASIA', 'NORTH_AMERICA')),
  status             text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'in_review', 'published', 'retired')),

  -- The full document from db/schema/question-bank.schema.json. Both locales, always.
  doc                jsonb NOT NULL,

  -- Promoted out of the document because scoring must never parse JSON to grade a round,
  -- and because a wrong answer key is the single most damaging content bug we can ship.
  answer_option_id   text NOT NULL,

  -- sha256 of the normalised document: duplicate detection, and a cheap "has this
  -- question changed since the match was played" check.
  checksum           text NOT NULL,

  version            integer NOT NULL DEFAULT 1,
  author             text,
  reviewed_by        text,
  ar_verified_by     text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),

  -- The promoted columns must agree with the document they shadow.
  CONSTRAINT questions_format_matches_doc   CHECK (doc ->> 'format' = format),
  CONSTRAINT questions_difficulty_matches   CHECK ((doc ->> 'difficulty')::smallint = difficulty),
  CONSTRAINT questions_region_matches       CHECK (doc ->> 'region' = region),
  CONSTRAINT questions_answer_matches       CHECK (doc ->> 'answerOptionId' = answer_option_id),
  -- Publishing requires Arabic sign-off. Enforced in the database, not just the validator,
  -- because the fairness guarantee is worthless if a script can bypass it.
  CONSTRAINT questions_publish_needs_review CHECK (
    status <> 'published' OR (reviewed_by IS NOT NULL AND ar_verified_by IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS questions_checksum_uidx ON questions (checksum);
CREATE INDEX IF NOT EXISTS questions_pool_idx ON questions (status, region, difficulty, format);
CREATE INDEX IF NOT EXISTS questions_tags_idx ON questions USING gin ((doc -> 'tags'));
CREATE INDEX IF NOT EXISTS questions_competitions_idx ON questions USING gin ((doc -> 'competitions'));

COMMENT ON COLUMN questions.doc IS
  'Bilingual question document. Both locales in one row: divergence is structurally impossible.';

CREATE TABLE IF NOT EXISTS question_versions (
  question_id  text    NOT NULL REFERENCES questions (id) ON DELETE CASCADE,
  version      integer NOT NULL,
  doc          jsonb   NOT NULL,
  changed_by   text,
  changed_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (question_id, version)
);

-- Anti-repetition. Retention 30 days, purged nightly; the PK makes the serve-cap a
-- cheap existence check rather than a scan over match history.
CREATE TABLE IF NOT EXISTS question_seen (
  player_id    uuid NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  question_id  text NOT NULL REFERENCES questions (id) ON DELETE CASCADE,
  served_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (player_id, question_id)
);

CREATE INDEX IF NOT EXISTS question_seen_purge_idx ON question_seen (served_at);

-- ------------------------------------------------------------------ matches --

CREATE TABLE IF NOT EXISTS matches (
  id             text PRIMARY KEY,
  season_id      integer REFERENCES seasons (id),
  region_pair    text,
  cross_region   boolean NOT NULL DEFAULT false,
  started_at     timestamptz NOT NULL,
  ended_at       timestamptz,
  -- Single-writer finalisation guard: a duplicate result write is a no-op, not a double rating.
  finalised_at   timestamptz,
  state          text NOT NULL DEFAULT 'live' CHECK (state IN ('live', 'final', 'void')),
  winner_id      uuid REFERENCES players (id),
  decided_by     text CHECK (decided_by IN ('goals', 'zone', 'correct', 'time', 'draw', 'forfeit', 'void')),
  engine_version text NOT NULL DEFAULT '1.0.0',
  CONSTRAINT match_ended_when_final CHECK (state <> 'final' OR ended_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS matches_started_idx ON matches (started_at DESC);
CREATE INDEX IF NOT EXISTS matches_unfinalised_idx ON matches (finalised_at) WHERE finalised_at IS NULL;

CREATE TABLE IF NOT EXISTS match_players (
  match_id       text NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  player_id      uuid NOT NULL REFERENCES players (id),
  locale         text NOT NULL CHECK (locale IN ('en', 'ar')),
  rating_before  integer,
  rating_delta   integer,
  goals          smallint NOT NULL DEFAULT 0,
  zone           smallint NOT NULL DEFAULT 0 CHECK (zone BETWEEN 0 AND 5),
  correct        smallint NOT NULL DEFAULT 0,
  wrong          smallint NOT NULL DEFAULT 0,
  no_answer      smallint NOT NULL DEFAULT 0,
  correct_time_ms integer NOT NULL DEFAULT 0,
  outcome        text CHECK (outcome IN ('win', 'loss', 'draw')),
  PRIMARY KEY (match_id, player_id)
);

CREATE INDEX IF NOT EXISTS match_players_player_idx ON match_players (player_id, match_id);

-- One row per question served. question_version is recorded because a disputed match
-- must be replayable against the exact text the players saw, not today's text.
CREATE TABLE IF NOT EXISTS match_rounds (
  match_id         text    NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  half             smallint NOT NULL CHECK (half IN (1, 2)),
  round_no         smallint NOT NULL,
  kind             text    NOT NULL CHECK (kind IN ('normal', 'shooting')),
  question_id      text    NOT NULL REFERENCES questions (id),
  question_version integer NOT NULL,
  window_opened_at timestamptz NOT NULL,
  window_closed_at timestamptz,
  PRIMARY KEY (match_id, half, round_no, kind)
);

CREATE TABLE IF NOT EXISTS match_answers (
  match_id    text    NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  half        smallint NOT NULL,
  round_no    smallint NOT NULL,
  kind        text    NOT NULL DEFAULT 'normal',
  player_id   uuid    NOT NULL REFERENCES players (id),
  option_id   text,
  received_at timestamptz NOT NULL,
  elapsed_ms  integer,
  is_correct  boolean,
  late        boolean NOT NULL DEFAULT false,
  PRIMARY KEY (match_id, half, round_no, kind, player_id)
);

-- ------------------------------------------------------------------- ops ----

CREATE TABLE IF NOT EXISTS reports (
  id          bigserial PRIMARY KEY,
  reporter_id uuid REFERENCES players (id) ON DELETE SET NULL,
  subject_id  uuid REFERENCES players (id) ON DELETE SET NULL,
  match_id    text REFERENCES matches (id) ON DELETE SET NULL,
  reason      text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE TABLE IF NOT EXISTS feature_flags (
  key        text PRIMARY KEY,
  enabled    boolean NOT NULL DEFAULT false,
  payload    jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Partitioned by month: the table that grows fastest and is only ever read in ranges.
CREATE TABLE IF NOT EXISTS analytics_events (
  occurred_at timestamptz NOT NULL,
  player_id   uuid,
  name        text NOT NULL,
  props       jsonb NOT NULL DEFAULT '{}'::jsonb
) PARTITION BY RANGE (occurred_at);

CREATE TABLE IF NOT EXISTS analytics_events_default PARTITION OF analytics_events DEFAULT;

COMMIT;

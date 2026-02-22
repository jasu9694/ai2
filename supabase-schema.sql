-- ══════════════════════════════════════════════════════════
-- LearnCraft — Supabase PostgreSQL Schema
-- Run this in your Supabase SQL Editor (supabase.com/dashboard)
-- ══════════════════════════════════════════════════════════

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────
-- 1. USER PROFILES
--    Synced from Clerk on first login
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  clerk_user_id TEXT UNIQUE NOT NULL,
  email         TEXT,
  first_name    TEXT,
  last_name     TEXT,
  avatar_url    TEXT,
  plan          TEXT DEFAULT 'free' CHECK (plan IN ('free','pro','teams')),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 2. USER PROGRESS (XP + streaks)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_progress (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id       TEXT UNIQUE NOT NULL REFERENCES public.user_profiles(clerk_user_id) ON DELETE CASCADE,
  xp            INTEGER DEFAULT 0,
  streak_days   INTEGER DEFAULT 0,
  last_active   DATE DEFAULT CURRENT_DATE,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 3. LESSON COMPLETIONS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.lesson_completions (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES public.user_profiles(clerk_user_id) ON DELETE CASCADE,
  course_id     TEXT NOT NULL,
  lesson_id     TEXT NOT NULL,
  completed_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, lesson_id)
);

-- ─────────────────────────────────────────────
-- 4. ASSESSMENT RESULTS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.assessment_results (
  id               UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id          TEXT NOT NULL REFERENCES public.user_profiles(clerk_user_id) ON DELETE CASCADE,
  assessment_id    TEXT NOT NULL,
  score            INTEGER NOT NULL,
  total_questions  INTEGER NOT NULL,
  passed           BOOLEAN NOT NULL,
  time_taken_secs  INTEGER,
  completed_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_assessment_user ON public.assessment_results(user_id);

-- ─────────────────────────────────────────────
-- 5. BOOKMARKED INTERVIEW QUESTIONS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bookmarked_questions (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES public.user_profiles(clerk_user_id) ON DELETE CASCADE,
  category      TEXT NOT NULL,
  question_text TEXT NOT NULL,
  bookmarked_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, question_text)
);

-- ─────────────────────────────────────────────
-- 6. AI INTERVIEW SESSIONS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.interview_sessions (
  id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES public.user_profiles(clerk_user_id) ON DELETE CASCADE,
  role          TEXT,
  difficulty    TEXT,
  questions_asked INTEGER DEFAULT 0,
  xp_earned     INTEGER DEFAULT 0,
  started_at    TIMESTAMPTZ DEFAULT NOW(),
  ended_at      TIMESTAMPTZ
);

-- ══════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) — CRITICAL for production
-- Users can only read/write their OWN data
-- ══════════════════════════════════════════════
ALTER TABLE public.user_profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_progress       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_completions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_results  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookmarked_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_sessions  ENABLE ROW LEVEL SECURITY;

-- ─ user_profiles policies ─────────────────────
CREATE POLICY "Users can view their own profile"
  ON public.user_profiles FOR SELECT
  USING (clerk_user_id = current_setting('request.jwt.claims', true)::json->>'sub');

CREATE POLICY "Users can update their own profile"
  ON public.user_profiles FOR UPDATE
  USING (clerk_user_id = current_setting('request.jwt.claims', true)::json->>'sub');

CREATE POLICY "Users can insert their own profile"
  ON public.user_profiles FOR INSERT
  WITH CHECK (clerk_user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ─ user_progress policies ─────────────────────
CREATE POLICY "Users manage own progress"
  ON public.user_progress FOR ALL
  USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub')
  WITH CHECK (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ─ lesson_completions policies ────────────────
CREATE POLICY "Users manage own lesson completions"
  ON public.lesson_completions FOR ALL
  USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub')
  WITH CHECK (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ─ assessment_results policies ────────────────
CREATE POLICY "Users manage own assessment results"
  ON public.assessment_results FOR ALL
  USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub')
  WITH CHECK (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ─ bookmarked_questions policies ──────────────
CREATE POLICY "Users manage own bookmarks"
  ON public.bookmarked_questions FOR ALL
  USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub')
  WITH CHECK (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ─ interview_sessions policies ────────────────
CREATE POLICY "Users manage own interview sessions"
  ON public.interview_sessions FOR ALL
  USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub')
  WITH CHECK (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ══════════════════════════════════════════════
-- PERFORMANCE INDEXES
-- ══════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_lesson_user    ON public.lesson_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_lesson_course  ON public.lesson_completions(course_id);
CREATE INDEX IF NOT EXISTS idx_bookmark_user  ON public.bookmarked_questions(user_id);
CREATE INDEX IF NOT EXISTS idx_interview_user ON public.interview_sessions(user_id);

-- ══════════════════════════════════════════════
-- AUTO-UPDATE updated_at TRIGGER
-- ══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_user_progress_updated_at
  BEFORE UPDATE ON public.user_progress
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ══════════════════════════════════════════════
-- Done! Your schema is ready.
-- Handles 100 to 100,000+ users with proper indexing.
-- ══════════════════════════════════════════════

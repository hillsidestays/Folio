-- ════════════════════════════════════════════════════════
--  FOLIO — Supabase Migration v2
--  Run once in Supabase SQL Editor (project: derybgfiwxeebwmcobht)
--
--  Open signup model: anyone who lands on the URL can create an
--  account and is auto-joined to the Hillside Stays workspace as
--  operator. Dylan (smithdj789@gmail.com) gets admin automatically.
-- ════════════════════════════════════════════════════════

-- ── Workspaces ──────────────────────────────────────────
CREATE TABLE workspaces (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ── Profiles (extends auth.users, same UUID) ────────────
CREATE TABLE profiles (
  id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id uuid REFERENCES workspaces(id),
  name         text NOT NULL DEFAULT '',
  role         text NOT NULL DEFAULT 'operator' CHECK (role IN ('admin','operator')),
  avatar_color text DEFAULT '#4A7CC2',
  created_at   timestamptz DEFAULT now()
);

-- ── Properties ───────────────────────────────────────────
CREATE TABLE properties (
  id           text PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  name         text,
  city         text,
  type         text,
  bedrooms     text,
  bathrooms    text,
  guests       text,
  airbnb       text,
  direct       text,
  notes        text,
  occupancy    numeric,
  adr          numeric,
  rating       numeric,
  status       text DEFAULT 'active',
  emoji        text DEFAULT '🏡',
  hosp_id      text,
  created_at   timestamptz DEFAULT now()
);

-- ── Tasks ────────────────────────────────────────────────
CREATE TABLE tasks (
  id           text PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  property_id  text,
  title        text NOT NULL,
  category     text,
  due          date,
  priority     text DEFAULT 'med' CHECK (priority IN ('high','med','low')),
  done         boolean DEFAULT false,
  notes        text,
  assignee     text CHECK (assignee IN ('dylan','susanna','tommy','')),
  created_at   timestamptz DEFAULT now()
);

-- ── KB Entries ───────────────────────────────────────────
CREATE TABLE kb_entries (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  property_id  text,
  category     text NOT NULL DEFAULT 'general'
               CHECK (category IN ('sop','house_rules','vendor_info','emergency','general')),
  title        text NOT NULL,
  content      text,
  file_url     text,
  file_name    text,
  created_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

-- ── RLS: Helper ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_workspace_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT workspace_id FROM profiles WHERE id = auth.uid()
$$;

-- ── RLS: Enable ─────────────────────────────────────────
ALTER TABLE workspaces  ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles    ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties  ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks       ENABLE ROW LEVEL SECURITY;
ALTER TABLE kb_entries  ENABLE ROW LEVEL SECURITY;

-- workspaces
CREATE POLICY "view own workspace" ON workspaces
  FOR SELECT USING (id = get_workspace_id());

-- profiles: see all teammates, update own
CREATE POLICY "view workspace profiles" ON profiles
  FOR SELECT USING (workspace_id = get_workspace_id());
CREATE POLICY "insert own profile" ON profiles
  FOR INSERT WITH CHECK (id = auth.uid());
CREATE POLICY "update own profile" ON profiles
  FOR UPDATE USING (id = auth.uid());

-- properties / tasks / kb_entries: full CRUD for workspace members
CREATE POLICY "workspace members" ON properties
  FOR ALL USING (workspace_id = get_workspace_id())
  WITH CHECK (workspace_id = get_workspace_id());

CREATE POLICY "workspace members" ON tasks
  FOR ALL USING (workspace_id = get_workspace_id())
  WITH CHECK (workspace_id = get_workspace_id());

CREATE POLICY "workspace members" ON kb_entries
  FOR ALL USING (workspace_id = get_workspace_id())
  WITH CHECK (workspace_id = get_workspace_id());

-- ── Trigger: auto-create profile on any signup ──────────
--  - Dylan (smithdj789@gmail.com) → admin
--  - Everyone else → operator
--  - All users land in the same Hillside Stays workspace
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_workspace_id uuid := 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  v_role         text;
  v_name         text;
BEGIN
  IF lower(NEW.email) = 'smithdj789@gmail.com' THEN
    v_role := 'admin';
  ELSE
    v_role := 'operator';
  END IF;

  v_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'name',
    split_part(NEW.email, '@', 1)
  );

  INSERT INTO profiles (id, workspace_id, name, role)
  VALUES (NEW.id, v_workspace_id, v_name, v_role)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── Seed: Hillside Stays workspace ──────────────────────
INSERT INTO workspaces (id, name)
VALUES ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Hillside Stays LLC');

-- ── Add more admins later ───────────────────────────────
-- UPDATE profiles SET role = 'admin' WHERE id = '<user-uuid>';

-- ════════════════════════════════════════════════════════
--  FOLIO — Supabase Migration
--  Run this once in the Supabase SQL Editor (derybgfiwxeebwmcobht)
--  Order matters: workspaces → profiles → workspace_invites → properties → tasks → kb_entries
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

-- ── Workspace Invites (pre-approved emails) ─────────────
CREATE TABLE workspace_invites (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  email        text NOT NULL,
  role         text NOT NULL DEFAULT 'operator' CHECK (role IN ('admin','operator')),
  created_at   timestamptz DEFAULT now(),
  UNIQUE(email)
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

-- ── RLS: Helper function ────────────────────────────────
CREATE OR REPLACE FUNCTION get_workspace_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT workspace_id FROM profiles WHERE id = auth.uid()
$$;

-- ── RLS: Enable + policies ──────────────────────────────
ALTER TABLE workspaces        ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE kb_entries        ENABLE ROW LEVEL SECURITY;

-- workspaces: members see their own
CREATE POLICY "members view workspace" ON workspaces
  FOR SELECT USING (id = get_workspace_id());

-- profiles: see all colleagues in same workspace
CREATE POLICY "view workspace profiles" ON profiles
  FOR SELECT USING (workspace_id = get_workspace_id());
CREATE POLICY "update own profile" ON profiles
  FOR UPDATE USING (id = auth.uid());
CREATE POLICY "insert own profile" ON profiles
  FOR INSERT WITH CHECK (id = auth.uid());

-- workspace_invites: admins can manage, members can read own workspace's invites
CREATE POLICY "members view invites" ON workspace_invites
  FOR SELECT USING (workspace_id = get_workspace_id());
CREATE POLICY "admins insert invites" ON workspace_invites
  FOR INSERT WITH CHECK (
    workspace_id = get_workspace_id() AND
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );
CREATE POLICY "admins delete invites" ON workspace_invites
  FOR DELETE USING (
    workspace_id = get_workspace_id() AND
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

-- properties, tasks, kb_entries: full CRUD for workspace members
CREATE POLICY "workspace members" ON properties
  FOR ALL USING (workspace_id = get_workspace_id())
  WITH CHECK (workspace_id = get_workspace_id());

CREATE POLICY "workspace members" ON tasks
  FOR ALL USING (workspace_id = get_workspace_id())
  WITH CHECK (workspace_id = get_workspace_id());

CREATE POLICY "workspace members" ON kb_entries
  FOR ALL USING (workspace_id = get_workspace_id())
  WITH CHECK (workspace_id = get_workspace_id());

-- ── Trigger: auto-create profile on signup ──────────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_invite workspace_invites%ROWTYPE;
  v_name   text;
BEGIN
  SELECT * INTO v_invite
  FROM workspace_invites
  WHERE lower(email) = lower(NEW.email)
  LIMIT 1;

  IF v_invite IS NOT NULL THEN
    v_name := COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      split_part(NEW.email, '@', 1)
    );
    INSERT INTO profiles (id, workspace_id, name, role)
    VALUES (NEW.id, v_invite.workspace_id, v_name, v_invite.role)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── Seed: Workspace + Invites ────────────────────────────
-- IMPORTANT: replace Susanna + Tommy emails with real ones before running
INSERT INTO workspaces (id, name)
VALUES ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'Hillside Stays LLC');

INSERT INTO workspace_invites (workspace_id, email, role) VALUES
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'smithdj789@gmail.com',     'admin'),
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'susanna@hillsidestays.com', 'operator'),  -- REPLACE
  ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'tommy@hillsidestays.com',   'operator');  -- REPLACE

-- ── Add a team member later (run as needed) ─────────────
-- INSERT INTO workspace_invites (workspace_id, email, role) VALUES
--   ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'newemail@example.com', 'operator');

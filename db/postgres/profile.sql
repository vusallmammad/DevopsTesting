CREATE TABLE IF NOT EXISTS player_profiles (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    level INTEGER NOT NULL DEFAULT 1,
    region TEXT NOT NULL,
    bio TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS profile_settings (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    notifications_enabled BOOLEAN NOT NULL DEFAULT true,
    language TEXT NOT NULL DEFAULT 'en',
    theme TEXT NOT NULL DEFAULT 'system'
);

CREATE TABLE IF NOT EXISTS achievements (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, code)
);

INSERT INTO player_profiles (id, user_id, display_name, level, region, bio) VALUES
    ('profile-001', 'usr-001', 'Nova', 18, 'EU', 'Likes arena games.'),
    ('profile-002', 'usr-002', 'Vector', 31, 'NA', 'Tournament regular.')
ON CONFLICT DO NOTHING;

INSERT INTO profile_settings (id, profile_id, notifications_enabled, language, theme) VALUES
    ('settings-001', 'profile-001', true, 'en', 'dark'),
    ('settings-002', 'profile-002', false, 'en', 'system')
ON CONFLICT DO NOTHING;

INSERT INTO achievements (id, profile_id, code) VALUES
    ('ach-001', 'profile-001', 'FIRST_WIN'),
    ('ach-002', 'profile-002', 'TEN_WINS')
ON CONFLICT DO NOTHING;

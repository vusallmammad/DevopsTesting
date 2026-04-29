CREATE TABLE IF NOT EXISTS games (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    genre TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_sessions (
    id TEXT PRIMARY KEY,
    game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    status TEXT NOT NULL,
    max_players INTEGER NOT NULL,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS leaderboard_scores (
    id TEXT PRIMARY KEY,
    game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    profile_id TEXT NOT NULL,
    score INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO games (id, title, genre, status) VALUES
    ('game-001', 'Arena Rush', 'Action', 'Published'),
    ('game-002', 'Puzzle Forge', 'Puzzle', 'Beta')
ON CONFLICT DO NOTHING;

INSERT INTO game_sessions (id, game_id, status, max_players) VALUES
    ('session-001', 'game-001', 'Open', 8)
ON CONFLICT DO NOTHING;

INSERT INTO leaderboard_scores (id, game_id, profile_id, score) VALUES
    ('leaderboard-001', 'game-001', 'profile-001', 12400)
ON CONFLICT DO NOTHING;

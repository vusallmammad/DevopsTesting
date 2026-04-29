CREATE TABLE IF NOT EXISTS matchmaking_queues (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL,
    game_id TEXT NOT NULL,
    rating INTEGER NOT NULL,
    status TEXT NOT NULL,
    queued_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS match_requests (
    id TEXT PRIMARY KEY,
    queue_id TEXT NOT NULL REFERENCES matchmaking_queues(id) ON DELETE CASCADE,
    profile_id TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS matches (
    id TEXT PRIMARY KEY,
    game_id TEXT NOT NULL,
    blue_team_id TEXT NOT NULL,
    red_team_id TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO matchmaking_queues (id, profile_id, game_id, rating, status) VALUES
    ('queue-001', 'profile-001', 'game-001', 1510, 'Searching')
ON CONFLICT DO NOTHING;

INSERT INTO match_requests (id, queue_id, profile_id, status) VALUES
    ('request-001', 'queue-001', 'profile-001', 'Queued')
ON CONFLICT DO NOTHING;

INSERT INTO matches (id, game_id, blue_team_id, red_team_id, status) VALUES
    ('match-001', 'game-001', 'team-001', 'team-002', 'Ready')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS tournaments (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    game_id TEXT NOT NULL,
    status TEXT NOT NULL,
    max_teams INTEGER NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS tournament_registrations (
    id TEXT PRIMARY KEY,
    tournament_id TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    team_id TEXT NOT NULL,
    status TEXT NOT NULL,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tournament_id, team_id)
);

CREATE TABLE IF NOT EXISTS tournament_brackets (
    id TEXT PRIMARY KEY,
    tournament_id TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    round INTEGER NOT NULL,
    match_number INTEGER NOT NULL,
    blue_team_id TEXT,
    red_team_id TEXT,
    status TEXT NOT NULL
);

INSERT INTO tournaments (id, name, game_id, status, max_teams, starts_at) VALUES
    ('tournament-001', 'Spring Cup', 'game-001', 'RegistrationOpen', 16, now() + interval '14 days')
ON CONFLICT DO NOTHING;

INSERT INTO tournament_registrations (id, tournament_id, team_id, status) VALUES
    ('registration-001', 'tournament-001', 'team-001', 'Registered')
ON CONFLICT DO NOTHING;

INSERT INTO tournament_brackets (id, tournament_id, round, match_number, blue_team_id, red_team_id, status) VALUES
    ('bracket-001', 'tournament-001', 1, 1, 'team-001', 'team-002', 'Pending')
ON CONFLICT DO NOTHING;

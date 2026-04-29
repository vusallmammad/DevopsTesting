CREATE TABLE IF NOT EXISTS teams (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    owner_user_id TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS team_members (
    id TEXT PRIMARY KEY,
    team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (team_id, user_id)
);

CREATE TABLE IF NOT EXISTS team_invitations (
    id TEXT PRIMARY KEY,
    team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    status TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

INSERT INTO teams (id, name, owner_user_id, status) VALUES
    ('team-001', 'Northwind', 'usr-001', 'Active'),
    ('team-002', 'Contoso', 'usr-002', 'Active')
ON CONFLICT DO NOTHING;

INSERT INTO team_members (id, team_id, user_id, role) VALUES
    ('member-001', 'team-001', 'usr-001', 'Captain'),
    ('member-002', 'team-002', 'usr-002', 'Captain')
ON CONFLICT DO NOTHING;

INSERT INTO team_invitations (id, team_id, email, status, expires_at) VALUES
    ('invite-001', 'team-001', 'new-player@example.test', 'Pending', now() + interval '7 days')
ON CONFLICT DO NOTHING;

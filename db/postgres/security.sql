CREATE TABLE IF NOT EXISTS app_users (
    id TEXT PRIMARY KEY,
    user_name TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS audit_events (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES app_users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app_users (id, user_name, email, password_hash, status) VALUES
    ('usr-001', 'demo', 'demo@example.test', 'practice-hash', 'Active'),
    ('usr-002', 'captain', 'captain@example.test', 'practice-hash', 'Locked')
ON CONFLICT DO NOTHING;

INSERT INTO roles (id, name) VALUES
    ('role-admin', 'Admin'),
    ('role-player', 'Player')
ON CONFLICT DO NOTHING;

INSERT INTO user_roles (user_id, role_id) VALUES
    ('usr-001', 'role-admin'),
    ('usr-001', 'role-player'),
    ('usr-002', 'role-player')
ON CONFLICT DO NOTHING;

INSERT INTO audit_events (id, user_id, action, metadata) VALUES
    ('audit-001', 'usr-001', 'LoginSucceeded', '{"ip":"127.0.0.1"}')
ON CONFLICT DO NOTHING;

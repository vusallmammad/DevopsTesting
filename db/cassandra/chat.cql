CREATE KEYSPACE IF NOT EXISTS game_chat
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

USE game_chat;

CREATE TABLE IF NOT EXISTS chat_rooms (
    room_id text PRIMARY KEY,
    room_type text,
    title text,
    created_at timestamp
);

CREATE TABLE IF NOT EXISTS messages_by_room (
    room_id text,
    sent_at timestamp,
    message_id uuid,
    sender_user_id text,
    body text,
    PRIMARY KEY ((room_id), sent_at, message_id)
) WITH CLUSTERING ORDER BY (sent_at DESC, message_id DESC);

INSERT INTO chat_rooms (room_id, room_type, title, created_at)
VALUES ('room-001', 'team', 'Northwind Team Chat', '2026-04-20T09:00:00Z');

INSERT INTO messages_by_room (room_id, sent_at, message_id, sender_user_id, body)
VALUES ('room-001', '2026-04-20T09:05:00Z', 11111111-1111-1111-1111-111111111111, 'usr-001', 'Ready for practice.');

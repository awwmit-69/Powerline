CREATE TABLE IF NOT EXISTS call_intents (token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), number_id TEXT NOT NULL REFERENCES numbers(id), remote TEXT NOT NULL, expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS calls (sid TEXT PRIMARY KEY, number_id TEXT NOT NULL REFERENCES numbers(id), user_id TEXT REFERENCES users(id), remote TEXT NOT NULL, direction TEXT NOT NULL, status TEXT NOT NULL, duration INTEGER NOT NULL DEFAULT 0, ring_targets INTEGER NOT NULL DEFAULT 1, intent_hash TEXT, created_at INTEGER NOT NULL DEFAULT (unixepoch()), updated_at INTEGER NOT NULL DEFAULT (unixepoch()));
CREATE INDEX IF NOT EXISTS calls_number ON calls(number_id,created_at);
CREATE TABLE IF NOT EXISTS call_events (sid TEXT PRIMARY KEY, parent_sid TEXT NOT NULL, status TEXT NOT NULL, sequence INTEGER NOT NULL, duration INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS voice_dnc (remote TEXT PRIMARY KEY);

-- Captures one row per download signup from the website.
CREATE TABLE IF NOT EXISTS signups (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  email       TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  user_agent  TEXT,
  referrer    TEXT,
  country     TEXT,
  city        TEXT,
  region      TEXT,
  source      TEXT
);

CREATE INDEX IF NOT EXISTS idx_signups_email ON signups (email);
CREATE INDEX IF NOT EXISTS idx_signups_created_at ON signups (created_at);

#!/bin/bash
# Insert a FreshBooks time entry into the local SQLite database.
#
# Usage:
#   insert-freshbooks.sh <db_path> --date YYYY-MM-DD --project <name> --hours <hours> --description <desc> [--entry-id <fb_id>]

set -e

DB_PATH="$1"
shift || true

if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
  echo "Usage: insert-freshbooks.sh <db_path> --date YYYY-MM-DD --project <name> --hours <hours> --description <desc> [--entry-id <fb_id>]" >&2
  exit 1
fi

DATE=""
PROJECT=""
HOURS=""
DESCRIPTION=""
ENTRY_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --date)        DATE="$2";        shift 2 ;;
    --project)     PROJECT="$2";     shift 2 ;;
    --hours)       HOURS="$2";       shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --entry-id)    ENTRY_ID="$2";    shift 2 ;;
    *)             echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$DATE" ] || [ -z "$PROJECT" ] || [ -z "$HOURS" ] || [ -z "$DESCRIPTION" ]; then
  echo "Error: --date, --project, --hours, and --description are all required" >&2
  exit 1
fi

sqlite3 "$DB_PATH" <<SQL
CREATE TABLE IF NOT EXISTS freshbooks_time_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  project TEXT NOT NULL,
  hours REAL NOT NULL,
  description TEXT,
  freshbooks_entry_id TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_fb_entries_unique
  ON freshbooks_time_entries(date, project, description);
INSERT OR REPLACE INTO freshbooks_time_entries (date, project, hours, description, freshbooks_entry_id)
VALUES ('$DATE', '$PROJECT', $HOURS, '$DESCRIPTION', '$ENTRY_ID');
SQL

echo "Inserted: $DATE | $PROJECT | $HOURS | $DESCRIPTION | entry_id=$ENTRY_ID"

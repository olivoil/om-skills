#!/bin/bash
# Query FreshBooks time entries from SQLite.
#
# Usage:
#   query-freshbooks.sh <db_path> [--from YYYY-MM-DD] [--to YYYY-MM-DD]
#
# Output: TSV with columns: date, project, description, hours

set -e

DB_PATH="$1"
shift || true

if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
  echo "Usage: query-freshbooks.sh <db_path> [--from YYYY-MM-DD] [--to YYYY-MM-DD]" >&2
  exit 1
fi

FROM=""
TO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --to)   TO="$2";   shift 2 ;;
    *)      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

WHERE=""
if [ -n "$FROM" ] && [ -n "$TO" ]; then
  WHERE="WHERE date BETWEEN '$FROM' AND '$TO'"
elif [ -n "$FROM" ]; then
  WHERE="WHERE date >= '$FROM'"
elif [ -n "$TO" ]; then
  WHERE="WHERE date <= '$TO'"
fi

sqlite3 -separator $'\t' "$DB_PATH" <<SQL
SELECT date, project, description, hours
FROM freshbooks_time_entries
$WHERE
ORDER BY date, project, description;
SQL

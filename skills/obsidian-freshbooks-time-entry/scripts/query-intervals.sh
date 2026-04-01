#!/bin/bash
# Query Intervals time entries from SQLite, grouped by date + project.
#
# Usage:
#   query-intervals.sh <db_path> [--from YYYY-MM-DD] [--to YYYY-MM-DD]
#
# Output: TSV with columns: date, project, hours

set -e

DB_PATH="$1"
shift || true

if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
  echo "Usage: query-intervals.sh <db_path> [--from YYYY-MM-DD] [--to YYYY-MM-DD]" >&2
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
SELECT date, project, SUM(hours) as hours
FROM intervals_time_entries
$WHERE
GROUP BY date, project
ORDER BY date, project;
SQL

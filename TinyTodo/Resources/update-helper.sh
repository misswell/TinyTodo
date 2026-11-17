#!/bin/sh
# TinyTodo update helper: waits for the old process to exit, swaps the verified bundle in
# /Applications, removes quarantine and relaunches. The bundle being replaced is this process's
# parent, so all work happens here, outside it.
set -u

PID="$1"
SRC="$2"
DST="$3"
LOG="$4"

mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] update start pid=$PID src=$SRC dst=$DST"

i=0
while kill -0 "$PID" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 600 ]; then
    echo "timeout waiting for app to quit"
    exit 1
  fi
  sleep 0.2
done

BACKUP="${DST}.backup-$(date +%s)"
rm -rf "$BACKUP"
if ! mv "$DST" "$BACKUP"; then
  echo "cannot move destination out of the way"
  exit 1
fi

if /usr/bin/ditto "$SRC" "$DST"; then
  /usr/bin/xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true
  rm -rf "$BACKUP"
  echo "swapped in $DST"
else
  echo "ditto failed; restoring previous bundle"
  rm -rf "$DST"
  mv "$BACKUP" "$DST"
  "$DST/Contents/MacOS/TinyTodo" >/dev/null 2>&1 &
  exit 1
fi

rm -rf "$(dirname "$SRC")"
"$DST/Contents/MacOS/TinyTodo" >/dev/null 2>&1 &
echo "relaunched"

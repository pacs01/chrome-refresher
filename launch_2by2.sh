#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

# Usage:
#   ./launch_2by2.sh <TARGET_URL> <TARGET_DATE> [TARGET_MS_PRE] [TARGET_MS_POST] [SCREEN_RESOLUTION]
#
# Example:
#   ./launch_2by2.sh "https://currentmillis.com/" "2025-11-17 20:00:00.000 CET" "600000,15000" "0,010,050,200" "2560x1440"
#
# Example TARGET_MS_PRE:
#   sync / debug reload at -600'000ms (T-10min)
#   session warmup reload at -15'000ms (T-15s)

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <TARGET_URL> <TARGET_DATE> [TARGET_MS_PRE] [TARGET_MS_POST] [SCREEN_RESOLUTION]"
  exit 1
fi

# ---- input value mapping and configuration ----

TARGET_URL="$1" # test with https://currentmillis.com/

TARGET_DATE="$2"
TARGET_DATE_MS=$(date --date="$TARGET_DATE" +%s%3N)

TARGET_MS_PRE="${3:-600000,15000}"
IFS=',' read -r -a PRE_ARRAY <<< "$TARGET_MS_PRE"
if (( ${#PRE_ARRAY[@]} != 2 )); then
  echo "Expected exactly 2 comma-separated values for TARGET_MS_PRE, got ${#PRE_ARRAY[@]}: '$TARGET_MS_PRE'" >&2
  exit 1
fi
PRE1="${PRE_ARRAY[0]}"
PRE2="${PRE_ARRAY[1]}"

TARGET_MS_POST="${4:-0,010,050,200}"
IFS=',' read -r -a POST_ARRAY <<< "$TARGET_MS_POST"
if (( ${#POST_ARRAY[@]} != 4 )); then
  echo "Expected exactly 4 comma-separated values for TARGET_MS_POST, got ${#POST_ARRAY[@]}: '$TARGET_MS_POST'" >&2
  exit 1
fi
MS1="${POST_ARRAY[0]}"
MS2="${POST_ARRAY[1]}"
MS3="${POST_ARRAY[2]}"
MS4="${POST_ARRAY[3]}"

SCREEN_RESOLUTION="${5:-2560x1440}"
IFS='x' read -r -a SCREEN_ARRAY <<< "$SCREEN_RESOLUTION"
if (( ${#SCREEN_ARRAY[@]} != 2 )); then
  echo "SCREEN_RESOLUTION must be in the following format: '2560x1440', got '$SCREEN_RESOLUTION'" >&2
  exit 1
fi
SCREEN_WIDTH="${SCREEN_ARRAY[0]}"
SCREEN_HEIGHT="${SCREEN_ARRAY[1]}"

# ---- timestamp calculation ----

PTS1=$((TARGET_DATE_MS - PRE1))
PTS2=$((TARGET_DATE_MS - PRE2))
TS1=$((TARGET_DATE_MS + MS1))
TS2=$((TARGET_DATE_MS + MS2))
TS3=$((TARGET_DATE_MS + MS3))
TS4=$((TARGET_DATE_MS + MS4))

# ---- window size and position ----

HW=$((SCREEN_WIDTH / 2))
HH=$((SCREEN_HEIGHT / 2))

# ---- launch ----

# ensure logs directory exists
mkdir -p logs

./chrome_reload_at_ms.sh "$TARGET_URL" "${PTS1},${PTS2},${TS1}" 9222 0     0     "$HW" "$HH" > logs/9222.log 2>&1 &
./chrome_reload_at_ms.sh "$TARGET_URL" "${PTS1},${PTS2},${TS2}" 9223 "$HW" 0     "$HW" "$HH" > logs/9223.log 2>&1 &
./chrome_reload_at_ms.sh "$TARGET_URL" "${PTS1},${PTS2},${TS3}" 9224 0     "$HH" "$HW" "$HH" > logs/9224.log 2>&1 &
./chrome_reload_at_ms.sh "$TARGET_URL" "${PTS1},${PTS2},${TS4}" 9225 "$HW" "$HH" "$HW" "$HH" > logs/9225.log 2>&1 &

# ---- print logs ----
sleep 3
xfce4-terminal --title="Chrome Refresher Logs" \
  --working-directory="$PWD" \
  -e "bash -lc 'tail -F logs/*.log; exec bash'" &

#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

# Usage:
#   ./chrome_reload_at_ms.sh <TARGET_URL> <TARGET_MS_CSV> <DEBUG_PORT> [POS_X POS_Y WIDTH HEIGHT] [PROFILE_DIR]"
#
# Example (single reload):
#   ./chrome_reload_at_ms.sh "https://currentmillis.com/" 1768096800000 9222 0 0 960 540
#
# Example (multiple reloads, comma-separated):
#   ./chrome_reload_at_ms.sh "https://currentmillis.com/" 1768096800000,1768096800200,1768096800400 9222 0 0 960 540
#
# Timestamps are ms since epoch (date +%s%3N).

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <TARGET_URL> <TARGET_MS_CSV> <DEBUG_PORT> [POS_X POS_Y WIDTH HEIGHT] [PROFILE_DIR]"
  exit 1
fi

# ---- functions ----
ms_to_cet() {
  local ms="$1"
  local seconds=$(( ms / 1000 ))
  local milliseconds=$(( ms % 1000 ))

  TZ=Europe/Berlin date --date="@$seconds" "+%Y-%m-%d %H:%M:%S.$(printf '%03d' "$milliseconds") CET"
}

# ---- input value mapping and configuration ----

TARGET_URL="$1" # test with https://currentmillis.com/
# --- time target (milliseconds since epoch) ---
# Example: 2025-11-17 19:00:00.000 CET → use date +%s%3N to compute
# Example generation:
#   date --date="2025-11-17 19:00:00.000 CET" +%s%3N
TARGET_MS_CSV="$2"
DEBUG_PORT="$3"

POS_X="${4:-}"
POS_Y="${5:-}"
WIN_W="${6:-}"
WIN_H="${7:-}"

PROFILE_DIR="${8:-/tmp/chrome-${DEBUG_PORT}}"

CHROME_BIN="google-chrome"

# ---- check dependencies ----
if ! command -v jq >/dev/null 2>&1; then
  echo "[!] jq not found. Install with: sudo apt install -y jq"
  exit 1
fi

if ! command -v websocat >/dev/null 2>&1; then
  echo "[!] websocat not found. Install binary to /usr/local/bin."
  exit 1
fi

# ---- start Chrome if not already on this port ----
if ! curl -sf "http://127.0.0.1:${DEBUG_PORT}/json/version" >/dev/null 2>&1; then
  echo "[*] Starting Chrome on port ${DEBUG_PORT} ..."

  # build extra window flags if position/size given
  EXTRA_FLAGS=()
  if [ -n "${POS_X}" ] && [ -n "${POS_Y}" ] && [ -n "${WIN_W}" ] && [ -n "${WIN_H}" ]; then
    EXTRA_FLAGS+=(--window-position="${POS_X},${POS_Y}")
    EXTRA_FLAGS+=(--window-size="${WIN_W},${WIN_H}")
  fi

  # NOTE: requires a running X session (e.g. xRDP)
  "$CHROME_BIN" \
    --remote-debugging-port="${DEBUG_PORT}" \
    --user-data-dir="${PROFILE_DIR}" \
    --disable-features=PushMessaging \
    --new-window "${TARGET_URL}" \
    --password-store=basic \
    --no-default-browser-check \
    --no-first-run \
    "${EXTRA_FLAGS[@]}" >/dev/null 2>&1 &

  sleep 2
else
  echo "[*] Chrome on port ${DEBUG_PORT} already running"
fi

# ---- wait for DevTools JSON endpoint ----
echo "[*] Waiting for DevTools on port ${DEBUG_PORT} ..."
for _ in {1..30}; do
  if curl -sf "http://127.0.0.1:${DEBUG_PORT}/json" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

# ---- get WebSocket URL (first tab only) ----
WS_URL=$(
  curl -s "http://127.0.0.1:${DEBUG_PORT}/json" | jq -r '.[0].webSocketDebuggerUrl'
)

if [ -z "${WS_URL}" ] || [ "${WS_URL}" = "null" ]; then
  echo "[!] No WebSocket URL found on port ${DEBUG_PORT}"
  exit 1
fi
echo "[*] Using WebSocket: ${WS_URL}\n"

# ---- parse comma-separated timestamps into array ----
IFS=',' read -r -a TARGET_MS_ARRAY <<< "${TARGET_MS_CSV}"

echo "[*] Will trigger reloads at:"
for t in "${TARGET_MS_ARRAY[@]}"; do
  echo "$(ms_to_cet "$t") (${t})"
done
echo

# ---- for each target time: wait until it, then reload ----
TOTAL_RELOADS="${#TARGET_MS_ARRAY[@]}"
COUNT=0
for TARGET_MS in "${TARGET_MS_ARRAY[@]}"; do
  COUNT=$((COUNT + 1))
  echo "[*] Waiting until $(ms_to_cet "$TARGET_MS") (${TARGET_MS}) ... (reload ${COUNT}/${TOTAL_RELOADS})"

  while :; do
    NOW_MS=$(date +%s%3N)
    if (( NOW_MS >= TARGET_MS )); then
      break
    fi
    # small busy sleep (reduces CPU but still enough precision)
    sleep 0.001
  done

  printf '{"id":1,"method":"Page.reload","params":{"ignoreCache":true}}\n' \
    | websocat -q "${WS_URL}"

  FIRED_MS=$(date +%s%3N)
  echo "[*] Reload triggered at $(ms_to_cet "$FIRED_MS") (${FIRED_MS}) ms \n--> target was $(ms_to_cet "$TARGET_MS") (${TARGET_MS})  [${COUNT}/${TOTAL_RELOADS}]"
done

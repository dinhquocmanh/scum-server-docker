#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=functions.sh
source /opt/scum/scripts/functions.sh

GAME_PORT="${GAME_PORT:-7777}"
QUERY_PORT="${QUERY_PORT:-27015}"
MULTIHOME_IP="${MULTIHOME_IP:-}"
MAX_PLAYERS="${MAX_PLAYERS:-32}"
RCON_PORT="${RCON_PORT:-$((GAME_PORT + 2))}"
ADDITIONAL_FLAGS="${ADDITIONAL_FLAGS:--nobattleye}"

require_uint GAME_PORT "$GAME_PORT"
require_uint QUERY_PORT "$QUERY_PORT"
require_uint RCON_PORT "$RCON_PORT"
[[ "$MAX_PLAYERS" =~ ^[1-9][0-9]*$ ]] || { error "MAX_PLAYERS must be a positive integer"; exit 64; }
if [[ -n "$MULTIHOME_IP" ]]; then
  [[ "$MULTIHOME_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { error "MULTIHOME_IP must be an IPv4 address; got '$MULTIHOME_IP'"; exit 64; }
  IFS=. read -r octet1 octet2 octet3 octet4 <<< "$MULTIHOME_IP"
  (( octet1 <= 255 && octet2 <= 255 && octet3 <= 255 && octet4 <= 255 )) || { error "MULTIHOME_IP octets must be <= 255"; exit 64; }
fi

multihome_arg=()
if [[ -n "$MULTIHOME_IP" ]]; then
  multihome_arg=("-MultiHome=$MULTIHOME_IP")
fi

cd /data/server
info "Launching SCUM: game UDP ${GAME_PORT}-$((GAME_PORT + 2)), query UDP ${QUERY_PORT}, RCON TCP ${RCON_PORT}, max players ${MAX_PLAYERS}"

shutdown() {
  warn "Shutdown received; forwarding SIGINT to SCUM"
  if [[ -n "${SCUM_PID:-}" ]] && kill -0 "$SCUM_PID" 2>/dev/null; then
    kill -INT "$SCUM_PID" || true
    for _ in $(seq 1 75); do
      kill -0 "$SCUM_PID" 2>/dev/null || break
      sleep 1
    done
    kill -0 "$SCUM_PID" 2>/dev/null && kill -TERM "$SCUM_PID" || true
  fi
  send_lifecycle_log "SCUM server stopped."
  exit 0
}
trap shutdown SIGTERM SIGINT

# Xvfb prevents Wine from failing where an Unreal/Wine build expects a display.
# ADDITIONAL_FLAGS is intentionally word-split to support several documented flags.
# shellcheck disable=SC2086
as_server_user xvfb-run --auto-servernum --server-args="-screen 0 1024x768x24" \
  wine /data/server/SCUM/Binaries/Win64/SCUMServer.exe \
    -log -NoSound -Port="$GAME_PORT" -QueryPort="$QUERY_PORT" -MaxPlayers="$MAX_PLAYERS" \
    "${multihome_arg[@]}" \
    $ADDITIONAL_FLAGS &
SCUM_PID=$!

for _ in $(seq 1 60); do
  if pgrep -f 'SCUMServer.exe' >/dev/null; then
    info "SCUMServer.exe process detected"
    break
  fi
  kill -0 "$SCUM_PID" 2>/dev/null || { error "Wine launcher exited before SCUM started"; wait "$SCUM_PID"; exit $?; }
  sleep 1
done

wait "$SCUM_PID"
status=$?
error "SCUM launcher exited with status ${status}"
exit "$status"

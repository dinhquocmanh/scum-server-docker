#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=functions.sh
source /opt/scum/scripts/functions.sh

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
GAME_PORT="${GAME_PORT:-7777}"
QUERY_PORT="${QUERY_PORT:-27015}"

require_uint GAME_PORT "$GAME_PORT"
require_uint QUERY_PORT "$QUERY_PORT"
(( GAME_PORT <= 65533 )) || { error "GAME_PORT must leave room for GAME_PORT+1/+2"; exit 64; }

mkdir -p /data/server /data/depotdownloader /tmp/runtime-scum
ensure_owner "$PUID" "$PGID"

export HOME=/home/scum
export WINEPREFIX=/home/scum/.wine
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:-fixme-all,err+all}"
export XDG_RUNTIME_DIR=/tmp/runtime-scum

# melle2/scum-ds installs vcrun2017, d3dcompiler_47 and native crypt32 in this
# exact image prefix at build time. Do not recreate or re-provision it: current
# Microsoft vcrun2017 payloads can deadlock the old Winetricks recipe.
if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
  error "The inherited melle2 Wine prefix is missing; refusing to start an unprovisioned SCUM runtime."
  exit 1
fi

if is_true "${UPDATE_ON_START:-true}" || [[ ! -f /data/server/SCUM/Binaries/Win64/SCUMServer.exe ]]; then
  info "Installing/updating SCUM Dedicated Server (AppID 3792580) using DepotDownloader"
  send_lifecycle_log "Starting DepotDownloader update for SCUM AppID 3792580."
  update_args=(
    -app 3792580
    -os windows
    -osarch 64
    -dir /data/server
    -max-downloads "${DEPOT_MAX_DOWNLOADS:-8}"
  )
  if is_true "${VALIDATE_ON_UPDATE:-false}"; then
    update_args+=(-validate)
  fi
  as_server_user /depotdownloader/DepotDownloader "${update_args[@]}"
  info "DepotDownloader completed"
else
  info "UPDATE_ON_START=false and server is installed; skipping update"
fi

if [[ ! -f /data/server/SCUM/Binaries/Win64/SCUMServer.exe ]]; then
  error "SCUMServer.exe is missing after DepotDownloader. Check the preceding DepotDownloader output."
  exit 1
fi

chown -R "$PUID:$PGID" /data/server /data/depotdownloader
apply_scum_settings
send_lifecycle_log "SCUM files are ready; starting server."
exec /opt/scum/scripts/start.sh

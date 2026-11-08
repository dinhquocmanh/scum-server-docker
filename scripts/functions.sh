#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date -Is)" "$level" "$*"
}

info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@" >&2; }

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_uint() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || { error "$name must be an unsigned integer; got '$value'"; return 1; }
  (( value >= 1 && value <= 65535 )) || { error "$name must be in 1..65535; got '$value'"; return 1; }
}

ensure_owner() {
  local uid="$1" gid="$2"
  [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || { error "PUID and PGID must be numeric"; return 1; }
  # The inherited melle2 Wine prefix must remain owned by its established scum
  # account (mapped here to the requested host UID:GID).
  groupmod -o -g "$gid" scum
  usermod -o -u "$uid" -g "$gid" scum
  chown -R "$uid:$gid" /data /home/scum /tmp/runtime-scum
}

as_server_user() {
  gosu scum "$@"
}

apply_scum_settings() {
  local settings='/data/server/SCUM/Saved/Config/WindowsServer/ServerSettings.ini'
  [[ -f "$settings" ]] || return 0
  SERVER_NAME="${SERVER_NAME:-SCUM Docker Server}" \
  SERVER_DESCRIPTION="${SERVER_DESCRIPTION:-}" \
  SERVER_PASSWORD="${SERVER_PASSWORD:-}" \
  SERVER_PLAYSTYLE="${SERVER_PLAYSTYLE:-PVP}" \
  RCON_ENABLED="${RCON_ENABLED:-1}" \
  RCON_PORT="${RCON_PORT:-$GAME_PORT}" \
  RCON_PASSWORD="${RCON_PASSWORD:-}" \
  python3 - "$settings" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
values = {
    'scum.ServerName': os.environ['SERVER_NAME'],
    'scum.ServerDescription': os.environ['SERVER_DESCRIPTION'],
    'scum.ServerPassword': os.environ['SERVER_PASSWORD'],
    'scum.ServerPlaystyle': os.environ['SERVER_PLAYSTYLE'],
    'RCONEnabled': os.environ['RCON_ENABLED'],
    'RCONPort': os.environ['RCON_PORT'],
    'RCONPassword': os.environ['RCON_PASSWORD'],
}
lines = path.read_text(encoding='utf-8', errors='surrogateescape').splitlines(keepends=True)
section = None
seen = set()
out = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        if section == 'General':
            for key, value in values.items():
                if key not in seen:
                    out.append(f'{key}={value}\n')
        section = stripped[1:-1]
        out.append(line)
        continue
    if section == 'General' and '=' in line:
        key = line.split('=', 1)[0].strip()
        if key in values:
            out.append(f'{key}={values[key]}\n')
            seen.add(key)
            continue
    out.append(line)
if section == 'General':
    for key, value in values.items():
        if key not in seen:
            out.append(f'{key}={value}\n')
elif not any(line.strip() == '[General]' for line in lines):
    out.extend(['\n[General]\n'] + [f'{key}={value}\n' for key, value in values.items()])
tmp = path.with_suffix('.ini.tmp')
tmp.write_text(''.join(out), encoding='utf-8', errors='surrogateescape')
tmp.replace(path)
PY
}

send_lifecycle_log() {
  local message="$1"
  /opt/scum/scripts/send-log.py "$message" || warn "Lifecycle webhook delivery failed (non-fatal)"
}

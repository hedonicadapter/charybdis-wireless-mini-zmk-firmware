#!/usr/bin/env bash
# Flash latest CI firmware (firmware-bt-qwerty) onto nice!nano halves in bootloader mode.
#
# Usage:
#   scripts/flash.sh watch                  auto-flash any half that enters bootloader
#   scripts/flash.sh learn left|right       record which chip is which half (once per half)
#   scripts/flash.sh [right|left|both]      one-off manual flash (default: right)
#
# Env:   BRANCH  branch whose latest successful build to use
#        RUN_ID  use a specific workflow run instead
#
# Bootloader: hold Space+Enter (XTRA), tap B (left half) or N (right half).
# Needs: gh (logged in), udisksctl, lsblk/findmnt, udevadm; notify-send optional.
set -euo pipefail

REPO="hedonicadapter/charybdis-wireless-mini-zmk-firmware"
BRANCH="${BRANCH:-claude/zmk-keybind-3x5-remap-0ewtqz}"
ARTIFACT="firmware-bt-qwerty"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/charybdis-fw"
SERIALS="${XDG_CONFIG_HOME:-$HOME/.config}/charybdis-flash/serials"

log() { echo "[charybdis-flash] $*" >&2; }
notify() {
  log "$*"
  command -v notify-send >/dev/null && notify-send -a "Charybdis" "Charybdis" "$*" || true
}

# Download latest successful build (cached per run), print its directory
fetch_firmware() {
  local run_id="${RUN_ID:-}" dir tmp
  if [[ -z "$run_id" ]]; then
    run_id=$(gh run list -R "$REPO" -w build.yml -b "$BRANCH" -s success -L 1 \
      --json databaseId -q '.[0].databaseId')
    [[ -n "$run_id" ]] || { log "No successful build found on $BRANCH"; return 1; }
  fi
  dir="$CACHE_ROOT/$run_id"
  if [[ ! -d "$dir" ]]; then
    log "Downloading $ARTIFACT from run $run_id"
    tmp="$dir.tmp"
    rm -rf "$tmp"
    gh run download "$run_id" -R "$REPO" -n "$ARTIFACT" -D "$tmp" >&2
    mv "$tmp" "$dir"
  fi
  echo "$dir"
}

# Block devices currently in bootloader mode (FAT volume labelled NICENANO)
nicenano_devices() {
  lsblk -rno PATH,LABEL 2>/dev/null | awk '$2 == "NICENANO" { print $1 }'
}

device_serial() {
  udevadm info -q property -n "$1" 2>/dev/null | sed -n 's/^ID_SERIAL_SHORT=//p'
}

side_for_serial() {
  [[ -f "$SERIALS" ]] && awk -v s="$1" '$1 == s { print $2 }' "$SERIALS" || true
}

mount_point() {
  local dev=$1 mnt=""
  for _ in $(seq 20); do
    mnt=$(findmnt -n -o TARGET --source "$dev" 2>/dev/null || true)
    [[ -n "$mnt" ]] && break
    sleep 0.5
  done
  # Not auto-mounted
  [[ -n "$mnt" ]] || udisksctl mount -b "$dev" >/dev/null
  # Read-only mount (e.g. FAT left dirty by a reboot mid-write): remount rw
  if [[ ",$(findmnt -n -o OPTIONS --source "$dev")," == *",ro,"* ]]; then
    log "$dev mounted read-only, remounting rw"
    udisksctl unmount -b "$dev" >/dev/null
    udisksctl mount -b "$dev" -o rw >/dev/null
  fi
  findmnt -n -o TARGET --source "$dev"
}

# Copy firmware for $side onto $dev and wait for the board to reboot
flash_device() {
  local dev=$1 side=$2 fw uf2 mnt
  fw=$(fetch_firmware) || { notify "No firmware available to flash"; return 1; }
  uf2="$fw/charybdis_${side}_bt-qwerty.uf2"
  [[ -f "$uf2" ]] || { notify "Missing $(basename "$uf2") in build"; return 1; }
  mnt=$(mount_point "$dev")
  log "Copying $(basename "$uf2") to $mnt ($dev)"
  # Board reboots as soon as the copy lands; I/O errors after that are expected
  cp "$uf2" "$mnt/" 2>/dev/null || true
  sync 2>/dev/null || true
  while [[ -b "$dev" ]] && [[ "$(lsblk -rno LABEL "$dev" 2>/dev/null)" == NICENANO ]]; do sleep 0.5; done
  notify "Flashed $side half ($(basename "$fw"))"
}

wait_for_device() {
  local dev
  log "Waiting for a half in bootloader mode..."
  while :; do
    dev=$(nicenano_devices | head -n1)
    [[ -n "$dev" ]] && { echo "$dev"; return; }
    sleep 0.5
  done
}

cmd_learn() {
  local side=$1 dev serial
  [[ "$side" == left || "$side" == right ]] || { echo "usage: $0 learn left|right" >&2; exit 1; }
  dev=$(wait_for_device)
  serial=$(device_serial "$dev")
  [[ -n "$serial" ]] || { log "Could not read USB serial for $dev"; exit 1; }
  mkdir -p "$(dirname "$SERIALS")"
  touch "$SERIALS"
  # Replace any previous entry for this serial or side
  awk -v s="$serial" -v d="$side" '$1 != s && $2 != d' "$SERIALS" > "$SERIALS.tmp"
  echo "$serial $side" >> "$SERIALS.tmp"
  mv "$SERIALS.tmp" "$SERIALS"
  log "Recorded $serial as $side half"
  flash_device "$dev" "$side"
}

cmd_watch() {
  local dev serial side
  declare -A busy=()
  log "Watching for halves in bootloader mode (branch $BRANCH)"
  while :; do
    for dev in $(nicenano_devices); do
      [[ -n "${busy[$dev]:-}" ]] && continue
      serial=$(device_serial "$dev")
      side=$(side_for_serial "$serial")
      if [[ -z "$side" ]]; then
        notify "Unknown half (serial $serial). Run: flash.sh learn left|right"
        busy[$dev]=unknown
        continue
      fi
      busy[$dev]=1
      flash_device "$dev" "$side" || true
    done
    # Forget devices that are gone so they flash again next time
    for dev in "${!busy[@]}"; do
      [[ " $(nicenano_devices | tr '\n' ' ') " == *" $dev "* ]] || unset "busy[$dev]"
    done
    sleep 1
  done
}

cmd_manual() {
  local side
  for side in "$@"; do
    log "== $side half =="
    flash_device "$(wait_for_device)" "$side"
  done
}

case "${1:-right}" in
  watch) cmd_watch ;;
  learn) cmd_learn "${2:-}" ;;
  right) cmd_manual right ;;
  left)  cmd_manual left ;;
  both)  cmd_manual right left ;;
  *) echo "usage: $0 watch | learn left|right | [right|left|both]" >&2; exit 1 ;;
esac

#!/usr/bin/env bash
# Flash latest CI firmware (firmware-bt-qwerty) onto a nice!nano in bootloader mode.
#
# Usage: scripts/flash.sh [right|left|both]   (default: right)
# Env:   BRANCH  branch whose latest successful build to use
#        RUN_ID  use a specific workflow run instead
#
# Bootloader: hold Space+Enter (XTRA), tap B (left half) or N (right half).
# Needs: gh (logged in), udisksctl (udisks2) unless NICENANO auto-mounts.
set -euo pipefail

REPO="hedonicadapter/charybdis-wireless-mini-zmk-firmware"
BRANCH="${BRANCH:-claude/zmk-keybind-3x5-remap-0ewtqz}"
ARTIFACT="firmware-bt-qwerty"
SIDE="${1:-right}"

case "$SIDE" in
  right|left|both) ;;
  *) echo "usage: $0 [right|left|both]" >&2; exit 1 ;;
esac

run_id="${RUN_ID:-}"
if [[ -z "$run_id" ]]; then
  run_id=$(gh run list -R "$REPO" -w build.yml -b "$BRANCH" -s success -L 1 \
    --json databaseId -q '.[0].databaseId')
  [[ -n "$run_id" ]] || { echo "No successful build found on $BRANCH" >&2; exit 1; }
fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}/charybdis-fw/$run_id"
if [[ ! -d "$cache" ]]; then
  echo "Downloading $ARTIFACT from run $run_id..."
  tmp="$cache.tmp"
  rm -rf "$tmp"
  gh run download "$run_id" -R "$REPO" -n "$ARTIFACT" -D "$tmp"
  mv "$tmp" "$cache"
else
  echo "Using cached firmware from run $run_id"
fi

# Wait for NICENANO, mount if needed, print mount point
wait_for_nicenano() {
  local dev=/dev/disk/by-label/NICENANO mnt
  echo "Waiting for NICENANO (put the half in bootloader mode)..." >&2
  until [[ -e "$dev" ]]; do sleep 0.5; done
  for _ in $(seq 20); do
    mnt=$(findmnt -n -o TARGET --source "$dev" 2>/dev/null || true)
    [[ -n "$mnt" ]] && { echo "$mnt"; return; }
    sleep 0.5
  done
  # Not auto-mounted
  udisksctl mount -b "$dev" >/dev/null
  findmnt -n -o TARGET --source "$dev"
}

flash() {
  local side=$1 uf2 mnt
  uf2="$cache/charybdis_${side}_bt-qwerty.uf2"
  [[ -f "$uf2" ]] || { echo "Missing $uf2" >&2; exit 1; }
  echo "== $side half =="
  mnt=$(wait_for_nicenano)
  echo "Copying $(basename "$uf2") to $mnt"
  # Board reboots as soon as the copy lands; I/O errors after that are expected
  cp "$uf2" "$mnt/" 2>/dev/null || true
  sync 2>/dev/null || true
  # Wait for the board to drop off before the next half
  while [[ -e /dev/disk/by-label/NICENANO ]]; do sleep 0.5; done
  echo "$side half flashed."
}

case "$SIDE" in
  right) flash right ;;
  left)  flash left ;;
  both)  flash right; flash left ;;
esac

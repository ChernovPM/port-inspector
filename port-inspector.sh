#!/usr/bin/env bash
set -e

# Simple Port Inspector (training version)
# Features:
#   - check if port is free/busy
#   - list listeners
#   - find first free port in range
#
# Usage:
#   ./port-inspector.sh --check 8000
#   ./port-inspector.sh --free 8000 8100
#   ./port-inspector.sh --list
#
# NOTE: This script is intentionally minimal; you'll ask Codex to polish it.

MODE="${1:-}"
ARG1="${2:-}"
ARG2="${3:-}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

list_listeners() {
  if have_cmd ss; then
    ss -lntp
  elif have_cmd lsof; then
    lsof -nP -iTCP -sTCP:LISTEN
  else
    echo "Neither ss nor lsof found. Install iproute2 or lsof." >&2
    exit 2
  fi
}

is_port_listening() {
  local port="$1"
  if have_cmd ss; then
    ss -lnt "( sport = :$port )" | tail -n +2 | grep -q .
  elif have_cmd lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  else
    echo "Neither ss nor lsof found." >&2
    exit 2
  fi
}

check_port() {
  local port="$1"
  if [[ -z "$port" ]]; then
    echo "Port is required" >&2
    exit 2
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    echo "Port must be a number" >&2
    exit 2
  fi

  if is_port_listening "$port"; then
    echo "BUSY: $port"
    exit 1
  else
    echo "FREE: $port"
    exit 0
  fi
}

find_free_port() {
  local start="$1"
  local end="$2"

  if [[ -z "$start" || -z "$end" ]]; then
    echo "Start and end ports are required" >&2
    exit 2
  fi

  for ((p=start; p<=end; p++)); do
    if ! is_port_listening "$p"; then
      echo "$p"
      return 0
    fi
  done

  echo "No free port found in range ${start}-${end}" >&2
  return 1
}

case "$MODE" in
  --list)
    list_listeners
    ;;
  --check)
    check_port "$ARG1"
    ;;
  --free)
    find_free_port "$ARG1" "$ARG2"
    ;;
  *)
    echo "Port Inspector"
    echo ""
    echo "Usage:"
    echo "  $0 --list"
    echo "  $0 --check <port>"
    echo "  $0 --free <start_port> <end_port>"
    exit 2
    ;;
esac

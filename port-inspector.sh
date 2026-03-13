#!/usr/bin/env bash
set -euo pipefail

readonly EXIT_BUSY=1
readonly EXIT_USAGE=2

SCRIPT_NAME="$(basename "$0")"
MODE=""
PORT=""
RANGE_START=""
RANGE_END=""
PROTOCOL="tcp"
USE_COLOR=1
BACKEND=""

RED=''
GREEN=''
YELLOW=''
BLUE=''
RESET=''

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

supports_color() {
  [[ -t 1 ]]
}

setup_colors() {
  if [[ "$USE_COLOR" -eq 1 ]] && supports_color; then
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    RESET=$'\033[0m'
  fi
}

print_error() {
  printf '%b\n' "${RED}ERROR:${RESET} $*" >&2
}

print_info() {
  printf '%b\n' "${BLUE}INFO:${RESET} $*"
}

print_usage() {
  cat <<EOF
Port Inspector - inspect listening ports and discover free ones

Usage:
  $SCRIPT_NAME [global options] --list
  $SCRIPT_NAME [global options] --check <port>
  $SCRIPT_NAME [global options] --find-free <start_port> <end_port>
  $SCRIPT_NAME [global options] --free <start_port> <end_port>

Modes:
  --list                     List listening TCP sockets.
  --check <port>             Exit 0 if port is free, 1 if busy.
  --find-free <start> <end>  Print first free port in inclusive range.
  --free <start> <end>       Alias for --find-free.

Global options:
  --protocol <proto>         Transport protocol to inspect (currently: tcp).
  --no-color                 Disable colored output.
  -h, --help                 Show this help text.

Exit codes:
  0  Success
  1  Busy port on --check, or no free port found
  2  Usage / environment error
EOF
}

validate_protocol() {
  local protocol="$1"
  case "$protocol" in
    tcp) ;;
    *)
      print_error "Unsupported protocol '$protocol'. Only 'tcp' is currently supported."
      exit "$EXIT_USAGE"
      ;;
  esac
}

validate_port() {
  local raw_port="$1"

  if ! [[ "$raw_port" =~ ^[0-9]+$ ]]; then
    print_error "Invalid port '$raw_port' (must be an integer)."
    exit "$EXIT_USAGE"
  fi

  local port=$((10#$raw_port))

  if (( port < 1 || port > 65535 )); then
    print_error "Invalid port '$raw_port' (must be in range 1..65535)."
    exit "$EXIT_USAGE"
  fi
}

choose_backend() {
  if is_linux && have_cmd ss; then
    BACKEND="ss"
    return
  fi

  if is_macos && have_cmd lsof; then
    BACKEND="lsof"
    return
  fi

  if have_cmd ss; then
    BACKEND="ss"
    return
  fi

  if have_cmd lsof; then
    BACKEND="lsof"
    return
  fi

  print_error "No supported tooling found. Install 'ss' (Linux iproute2) or 'lsof' (macOS/Linux)."
  exit "$EXIT_USAGE"
}

list_listeners() {
  case "$BACKEND" in
    ss)
      ss -lnt
      ;;
    lsof)
      lsof -nP -iTCP -sTCP:LISTEN
      ;;
    *)
      print_error "Unknown backend '$BACKEND'."
      exit "$EXIT_USAGE"
      ;;
  esac
}

is_port_busy() {
  local raw_port="$1"
  local port=$((10#$raw_port))

  case "$BACKEND" in
    ss)
      ss -lntH "sport = :$port" | grep -q .
      ;;
    lsof)
      lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
      ;;
    *)
      print_error "Unknown backend '$BACKEND'."
      exit "$EXIT_USAGE"
      ;;
  esac
}

check_port() {
  local port="$1"
  validate_port "$port"

  if is_port_busy "$port"; then
    printf '%b\n' "${YELLOW}BUSY${RESET}: $port"
    return "$EXIT_BUSY"
  fi

  printf '%b\n' "${GREEN}FREE${RESET}: $port"
  return 0
}

find_first_free_port() {
  local start_raw="$1"
  local end_raw="$2"
  local start_port end_port port

  validate_port "$start_raw"
  validate_port "$end_raw"

  start_port=$((10#$start_raw))
  end_port=$((10#$end_raw))

  if (( start_port > end_port )); then
    print_error "Invalid range: start port ($start_port) is greater than end port ($end_port)."
    exit "$EXIT_USAGE"
  fi

  for ((port = start_port; port <= end_port; port++)); do
    if ! is_port_busy "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done

  print_info "No free port found in range ${start_port}-${end_port}."
  return 1
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit "$EXIT_USAGE"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list)
        [[ -z "$MODE" ]] || { print_error "Only one mode can be specified."; exit "$EXIT_USAGE"; }
        MODE="list"
        shift
        ;;
      --check)
        [[ -z "$MODE" ]] || { print_error "Only one mode can be specified."; exit "$EXIT_USAGE"; }
        [[ $# -ge 2 ]] || { print_error "--check requires <port>."; exit "$EXIT_USAGE"; }
        MODE="check"
        PORT="$2"
        shift 2
        ;;
      --find-free|--free)
        [[ -z "$MODE" ]] || { print_error "Only one mode can be specified."; exit "$EXIT_USAGE"; }
        [[ $# -ge 3 ]] || { print_error "--find-free requires <start_port> <end_port>."; exit "$EXIT_USAGE"; }
        MODE="find_free"
        RANGE_START="$2"
        RANGE_END="$3"
        shift 3
        ;;
      --protocol)
        [[ $# -ge 2 ]] || { print_error "--protocol requires a value."; exit "$EXIT_USAGE"; }
        PROTOCOL="$2"
        shift 2
        ;;
      --no-color)
        USE_COLOR=0
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        print_error "Unknown argument '$1'."
        print_usage
        exit "$EXIT_USAGE"
        ;;
    esac
  done

  if [[ -z "$MODE" ]]; then
    print_error "A mode is required (--list, --check, or --find-free)."
    print_usage
    exit "$EXIT_USAGE"
  fi
}

main() {
  setup_colors
  parse_args "$@"
  validate_protocol "$PROTOCOL"
  choose_backend

  case "$MODE" in
    list)
      list_listeners
      ;;
    check)
      check_port "$PORT"
      ;;
    find_free)
      find_first_free_port "$RANGE_START" "$RANGE_END"
      ;;
    *)
      print_error "Unknown mode '$MODE'."
      exit "$EXIT_USAGE"
      ;;
  esac
}

main "$@"

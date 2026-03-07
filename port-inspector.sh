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
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    BLUE='\033[34m'
    RESET='\033[0m'
  else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    RESET=''
  fi
}

print_error() {
  printf '%b\n' "${RED}ERROR:${RESET} $*" >&2
}

print_info() {
  printf '%b\n' "${BLUE}INFO:${RESET} $*"
}

print_usage() {
  cat <<USAGE
Port Inspector - inspect listening ports and discover free ones

Usage:
  $SCRIPT_NAME [global options] --list
  $SCRIPT_NAME [global options] --check <port>
  $SCRIPT_NAME [global options] --find-free <start_port> <end_port>

Modes:
  --list                     List listening sockets.
  --check <port>             Exit 0 if port is free, 1 if busy.
  --find-free <start> <end>  Print first free port in inclusive range.

Global options:
  --protocol <proto>         Transport protocol to inspect (currently: tcp).
  --no-color                 Disable colored output.
  -h, --help                 Show this help text.

Exit codes:
  0  Success (including free port on --check)
  1  Busy port on --check, or no free port in --find-free
  2  Usage / environment error
USAGE
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
  local port="$1"

  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    print_error "Invalid port '$port' (must be an integer)."
    exit "$EXIT_USAGE"
  fi

  if (( port < 1 || port > 65535 )); then
    print_error "Invalid port '$port' (must be in range 1..65535)."
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
      # Show listening TCP sockets in numeric format.
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
  local port="$1"

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
  local start_port="$1"
  local end_port="$2"
  local port

  validate_port "$start_port"
  validate_port "$end_port"

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
  parse_args "$@"
  setup_colors
  validate_protocol "$PROTOCOL"

  case "$MODE" in
    list)
      choose_backend
      list_listeners
      ;;
    check)
      validate_port "$PORT"
      choose_backend
      check_port "$PORT"
      ;;
    find_free)
      validate_port "$RANGE_START"
      validate_port "$RANGE_END"
      choose_backend
      find_first_free_port "$RANGE_START" "$RANGE_END"
      ;;
    *)
      print_error "Unknown mode '$MODE'."
      exit "$EXIT_USAGE"
      ;;
  esac
}

main "$@"

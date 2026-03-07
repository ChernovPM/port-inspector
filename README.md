# Port Inspector

A production-ready Bash utility to inspect TCP listeners and quickly locate free ports on developer machines and CI runners.

## Why this exists

In DevOps workflows, port conflicts cause flaky local runs, broken integration tests, and failed container startup. `port-inspector.sh` gives a single, scriptable interface to:

- list active listeners,
- check whether a specific port is available,
- find the first free port in a range.

It is designed for both Linux (Ubuntu) and macOS environments.

## Features

- Strict Bash mode (`set -euo pipefail`) for reliability.
- Argument parsing with `-h` / `--help`.
- Port validation (`1..65535`) and range checks.
- Protocol flag (`--protocol tcp`) with clean extension points.
- Optional colored output with `--no-color` support.
- OS-aware backend selection:
  - Prefer `ss` on Linux.
  - Prefer `lsof` on macOS.
  - Fallback logic when preferred tool is unavailable.
- Clear exit codes for automation:
  - `0`: success (or free on `--check`)
  - `1`: busy on `--check`, or none free on `--find-free`
  - `2`: usage/environment errors

## Requirements

- Bash 4+
- One of:
  - `ss` (from `iproute2`, common on Ubuntu/Linux)
  - `lsof` (default on macOS, often available on Linux)

## Installation

### Option 1: Direct use

```bash
chmod +x port-inspector.sh
./port-inspector.sh --help
```

### Option 2: Install in your PATH

```bash
install -m 0755 port-inspector.sh /usr/local/bin/port-inspector
port-inspector --help
```

## Usage

### Show help

```bash
./port-inspector.sh --help
```

### List listeners

```bash
./port-inspector.sh --list
```

### Check a specific port

```bash
./port-inspector.sh --check 8080
echo $?   # 0 = free, 1 = busy, 2 = usage error
```

### Find the first free port in a range

```bash
./port-inspector.sh --find-free 8000 8100
```

### Disable color output (for logs/CI)

```bash
./port-inspector.sh --no-color --check 8080
```

### Protocol flag

```bash
./port-inspector.sh --protocol tcp --list
```

## CI

GitHub Actions runs `shellcheck` on every push and pull request.

Workflow file: `.github/workflows/ci.yml`.

## License

MIT. See [LICENSE](LICENSE).

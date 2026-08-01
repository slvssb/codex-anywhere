#!/usr/bin/env bash
set -euo pipefail

CODEX_BIN=/usr/local/bin/codex-real

if [ "$(id -u)" -eq 0 ]; then
    exec runuser -u user --preserve-environment -- \
        env HOME=/home/user USER=user LOGNAME=user \
        CODEX_HOME="${CODEX_HOME:-/data/.codex}" \
        "$CODEX_BIN" "$@"
fi

exec "$CODEX_BIN" "$@"

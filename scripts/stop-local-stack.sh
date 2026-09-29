#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v powershell.exe >/dev/null; then
  echo 'These local scripts require Windows PowerShell and PostgreSQL on PATH.' >&2
  exit 1
fi
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$script_dir/stop-local-stack.ps1")"

#!/usr/bin/env bash
# Runs every qbcore smoke test with plain Lua (no busted). Exits non-zero on any
# failure. Each file loads only the module(s) it exercises, in one realm, to
# avoid the same-name-across-realms collision (see qblib AGENTS.md).
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua_bin="${LUA:-lua}"
status=0
for file in "$dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    if ! ( cd "$dir/.." && "$lua_bin" "$file" ); then status=1; fi
    echo
done
if ! bash "$dir/txadmin_installer.sh"; then status=1; fi
exit "$status"

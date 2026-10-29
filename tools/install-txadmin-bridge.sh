#!/usr/bin/env bash
# Run before starting txAdmin, including after replacing FXServer artifacts.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo 'Usage: bash tools/install-txadmin-bridge.sh /path/to/citizen/system_resources/monitor' >&2
    exit 1
fi

bridge_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
monitor_dir="$(cd -- "$1" && pwd)"
bridge_source="$bridge_script_dir/../integrations/txadmin.lua"
bridge_target="$monitor_dir/resource/qbcore_bridge.lua"
manifest="$monitor_dir/fxmanifest.lua"
bridge_entry="server_script 'resource/qbcore_bridge.lua'"

if [ ! -f "$manifest" ] || [ ! -f "$monitor_dir/resource/sv_admins.lua" ]; then
    echo 'Expected the bundled txAdmin monitor resource; no bridge was installed.' >&2
    exit 1
fi

bridge_temp=''
manifest_temp=''
trap 'rm -f -- "$bridge_temp" "$manifest_temp"' EXIT

if ! cmp -s "$bridge_source" "$bridge_target"; then
    bridge_temp="$(mktemp "$bridge_target.XXXXXX")"
    cat "$bridge_source" > "$bridge_temp"
    chmod 644 "$bridge_temp"
    mv -- "$bridge_temp" "$bridge_target"
fi

if ! grep -Fxq "$bridge_entry" "$manifest"; then
    manifest_temp="$(mktemp "$manifest.XXXXXX")"
    cat "$manifest" > "$manifest_temp"
    printf '\n%s\n' "$bridge_entry" >> "$manifest_temp"
    chmod 644 "$manifest_temp"
    mv -- "$manifest_temp" "$manifest"
fi

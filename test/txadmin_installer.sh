#!/usr/bin/env bash
set -euo pipefail

installer_test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
installer="$installer_test_dir/../tools/install-txadmin-bridge.sh"
fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
monitor="$fixture_dir/monitor with spaces"
mkdir -p "$monitor/resource"
printf "server_scripts { 'resource/sv_admins.lua' }\n-- preserved vendor content\n" > "$monitor/fxmanifest.lua"
touch "$monitor/resource/sv_admins.lua"
cp "$monitor/fxmanifest.lua" "$fixture_dir/original.lua"

bash "$installer" "$monitor"
cmp "$installer_test_dir/../integrations/txadmin.lua" "$monitor/resource/qbcore_bridge.lua"
head -n 2 "$monitor/fxmanifest.lua" | cmp - "$fixture_dir/original.lua"
cp "$monitor/fxmanifest.lua" "$fixture_dir/installed.lua"
bash "$installer" "$monitor"
cmp "$monitor/fxmanifest.lua" "$fixture_dir/installed.lua"

# Replacing artifacts removes the helper and manifest entry; installation restores both.
cp "$fixture_dir/original.lua" "$monitor/fxmanifest.lua"
rm "$monitor/resource/qbcore_bridge.lua"
bash "$installer" "$monitor"
cmp "$monitor/fxmanifest.lua" "$fixture_dir/installed.lua"
cmp "$installer_test_dir/../integrations/txadmin.lua" "$monitor/resource/qbcore_bridge.lua"

mkdir "$fixture_dir/unrelated"
if bash "$installer" "$fixture_dir/unrelated" 2>/dev/null; then
    echo 'Installer accepted an unrelated directory.' >&2
    exit 1
fi
echo 'txAdmin installer: installation, idempotency, artifact replacement and invalid target checks passed.'

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/script.lua"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

echo "compile: script.lua"
luau-compile --binary "$script" > /dev/null

echo "smoke: boot under the Roblox mock"
{
    cat "$root/tests/roblox_mock.luau"
    echo
    echo "local function main()"
    cat "$script"
    echo
    cat "$root/tests/smoke.luau"
    echo
    echo "end"
    echo "setfenv(main, env)"
    echo "main()"
    echo 'print("smoke: ok")'
} > "$build/smoke.luau"

output="$(luau "$build/smoke.luau" 2>&1)" || { echo "$output"; exit 1; }
echo "$output"
grep -q "smoke: ok" <<< "$output"

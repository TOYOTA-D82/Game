#!/usr/bin/env bash
# Runs the pure-Luau tests with Lune (https://lune-org.github.io).
# Shared modules use Roblox-style requires, so we copy them into a temp folder
# and rewrite `require(script.Parent.X)` into `require("./X")`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for f in "$here/../src/shared/"*.luau; do
  name="$(basename "$f")"
  {
    echo 'local Color3, Enum = (require("@lune/roblox") :: any).Color3, (require("@lune/roblox") :: any).Enum'
    sed -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/g' "$f"
  } > "$work/$name"
done
cp "$here/"*.spec.luau "$work/"
# World needs instance-level Roblox globals: give it the prelude and path requires.
cp "$here/prelude.luau" "$work/__prelude.luau"
cp "$here/world.check.luau" "$work/world.check.luau"
{
  echo 'local __env = require("./__prelude")'
  echo 'local game, Instance, Vector3, Vector2, CFrame, Color3, UDim, UDim2, Enum, ColorSequence, ColorSequenceKeypoint, NumberSequence, NumberRange, PhysicalProperties, Random = __env.game, __env.Instance, __env.Vector3, __env.Vector2, __env.CFrame, __env.Color3, __env.UDim, __env.UDim2, __env.Enum, __env.ColorSequence, __env.ColorSequenceKeypoint, __env.NumberSequence, __env.NumberRange, __env.PhysicalProperties, __env.Random'
  sed -E -e 's/require\(Shared\.([A-Za-z]+)\)/require(".\/\1")/g' \
         -e 's/bar:SetNetworkOwner\(nil\)/-- (live servers only)/' "$here/../src/server/World.luau"
} > "$work/World.luau"
status=0
echo "== compile check"
lune run "$here/compile.luau" "$here/../src" || status=1
for spec in "$work/"*.spec.luau "$work/world.check.luau"; do
  echo "== $(basename "$spec")"
  lune run "$spec" || status=1
done
exit $status

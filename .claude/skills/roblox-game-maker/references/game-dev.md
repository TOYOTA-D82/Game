# Building the game (Rojo + Luau)

## Toolchain in a cloud container

GitHub release downloads may be blocked; install from crates instead:

```bash
cargo install rojo --version 7.7.1
cargo install selene lune
```

- **Rojo** builds the place file: `rojo build default.project.json -o Game.rbxl`.
- **Selene** lints. The official `roblox` std download may fail; keep a small
  custom std file (`roblox_lite.yml`, `std = "roblox_lite"` in `selene.toml`)
  and add globals there when Selene reports `undefined_variable` for real
  Roblox types (e.g. `NumberSequenceKeypoint`).
- **Lune** runs Luau tests outside Roblox. It has `@lune/roblox` (real Instance
  property checking) but no `Random`, `Terrain`, or `Part.Position` setter, so
  keep pure logic in shared modules with their own RNG.

## Project layout that worked

```
default.project.json   Shared → ReplicatedStorage, Server → ServerScriptService,
                       Client → StarterPlayerScripts, Workspace.StreamingEnabled=false
src/shared/            pure modules (Config, Strings en/zh, Themes, Course generator,
                       Ranking, Calendar, Manual) — testable in Lune
src/server/            Main, Game, World (builds instances), Data (DataStore),
                       Progress, Shop, Cosmetics, TrailFx, Net (rate-limited remotes)
src/client/            Main, UI, Ambience (area hiding, sky), Chains, Effects, Trailer
tests/run.sh           copies shared modules, rewrites requires, runs *.spec.luau,
                       a compile check of every file, and world.check.luau which
                       builds the lobby + every level with real instances
```

- Put every tunable number in `Config` and every player-facing string in
  `Strings` (en + zh). Docs and the in-game manual read numbers from `Config`
  so they never disagree.
- Levels: generate routes from a daily seed (same on every server), and have a
  test that builds N levels × 60 days and proves each is reachable without
  buying anything (BFS over jumpable surfaces).
- Keep a shared `levelOrigin` so the client can rebuild the same route the
  server built (used by the recording tour).

## Checks before every commit

1. `bash tests/run.sh` (compile + specs + world build).
2. `selene src`.
3. For new instance properties / enums, check them against Lune's API dump
   (instantiate the class and read/write the property). Errors that say
   "missing default value" or "into 'Ref'" are harness limits, not real.
4. `rojo build` the `.rbxl` and commit it with the source so the user can open
   the latest file.

## Publishing

- Studio: 「檔案 → 發佈為」 once to link the local file to the existing
  experience (choose it in the list; the "無標題體驗" form creates a NEW game
  whose products won't work), then 「發佈」 (Alt+P) afterwards. 「儲存到 Roblox」
  does not update what players see.
- If Studio hangs on 「正在上傳」 / 「擷取失敗」, Studio can't reach Roblox
  (login, VPN, antivirus). Publishing from the container works via Open Cloud:

```bash
curl -X POST "https://apis.roblox.com/universes/v1/<universeId>/places/<placeId>/versions?versionType=Published" \
  -H "x-api-key: <key from the credential form>" -H "Content-Type: application/octet-stream" \
  --data-binary @Game.rbxl
```

  Universe id is in the Creator Hub URL; the place id (`rootPlaceId`) comes
  from `https://develop.roblox.com/v1/universes/<universeId>`. The key needs
  the `universe-places` → write permission for that experience and
  `0.0.0.0/0` as accepted IP. Ask before publishing; it is a real release.

## Roblox gotchas hit before

- Anything below `Workspace.FallenPartsDestroyHeight` (-500) is deleted —
  including a character standing on an area you hid client-side. Anchor the
  root while its floor is hidden.
- Client-side area hiding moves folders to ReplicatedStorage; physics and
  raycasts only see what's in Workspace, so show the area before teleporting.
- Conveyors / currents that push via the floor ray stop at the edge; keep
  pushing for ~0.6 s after leaving so players actually fall off.
- Purchasable items must not affect timed leaderboards (disable them there).
- A "Leave" button label should match what it does (e.g. 離開關卡 vs 離開隊伍).
- Effects must match their shop description (a "fire" trail leaves flames on
  the ground; "lightning" draws bolts). Keep glow and flicker soft; strong
  flicker and bright additive particles on white levels hurt the eyes.

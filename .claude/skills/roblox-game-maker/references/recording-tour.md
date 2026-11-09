# In-game recording tour (自動錄影導覽)

Goal: the user presses Play in Studio (or the owner types `/trailer` in the
live game), presses Win+Alt+R, and the game films itself with REAL footage.
`assets/recording-tour/Trailer.luau` is the working version from Chained Tower;
adapt its route source and shot list to the new game.

## Design that works

- **Real physics bot, not scripted sliding.** Steer the player's Humanoid like a
  player: `Humanoid:Move(dir)` toward the exit edge of the current platform,
  `Humanoid.Jump = true` near the edge, steer toward the next platform in the
  air, stop steering once above it, walk into ladders to climb. Default Animate
  script plays real animations. A version that CFrame-slid an anchored character
  went through walls and moving obstacles and looked fake — the user hated it.
- **Pick filmable stretches.** Rebuild today's route on the client from the
  shared generator (same seed), BFS the platforms, and only film stretches where
  every hop is doable (gap ≤ ~6 studs, rise ≤ ~3.6, ladders on truss sections).
  Skip sections the bot can't handle: flying walls, spinners, moving platforms,
  rapids, conveyors, ice, and whole levels whose floors are slippery. Give each
  shot backup levels and try shorter stretches before giving up; prove in Lune
  that every shot finds a stretch for the next 60 days.
- **Hold the character still between shots** (anchor the root) — hiding the
  lobby while the character stands there drops it into the void and Roblox
  deletes it below -500. Before each shot: show the area, raycast for the real
  floor under the start platform, teleport while anchored, wait ~0.25 s,
  unanchor, then run.
- **Failures:** detect a miss early (4 studs below the platforms), cut
  immediately, retry up to 3 times without fading (fades on every retry looked
  like flashing), then fall back to a camera flyover along the route so the
  shot is never empty.
- **Chained friend for duo shots:** a recolored clone that replays the leader's
  recorded CFrames ~0.7 s later (anchored, no collisions) with matching
  animation states, plus a drawn chain. Hide it the moment the leader misses —
  otherwise it "replays" a fall without the team reset the real game does.
- **Camera:** follow from ~19 studs behind / 9 up with gentle smoothing;
  raycast from the character to the camera and move the camera in front of any
  hit (tunnel roofs, walls); orbit shots for towers with the logo overlay.
- **Calm for video:** walk speed 12 instead of 16, a 0.12 s beat after landing,
  halve particle/trail light emission and shrink lights during the tour.
- **Clean frame:** hide all ScreenGuis, CoreGui and the top bar; disable player
  controls (`PlayerModule:GetControls():Disable()`); restore everything after.
- **Access:** auto-start only when `RunService:IsStudio() and Config.TrailerMode`
  (ship a separate `*_Trailer.rbxl` built with it on, never publish that file);
  in the live game only the owner (`game.CreatorId`) via `/trailer` or Shift+T.
  The server shows off cosmetics (trail, wings) only for the owner / Studio.
- **Diagnostics:** `print("[Trailer] …")` for route sizes, chosen start, and why
  a shot stopped (fell / stuck / no floor, with position). The user reads them
  with F9 → 記錄 (Log) → 用戶端 (Client) after the tour ends; the Output window
  may be hard for them to find.

## Telling the user how to record

1. Open `<Game>_Trailer.rbxl` in Studio, maximise the window.
2. Play; when the character appears press Win+Alt+R; it starts after ~5 s.
3. When the screen is back to normal, Win+Alt+R again. Video is in
   影片 → 擷取. Shift+T replays the tour.
4. Upload to Google Drive / OneDrive with "anyone with the link" and paste the
   link; then edit with `scripts/recording.py`.

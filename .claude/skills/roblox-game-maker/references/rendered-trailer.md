# Rendered trailer (no recording available)

When the user has no footage yet, render a trailer in the container from the
game's REAL level data. Fine for YouTube / TikTok / Reels; not for the Roblox
game page (not real in-experience footage) and never call it 「實機」.

Files in `assets/rendered-trailer/`:

- `export_levels.luau` — Lune script: generates today's courses with the shared
  generator, BFS jump path start→finish, writes pieces + colors + sky + path to
  `levels.json`. Preprocess shared modules first (rewrite
  `require(script.Parent.X)` → `require("./X")` and inject `Color3, Enum` from
  `@lune/roblox`, exactly like `tests/run.sh`).
- `index.html` + `trailer.js` — three.js (pin `three@0.160.0` via npm, served
  with `python3 -m http.server`): builds the boxes per kind/color, landmark,
  sky dome, blocky avatars with run/jump/climb poses, jump-arc timeline from the
  path, chain between two runners, fire / galaxy sprite trails, follow and
  orbit cameras, bilingual captions in DOM (Noto Sans TC + Fredoka from Google
  Fonts). `window.renderAt(t)` is deterministic.
- `stills.js` — render a few times to PNG for a quick look (always check a
  contact sheet before the full render).
- `render.js` — frame-by-frame JPEG capture (`?w=1080&h=1920` or `1920x1080`),
  then `ffmpeg -framerate 30 -i f%05d.jpg -i music.wav -c:v libx264 -crf 18
  -pix_fmt yuv420p -shortest out.mp4`. Chromium flags:
  `--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader`.

Music: `scripts/music.py out.wav <seconds> <cut times>`.

Lessons: captions must not wrap a single character onto its own line (use
`<br>`), keep emoji with the text, centre badges with margin:auto (a pop-in
`transform` overrides translateX), additive white fire looks blown out, night
levels need more ambient light.

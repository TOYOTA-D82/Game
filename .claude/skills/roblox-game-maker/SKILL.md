---
name: roblox-game-maker
description: Roblox遊戲製作 — end-to-end help for making, publishing and promoting a Roblox game with Rojo + Luau, then producing promo videos and marketing copy. Use this skill whenever the user talks about a Roblox game, Roblox Studio, Rojo, Luau scripts, game passes / developer products, publishing or making a Roblox experience public, an in-game recording tour, cutting or editing a Studio / Roblox screen recording, a Roblox game-page video or thumbnail, a trailer or 宣傳影片, or YouTube Shorts / TikTok / Reels 文案 for a game — even if they don't say "skill" or name every step (e.g. "幫我剪這支遊戲影片", "幫我寫 Shorts 文案", "上傳 Roblox 跳錯誤", "我想加一個新關卡").
---

# Roblox 遊戲製作 (Roblox game maker)

A workflow for a non-programmer who wants a polished, money-making Roblox game
without touching code, plus the trailer and copy to promote it. You do the
building, testing, video editing and writing; the user clicks a few buttons in
Roblox Studio / Creator Hub.

## Who you're working with

- Usually a Traditional Chinese (Taiwan) speaker with little coding background.
  Reply in 台灣繁體中文, short and concrete. Name UI items in both languages,
  e.g. 「營利（Monetization）」, because their Studio / Creator Hub may be in
  Chinese and labels move between versions.
- They want "最高品質" and they notice when something doesn't match its
  description (an effect that doesn't do what the shop text says, a teammate
  who falls without the team resetting). Make features do exactly what their
  text claims, and say plainly what you could not verify.
- You cannot run Roblox in the cloud container. Say so before they test, ask for
  screenshots / F9 logs when something looks wrong, and build in diagnostics
  (`print("[Feature] ...")`) so their report tells you the cause.

## The pieces

| Task | Read |
|---|---|
| Build or change the game (Rojo project, Luau, tests, publish) | `references/game-dev.md` |
| Creator Hub chores: products, passes, IDs, publishing, going public, private servers, video uploads | `references/publishing.md` |
| An automatic in-game recording tour so the user can record real footage without playing | `references/recording-tour.md` |
| Editing a recording the user sends (cut, crop Studio UI, music, Roblox / YouTube / Shorts exports) | "Editing a recording" below + `scripts/` |
| Trailer without any recording (rendered from real level data, for social media only) | `references/rendered-trailer.md` |
| Titles, descriptions, hashtags, pinned comments | `references/promo-copy.md` |

Read only the reference you need for the current request.

## Working rules that saved time before

1. **Ship real things, verify what you can.** Run the project's tests and
   linters after every change, rebuild the `.rbxl`, commit and push. For anything
   Roblox-only (feel, camera, effects), tell the user exactly what to look at.
2. **Never publish or spend on the user's behalf without an explicit yes.**
   Uploading a place version, deleting assets, or anything charged needs their
   clear go-ahead. API keys go through the secure credential form
   (request_credential), never pasted into chat; if they paste one anyway, use
   it only for what they asked, don't store it in files, and remind them to
   rotate it.
3. **Honesty about footage.** Roblox game-page videos and thumbnails must show
   real in-experience content (logo/branding overlays are fine). A trailer
   rendered from level data is fine for YouTube/TikTok but not for the Roblox
   page, and its titles must not say 「實機」.
4. **Keep the game fair.** Nothing purchasable should buy leaderboard placings
   (e.g. items disabled in a timed challenge), and every level must be beatable
   without paying; the test suite proves it.

## Editing a recording (the flow the user liked)

The user records with Win+Alt+R (Xbox Game Bar) in Studio and shares a link
(Google Drive / OneDrive / SharePoint "anyone with the link"). Then:

1. **Download** into its own scratch folder. For SharePoint/OneDrive share links,
   follow the link with a cookie jar, then fetch
   `/_layouts/15/download.aspx?SourceUrl=<path from the redirect>` with the same
   cookies. Google Drive: `https://drive.google.com/uc?export=download&id=<id>`.
2. **Inspect**: `python3 scripts/recording.py inspect <video> <workdir>` writes a
   1-fps contact sheet with timestamps, a list of scene cuts, and two full-size
   frames. Look at them (Read the PNGs). Measure the game viewport inside the
   Studio window from a full frame (toolbars on top, Explorer on the right,
   command bar at the bottom) and pick a 16:9 crop inside it that also leaves
   out the Roblox menu buttons in the top-left.
3. **Decide what to keep** with the user's wishes first (e.g. "刪掉火山跟外太空"),
   then remove anything that hurts watching: loading/black screens, the lobby
   before and after the tour, HUD frames, the camera clipping into walls or
   trees, blown-out flashes, retries. Zoom in on suspicious spans with
   `python3 scripts/recording.py zoom <video> <start> <end> <out.png>`
   (4 fps, timestamped) before cutting. A jump cut inside one level is fine.
4. **Cut**: `python3 scripts/recording.py cut <video> <out_dir> --crop W:H:X:Y
   --keep "5.3-8.8,8.8-10.9,..." --short "5.3-8.0,..." --title "..."
   --tagline "..." --search "..."` produces:
   - `full_16x9.mp4` (YouTube), `short_16x9.mp4` (≤30 s),
   - `roblox_1080p.mp4` and `roblox_720p.mp4` (square pixels, ≤15 Mbps, ≤60 s,
     16:9: Roblox rejects non-square pixel aspect as "超過 1920x1080"),
   - `shorts_9x16.mp4` (blurred background, footage in the middle, title on
     top, search pill at the bottom),
   - fresh synthesized music with a hit on every level change (no copyright
     issues; the original audio is dropped).
   It prints each file's resolution / pixel aspect / bitrate / duration so you
   can confirm they meet the Roblox limits before the user spends one of their
   3 monthly uploads.
5. **Check** one frame per kept segment of each output (contact sheet) before
   sending. Send files with SendUserFile and give a short table: file, length,
   where to use it. Remind them to turn the share link back to private.

## Writing copy

Follow `references/promo-copy.md`: hook-first title (≤40 visible chars),
keyword-first description, 3–5 hashtags, a choice-question pinned comment, an
English variant, and posting tips (only post after the game is public; first
hour engagement; series instead of reposts). Match claims to what's actually in
the video and game.

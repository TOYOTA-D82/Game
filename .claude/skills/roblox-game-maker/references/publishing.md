# Creator Hub chores (products, publishing, going public, videos)

Creator Hub: https://create.roblox.com/dashboard/creations (中文:「創作者中心」).
Labels move between versions; describe the location and ask for a screenshot
if the user can't find it.

## Products

- **Game passes (通行證)**: one-time, permanent (VIP, trails). Category "Passes".
- **Developer products (開發者產品)**: consumable, buyable again (item packs,
  coins, skips, a once-only starter pack enforced in code). Category: **Others**
  or custom shop categories (道具 / 禮包 / 金幣). Never "Passes".
- Developer products can't be deleted; a wrong category is just changed in the
  item's Category dropdown. An unused product does nothing if its id isn't in
  the config.
- Put ids into `Config.GamePasses` / `Config.Products`. With id = 0 the game
  grants them free in Studio; with real ids Studio shows a free test purchase.
  Read live prices and icons with `MarketplaceService:GetProductInfo` so price
  changes in the dashboard need no code change.

## Going public (2025+ rules, check the live docs)

- New creators see 「新加入的創作者…需要等待」: the account must be ≥ 2 days
  old and pass an age check (face estimation or ID). All-ages release also needs
  2FA plus Premium for 2 months or a refundable 1,000 Robux fee, and passing
  review. Until then 「管理受眾」 is grey.
- Fill the content questionnaire first (受眾 → 成熟度與合規).
- Private servers (私人伺服器) live under 受眾 → 存取設定 (Access Settings),
  not under 營利, and require the game to be public first.

## Game-page videos and thumbnails

- Must be real in-experience footage; logo/branding overlays are allowed;
  reviewed before showing; 3 video uploads a month (failed ones may count).
- Upload dialog limits seen: .mp4/.mov, ≤ 100 MB, ≤ 60 s, ~15 Mbps recommended,
  640×360 to 1920×1080, 16:9. A 1920×1080 file with non-square pixel aspect
  (SAR like 1287:1288) is rejected as 「超過 1920x1080」 — export with
  `setsar=1`. `scripts/recording.py cut` does this and prints a spec check.
- Keep the Roblox version ≤ 30 s and lead with the most distinctive mechanic.

## Marketing timing

Don't push videos or ads until the game is public — viewers who can't join
leave angry comments. Then: short videos daily-ish, bring 5–10 friends in the
first week (Roblox ranks on engagement), small Roblox ads only after the game
is stable.

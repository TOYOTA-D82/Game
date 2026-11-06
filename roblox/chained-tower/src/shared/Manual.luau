--!strict
-- The in-game guide book (📖 button). Players open it only if they want to.
-- Four tabs: how to play, every block you can meet, items, points & rewards.
-- Numbers come from Config so the book never disagrees with the game.

local Config = require(script.Parent.Config)

local Manual = {}

export type Entry = {
	icon: string, -- emoji shown on the swatch
	color: Color3?, -- swatch colour = what the block looks like in the game
	en: { string }, -- { title, text }
	zh: { string },
}
export type Tab = { id: string, en: string, zh: string, entries: { Entry } }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local daily = Config.Daily
local P = Config.Points
local tiers = P.perMinuteByPlace
local function rate(i: number): number
	return tiers[i].points
end

Manual.Tabs = {
	{
		id = "play",
		en = "🎮 How to play",
		zh = "🎮 怎麼玩",
		entries = {
			{
				icon = "🏆",
				en = { "The goal", "Get from the start to the 🏆 at the end of each level. A level is made of sections: jumps, buildings, climbs and traps. Numbered flags are checkpoints." },
				zh = { "目標", "從起點一路闖到終點的 🏆。每一關由好幾段組成：跳台、建築、攀爬、陷阱。路上有編號旗子的是檢查點。" },
			},
			{
				icon = "🧍",
				color = rgb(70, 150, 255),
				en = { "Solo world (blue portal)", "Play alone with no chain. Fall off and you go straight back to your last checkpoint." },
				zh = { "單人世界（藍色傳送門）", "一個人玩、沒有鎖鏈。掉下去就直接回到上一個檢查點。" },
			},
			{
				icon = "🔗",
				color = rgb(160, 90, 255),
				en = {
					"Team world (purple portal)",
					("Duo: two players chained at the ankle (%d studs). Squad: four players chained to one iron ball. You win and lose together."):format(Config.Modes.duo.chainLength),
				},
				zh = {
					"組隊世界（紫色傳送門）",
					("雙人：兩個人腳踝綁在一起（鏈長 %d 格）。四人：四個人一起綁在中間的鐵球上。全隊一起過關、一起失敗。"):format(Config.Modes.duo.chainLength),
				},
			},
			{
				icon = "🪢",
				en = {
					"Falling in a team",
					("You hang on the chain instead of resetting. You climb up slowly by yourself; hold Jump or the ⬆ button to climb fast. Teammates walking away pull you up. Only when EVERYONE is off the ground for %.1f s does the team go back to the checkpoint."):format(Config.AllFallSeconds),
				},
				zh = {
					"組隊時掉下去",
					("不會馬上重來，而是吊在鎖鏈上：自己會慢慢往上爬，按住跳躍或「⬆ 爬上去」爬更快；隊友往反方向走也能把你拉上來。全隊都離地超過 %.1f 秒，才會一起回檢查點。"):format(Config.AllFallSeconds),
				},
			},
			{
				icon = "📅",
				en = { "A new route every day", "Every day at 08:00 (Taiwan) every level gets a brand-new route. Level 1 is open first; clear a level to open the next one for today." },
				zh = { "每天都是新路線", "每天台灣早上 8 點，每一關都會換成全新的路線。每天從第 1 關開始，通過一關才會開下一關。" },
			},
			{
				icon = "🚪",
				en = { "Gates and leaving", "In a world, walk onto a level's gate pad to start it (team: wait for the others on the pad). Press 🚪 Leave level any time to go back to the world." },
				zh = { "關卡門和離開", "在世界島上走到關卡門前的平台就會開始（組隊要等隊友一起站上去）。隨時可以按「🚪 離開關卡」回到世界島。" },
			},
		},
	},
	{
		id = "blocks",
		en = "🧱 Blocks",
		zh = "🧱 方塊",
		entries = {
			{
				icon = "🟩",
				color = rgb(120, 200, 120),
				en = { "Normal platform", "Safe to stand on. Its colour changes with each level's theme." },
				zh = { "一般平台", "可以放心站。顏色會跟著每一關的主題變。" },
			},
			{
				icon = "🚩",
				color = rgb(255, 210, 70),
				en = { "Checkpoint", "The ring with a number and flag. Reach it and that's where you come back if you fall." },
				zh = { "檢查點", "有數字和旗子的平台。碰到之後，掉下去就會回到這裡。" },
			},
			{
				icon = "🔥",
				color = rgb(255, 90, 20),
				en = { "Lava", "Glowing cracked rock. Touch it and you go back to the checkpoint. In a team the fire runs along the chain and burns EVERYONE." },
				zh = { "岩漿", "發光的裂紋岩石。碰到就回檢查點。組隊時火會順著鎖鏈燒到全隊，大家一起回去。" },
			},
			{
				icon = "⬆",
				color = rgb(90, 255, 140),
				en = { "Jump pad", "Bright glowing pad. Step on it and it launches you high into the air." },
				zh = { "彈跳墊", "發亮的墊子。踩上去會把你彈得很高。" },
			},
			{
				icon = "↔",
				color = rgb(230, 210, 120),
				en = { "Moving platform", "Yellowish platform that slides back and forth. Stand on it and it carries you. Time your jump." },
				zh = { "移動平台", "偏黃色、會來回移動的平台。站上去會帶著你走，看準時機再跳。" },
			},
			{
				icon = "💥",
				color = rgb(150, 110, 80),
				en = { "Crumbling stone", "Grey-brown rough stone. When you step on it, it turns orange, shakes and falls apart about a second later. It comes back after a few seconds. Don't stop on it!" },
				zh = { "碎裂石", "灰褐色、表面粗糙的石頭。踩上去會變橘、開始抖，大約 1 秒後碎掉，幾秒後才會恢復。不要停在上面！" },
			},
			{
				icon = "👣",
				color = rgb(170, 230, 255),
				en = { "Fragile glass", "Light-blue glass with a 👣 number: how many more different people it can hold. It holds 2; the 3rd person breaks it. Squads must plan who crosses." },
				zh = { "易碎玻璃", "淺藍色玻璃，上面的 👣 數字是還能承受幾個不同的人。最多 2 人，第 3 個人踩上去就會破。四人隊要先商量誰走這裡。" },
			},
			{
				icon = "👻",
				color = rgb(220, 225, 235),
				en = { "Vanishing glass", "Pale see-through glass. Half a second after you touch it, it fades away; it comes back a few seconds later. Keep moving." },
				zh = { "消失玻璃", "淡白色半透明玻璃。碰到半秒後會消失，幾秒後才回來。踩了就要繼續走。" },
			},
			{
				icon = "🧊",
				color = rgb(190, 235, 255),
				en = { "Ice", "You keep sliding after you let go. Some ice floors have holes, so slow down early." },
				zh = { "冰面", "放開方向鍵後還會一直滑。有些冰面有破洞，要提早減速。" },
			},
			{
				icon = "⏪",
				color = rgb(45, 45, 50),
				en = { "Conveyor belt", "Dark metal belt with moving yellow stripes. It pushes you backwards or sideways; stand still and it carries you off the edge. Jump to escape." },
				zh = { "輸送帶", "深色金屬帶、上面有黃色條紋在動。會把你往後或往旁邊送，站著不動就會被送到邊緣推下去，跳起來就能脫離。" },
			},
			{
				icon = "🌊",
				color = rgb(50, 150, 255),
				en = { "Water current / rapids", "Blue water with white foam. A strong current pushes you along. In a team the chain can hold you while teammates pull you back." },
				zh = { "水流／急流", "有白色浪花的藍色水面。強勁的水流會一直推你。組隊時鎖鏈會拉住你，隊友頂住就能把你拉回來。" },
			},
			{
				icon = "🌀",
				color = rgb(235, 70, 70),
				en = { "Spinning bar", "A glowing red bar turning around a post. It knocks you flying: jump over it or wait for a gap." },
				zh = { "旋轉棒", "繞著柱子轉的紅色發光長棒。被打到會飛出去，要跳過去或等空檔。" },
			},
			{
				icon = "🧱",
				color = rgb(255, 170, 40),
				en = { "Flying walls", "Walls that slide at you. Low ORANGE walls: jump over. Tall RED walls: step aside to dodge." },
				zh = { "飛來的牆", "會朝你滑過來的牆。矮的橘色牆：跳過去。高的紅色牆：往旁邊閃開。" },
			},
			{
				icon = "🔨",
				color = rgb(190, 120, 70),
				en = {
					"Cracked wall (shortcut)",
					("Cobblestone wall with a crack icon. It blocks a shortcut: take the long way round, or smash it with 🔨 from up to %d studs away. It grows back after %d s."):format(Config.SmashRange, Config.SmashRespawnSeconds),
				},
				zh = {
					"裂縫牆（捷徑）",
					("有裂縫圖示的石牆，擋住一條捷徑。可以繞遠路，或在 %d 格內用 🔨 破壞錘打碎，%d 秒後會長回來。"):format(Config.SmashRange, Config.SmashRespawnSeconds),
				},
			},
			{
				icon = "🪜",
				color = rgb(200, 200, 210),
				en = { "Ladder / truss", "Silver lattice. Walk into it and you climb it automatically." },
				zh = { "梯子／鐵架", "銀色格子架。走過去貼著它就會自動往上爬。" },
			},
			{
				icon = "🏚",
				en = { "Buildings, tunnels and shafts", "Some routes go INTO buildings: walk through the door, climb the ladder inside a tower, run along rooftops, through tunnels and arches." },
				zh = { "建築、隧道、升降井", "有些路線會走進建築裡：從門口進去、在塔裡爬梯子、跑屋頂、穿過隧道和拱門。" },
			},
			{
				icon = "⛰",
				en = { "Scenery", "Mountains, icebergs, pyramids and other big background objects are scenery. They are solid, but landing on them counts as falling off the course." },
				zh = { "背景景物", "山、冰山、金字塔這類大型背景是裝飾。碰得到，但掉到上面一樣算是掉出路線。" },
			},
		},
	},
	{
		id = "items",
		en = "🎒 Items",
		zh = "🎒 道具",
		entries = {
			{
				icon = "🔓",
				en = {
					"Unchain (team only)",
					("Frees the whole team from the chain for %d s. Free every day: %d (VIP +%d, Premium +%d)."):format(Config.UnchainSeconds, daily.unchain, daily.vipBonusUnchain, daily.premiumBonusUnchain),
				},
				zh = {
					"解除束縛（組隊限定）",
					("讓全隊暫時不被鎖鏈綁住 %d 秒。每天免費 %d 個（VIP 多 %d 個、Premium 多 %d 個）。"):format(Config.UnchainSeconds, daily.unchain, daily.vipBonusUnchain, daily.premiumBonusUnchain),
				},
			},
			{
				icon = "🔨",
				en = { "Smash hammer", ("Breaks a cracked wall in front of you to take the shortcut. Free every day: %d (VIP +%d)."):format(daily.smash, daily.vipBonusSmash) },
				zh = { "破壞錘", ("打碎前方的裂縫牆，走捷徑。每天免費 %d 個（VIP 多 %d 個）。"):format(daily.smash, daily.vipBonusSmash) },
			},
			{
				icon = "⏭",
				en = { "Skip", "Stuck on one section? Skip it (in a team, for everyone). It's in the shop, and a small card offers it after you fail the same section several times." },
				zh = { "跳過", "卡在某一段？直接跳過（組隊時全隊一起跳）。商店買得到；同一段失敗好幾次後，右側也會滑出小卡片提醒。" },
			},
			{
				icon = "🪙",
				en = { "Coins and trails", "Climbing, clearing levels and daily challenges give coins. Spend them on run trails in ✨ Trails. Every trail has its own effect." },
				zh = { "金幣和特效", "爬關卡、通關、完成每日任務都會拿到金幣，可以在「✨ 特效」買跑步特效，每個特效的效果都不一樣。" },
			},
			{
				icon = "✅",
				en = { "No need to buy", "Every level can be cleared without buying anything. Items only make it faster or easier." },
				zh = { "不買也能過", "每一關都不用花錢就能通過，道具只是讓你更快、更輕鬆。" },
			},
		},
	},
	{
		id = "points",
		en = "⭐ Points",
		zh = "⭐ 積分",
		entries = {
			{
				icon = "⏱",
				en = {
					"Points every minute",
					("Clear 1 level today and you earn points every minute, anywhere, even standing still. How many depends on yesterday's final place: #1 +%d, #2 +%d, #3 +%d, #4-10 +%d, #11-50 +%d, #51-100 +%d, everyone else +%d."):format(rate(1), rate(2), rate(3), rate(4), rate(5), rate(6), P.perMinuteDefault),
				},
				zh = {
					"每分鐘加分",
					("今天通過 1 關後，每分鐘自動加分，在哪裡、站著不動都算。每分鐘幾分看昨天的最終名次：第 1 名 +%d、第 2 名 +%d、第 3 名 +%d、4–10 名 +%d、11–50 名 +%d、51–100 名 +%d、其他人 +%d。"):format(rate(1), rate(2), rate(3), rate(4), rate(5), rate(6), P.perMinuteDefault),
				},
			},
			{
				icon = "💤",
				en = { "Time away counts", ("When you come back you get points for the time you were away (up to %d hours a day)."):format(P.offlineMaxMinutes // 60) },
				zh = { "離線也算", ("下次回來時，會把你離開的時間補給你（每天最多 %d 小時）。"):format(P.offlineMaxMinutes // 60) },
			},
			{
				icon = "➕",
				en = {
					"Bonus points",
					("Each checkpoint +%d. Clearing a level: %d + %d x level number, x%d the first time today, +%d%% if you beat the par time. Duo x%.1f, squad x%.1f."):format(P.checkpoint, P.clearBase, P.clearPerLevel, P.firstClearMultiplier, math.floor(P.fastBonus * 100), P.modeMultiplier.duo, P.modeMultiplier.squad),
				},
				zh = {
					"額外加分",
					("每個檢查點 +%d。通關：%d + %d × 關卡編號，當天第一次 ×%d，比標準時間快再 +%d%%。雙人 ×%.1f、四人 ×%.1f。"):format(P.checkpoint, P.clearBase, P.clearPerLevel, P.firstClearMultiplier, math.floor(P.fastBonus * 100), P.modeMultiplier.duo, P.modeMultiplier.squad),
				},
			},
			{
				icon = "👑",
				en = { "Daily top 3", "Today's points reset every day at 08:00. The top 3 get a crown or name tag, a special trail and bonus coins for 1 day. Same score: whoever got there first ranks higher." },
				zh = { "每日前三名", "今日積分每天早上 8 點歸零。前三名拿到 1 天的皇冠或名牌、專屬特效和金幣加成。同分時，先達到的人排前面。" },
			},
			{
				icon = "🪽",
				en = { "Weekly top 10", "Today's points also add up into the week (resets Monday 08:00). The top 10 wear glowing, flapping wings for a week; #1 also gets a halo." },
				zh = { "每週前十名", "今日積分也會累加進本週積分（每週一早上 8 點歸零）。前十名拿到 1 週會拍動、會發光的翅膀，第 1 名還有光環。" },
			},
			{
				icon = "🚫",
				en = { "Can't be bought", "Rewards come only from your place. They can't be bought and disappear when time is up." },
				zh = { "買不到", "這些獎勵只能靠名次拿到，商店買不到，時間到就會消失。" },
			},
		},
	},
} :: { Tab }

return Manual

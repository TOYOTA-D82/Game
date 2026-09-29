// 角色資料表：要新增角色，只要在 LIST 加一行就好。
// mk(id, 名字, 稱號, 稀有度1~5, 定位, 衣服色, 髮色, 技能類型, 技能名)
// 定位：atk 輸出型 / tank 坦克型 / fast 速度型 / bal 均衡型
// 技能類型：rush 突進 / fire 貫穿火球 / burst 範圍爆發 / barrage 連射 / heal 治療
(function () {
  const SKILL = {
    rush:    { cd: 4, mult: 2.2 },
    fire:    { cd: 5, mult: 2.5 },
    burst:   { cd: 6, mult: 2.6 },
    barrage: { cd: 6, mult: 0.9 },
    heal:    { cd: 9, mult: 0.6 },
  };
  const ROLE = {
    atk:  { hp: 0.9, atk: 1.2, spd: 1.0 },
    tank: { hp: 1.3, atk: 0.9, spd: 0.9 },
    fast: { hp: 0.9, atk: 1.0, spd: 1.15 },
    bal:  { hp: 1.0, atk: 1.0, spd: 1.0 },
  };

  function mk(id, name, title, r, role, color, hair, type, skName) {
    const k = ROLE[role];
    return {
      id, name, title, rarity: r, role, color, hair,
      hp: Math.round((80 + r * 25) * k.hp),
      atk: Math.round((9 + r * 4) * k.atk),
      spd: Math.round((200 + r * 6) * k.spd),
      skill: { type, name: skName, cd: SKILL[type].cd, mult: SKILL[type].mult },
    };
  }

  const LIST = [
    // ★1
    mk('ino', '井野', '心轉身的少女', 1, 'bal', '#8e5bd0', '#f6e27a', 'barrage', '手裡劍連射'),
    mk('iruka', '伊魯卡', '忍者學校老師', 1, 'tank', '#3b6fb6', '#4a3020', 'rush', '教鞭突擊'),
    mk('konohamaru', '木葉丸', '三代目的孫子', 1, 'fast', '#e0872b', '#3a2a1a', 'burst', '色誘之術'),
    mk('karin', '香燐', '感知忍者', 1, 'bal', '#c94a4a', '#d23b3b', 'heal', '查克拉補給'),
    // ★2
    mk('tenten', '天天', '忍具使', 2, 'atk', '#d6588a', '#5a3520', 'barrage', '忍具連射'),
    mk('choji', '丁次', '倍化之術', 2, 'tank', '#4f9a4f', '#a0522d', 'burst', '肉彈戰車'),
    mk('kiba', '牙', '牙通牙', 2, 'fast', '#8a8a8a', '#5a3a20', 'rush', '牙通牙'),
    mk('shino', '志乃', '寄壞蟲使', 2, 'bal', '#4c5a3b', '#2b2b2b', 'burst', '寄壞蟲之術'),
    mk('temari', '手鞠', '風遁使', 2, 'atk', '#7a3f8f', '#e8d27a', 'fire', '風遁·鎌鼬'),
    mk('kankuro', '勘九郎', '傀儡師', 2, 'bal', '#3a2a4a', '#3a2a1a', 'barrage', '傀儡操演'),
    mk('shizune', '靜音', '醫療忍者', 2, 'bal', '#2b2b3a', '#1a1a1a', 'heal', '醫療忍術'),
    mk('kurenai', '紅', '幻術使', 2, 'bal', '#a83232', '#1a1a1a', 'burst', '幻術·樹縛'),
    mk('sai', '佐井', '超獸偽畫', 2, 'atk', '#2a2a2a', '#1a1a1a', 'barrage', '超獸偽畫'),
    mk('suigetsu', '水月', '斬首大刀', 2, 'atk', '#6a9ad0', '#cfe8ff', 'rush', '首切大刀'),
    // ★3
    mk('hinata', '雛田', '白眼公主', 3, 'bal', '#7a70b8', '#2a2a55', 'burst', '八卦六十四掌'),
    mk('neji', '寧次', '日向天才', 3, 'atk', '#dcdcdc', '#3a2a1a', 'burst', '八卦回天'),
    mk('rocklee', '小李', '體術達人', 3, 'fast', '#2f8f4f', '#1a1a1a', 'rush', '表蓮華'),
    mk('shikamaru', '鹿丸', '天才軍師', 3, 'bal', '#4a6a4a', '#2a2a2a', 'barrage', '影子模仿之術'),
    mk('sakura', '小櫻', '怪力醫療忍者', 3, 'bal', '#d95b8a', '#f4a0b8', 'heal', '創傷治癒'),
    mk('hidan', '飛段', '不死的邪教徒', 3, 'atk', '#2a2a2a', '#d8d8d8', 'rush', '詛咒儀式'),
    mk('zabuza', '再不斬', '鬼人', 3, 'atk', '#5a6a7a', '#2a2a2a', 'rush', '斬首大刀'),
    mk('haku', '白', '冰遁少年', 3, 'fast', '#e8a8c0', '#2a1a1a', 'barrage', '魔鏡冰晶'),
    mk('asuma', '阿斯瑪', '猿飛師父', 3, 'atk', '#3a3a3a', '#2a2a2a', 'fire', '風遁·鎮'),
    mk('anko', '紫', '蛇之女', 3, 'fast', '#b58a4a', '#4a2a5a', 'barrage', '潛影蛇手'),
    mk('yamato', '大和', '木遁使', 3, 'tank', '#3a5a3a', '#4a3020', 'burst', '木遁·木龍'),
    mk('jugo', '重吾', '咒印之力', 3, 'tank', '#c9a24a', '#e0873a', 'burst', '咒印狂化'),
    // ★4
    mk('naruto', '鳴人', '木葉的吊車尾', 4, 'atk', '#f28a1e', '#f5d442', 'burst', '螺旋丸'),
    mk('sasuke', '佐助', '宇智波的復仇者', 4, 'atk', '#2b3d7a', '#151515', 'rush', '千鳥'),
    mk('kakashi', '卡卡西', '拷貝忍者', 4, 'bal', '#3a4a6a', '#c8c8d0', 'rush', '雷切'),
    mk('gaara', '我愛羅', '砂之風影', 4, 'tank', '#a83a32', '#b5301f', 'burst', '砂瀑送葬'),
    mk('deidara', '迪達拉', '爆破藝術家', 4, 'atk', '#2a2a3a', '#f0d060', 'burst', '藝術就是爆炸'),
    mk('sasori', '蠍', '赤砂', 4, 'bal', '#4a2a2a', '#b0332a', 'barrage', '傀儡百機操演'),
    mk('kisame', '鬼鮫', '霧隱怪人', 4, 'tank', '#2a3a5a', '#3a6a9a', 'rush', '鮫肌斬擊'),
    mk('kakuzu', '角都', '五顆心臟', 4, 'tank', '#3a2a2a', '#2a2a2a', 'fire', '風遁·圧害'),
    mk('konan', '小南', '紙之天使', 4, 'fast', '#2a2a3a', '#3a5a9a', 'barrage', '紙手裡劍'),
    mk('guy', '凱', '木葉蒼綠猛獸', 4, 'fast', '#1f9a4a', '#1a1a1a', 'rush', '八門遁甲'),
    mk('killerbee', '艾', '八尾人柱力', 4, 'atk', '#6a5a3a', '#e8e8e8', 'rush', '雷遁·雷犁熱刀'),
    mk('tobirama', '扉間', '二代目火影', 4, 'bal', '#3a5a9a', '#d8d8d8', 'fire', '水遁·水龍彈'),
    mk('sarutobi', '三代目', '教授之神', 4, 'bal', '#c95a2a', '#4a3a2a', 'fire', '火遁·豪火滅卻'),
    mk('danzo', '團藏', '根之首領', 4, 'atk', '#4a4a4a', '#1a1a1a', 'fire', '風遁·真空大突破'),
    mk('kabuto', '藥師兜', '白蛇的眼鏡', 4, 'fast', '#6a4a8a', '#c8c8d0', 'rush', '查克拉手術刀'),
    // ★5
    mk('itachi', '鼬', '宇智波天才', 5, 'atk', '#232323', '#151515', 'fire', '天照'),
    mk('jiraiya', '自來也', '好色仙人', 5, 'atk', '#b53a3a', '#f0f0f0', 'fire', '仙法·蛙口勃隆'),
    mk('tsunade', '綱手', '傳說的三忍', 5, 'tank', '#3f8f6a', '#f0d868', 'heal', '創造再生'),
    mk('orochimaru', '大蛇丸', '三忍·蛇', 5, 'atk', '#7a6a9a', '#151515', 'barrage', '潛影多蛇手'),
    mk('minato', '四代目', '木葉黃色閃光', 5, 'fast', '#e0e0e0', '#f5d442', 'rush', '飛雷神之術'),
    mk('pain', '佩恩', '六道之力', 5, 'atk', '#3a2a3a', '#e0782a', 'burst', '神羅天征'),
    mk('obito', '帶土', '面具男', 5, 'bal', '#5a3a6a', '#2a2a2a', 'burst', '神威'),
    mk('madara', '斑', '宇智波傳說', 5, 'atk', '#7a2a2a', '#1a1a1a', 'burst', '須佐能乎'),
    mk('hashirama', '柱間', '初代目火影', 5, 'tank', '#5a3a2a', '#3a2a1a', 'burst', '木遁·樹界降誕'),
    mk('kaguya', '輝夜', '始祖', 5, 'atk', '#f0f0f0', '#e8e0d8', 'burst', '無限月讀'),
  ];

  window.SKILL = SKILL;
  window.ROSTER = LIST;
})();

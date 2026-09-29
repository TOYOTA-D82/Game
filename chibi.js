// Q 版角色繪圖：全部用程式畫，沒有外部圖檔。
// 要幫角色加外觀，在 STYLE 加一行：id: [髮型, 護額顏色|null, '配件 配件']
// 髮型：spiky 刺蝟頭 / long 長髮 / pony 馬尾 / bun 雙丸子 / short 短髮 / wild 長刺髮 / bowl 鍋蓋頭 / hood 頭巾 / bald 光頭
// 配件：whiskers 鬍鬚 / mask 面罩 / glasses 眼鏡 / marks 臉部紋路 / sharingan 紅眼 / cloak 斗篷 / gourd 葫蘆 / sword 背劍 / scarf 圍巾 / bandage 繃帶
(function () {
  const L = '#2a4fa0'; // 木葉護額
  const STYLE = {
    _d: ['hood', null, 'mask'],
    ino: ['pony', L, ''], iruka: ['pony', L, 'marks'], konohamaru: ['spiky', null, 'scarf'], karin: ['long', null, 'glasses'],
    tenten: ['bun', L, ''], choji: ['short', L, ''], kiba: ['spiky', L, 'marks'], shino: ['short', null, 'glasses mask'],
    temari: ['pony', L, ''], kankuro: ['hood', null, 'marks'], shizune: ['short', null, ''], kurenai: ['long', null, ''],
    sai: ['short', null, ''], suigetsu: ['spiky', null, 'sword'],
    hinata: ['long', L, ''], neji: ['long', L, ''], rocklee: ['bowl', L, ''], shikamaru: ['pony', L, ''],
    sakura: ['short', '#d33', ''], hidan: ['short', '#888', 'cloak'], zabuza: ['short', '#8a94a8', 'bandage sword'],
    haku: ['long', null, ''], asuma: ['short', L, ''], anko: ['pony', L, ''], yamato: ['short', L, ''], jugo: ['spiky', null, ''],
    naruto: ['spiky', L, 'whiskers'], sasuke: ['spiky', L, ''], kakashi: ['spiky', L, 'mask'], gaara: ['short', null, 'gourd marks'],
    deidara: ['pony', L, 'cloak'], sasori: ['short', null, 'cloak'], kisame: ['spiky', L, 'cloak sword'], kakuzu: ['hood', null, 'cloak mask'],
    konan: ['bun', null, 'cloak'], guy: ['bowl', L, ''], killerbee: ['short', L, 'sword glasses'], tobirama: ['spiky', L, ''],
    sarutobi: ['short', null, ''], danzo: ['short', L, ''], kabuto: ['pony', L, 'glasses'],
    itachi: ['long', L, 'sharingan marks cloak'], jiraiya: ['wild', L, 'marks'], tsunade: ['pony', null, ''],
    orochimaru: ['long', null, 'marks'], minato: ['spiky', L, ''], pain: ['spiky', null, 'cloak'], obito: ['spiky', null, 'sharingan mask'],
    madara: ['wild', null, 'sharingan cloak'], hashirama: ['long', L, ''], kaguya: ['long', null, 'marks'],
  };

  function rr(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath(); ctx.fill();
  }
  function dot(ctx, x, y, r) { ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); }

  // 腳底在 (0,0)，朝右；外層已處理翻面與縮放。整體高約 70，與原本判定框相容。
  window.drawChibi = function (ctx, c, o, T) {
    const st = STYLE[c.id] || STYLE._d, hs = st[0], band = st[1], acc = st[2] || '';
    const has = k => acc.indexOf(k) >= 0;
    const w = o.walk ? Math.sin(T * 16) : 0, bob = o.walk ? Math.abs(w) * 2 : 0;
    const skin = '#ffe2c6', dark = '#2a2233', hy = -50 - bob;

    ctx.fillStyle = 'rgba(0,0,0,.25)'; ctx.beginPath(); ctx.ellipse(0, 0, 20, 5, 0, 0, 7); ctx.fill();

    // 背後的東西
    if (has('gourd')) { ctx.fillStyle = '#b8894a'; dot(ctx, -19, -30 - bob, 11); ctx.fillStyle = '#8a6230'; ctx.fillRect(-21, -44 - bob, 4, 6); }
    if (has('sword')) { ctx.strokeStyle = '#cfd5e0'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(-14, -12 - bob); ctx.lineTo(10, -62 - bob); ctx.stroke(); }
    if (has('cloak')) { ctx.fillStyle = '#1c1622'; rr(ctx, -18, -38 - bob, 36, 32, 9); ctx.fillStyle = '#c22'; ctx.fillRect(-18, -10 - bob, 36, 3); }
    ctx.fillStyle = c.hair;
    if (hs === 'long' || hs === 'wild') rr(ctx, -19, hy - 4, 38, 36, 14);
    if (hs === 'pony') { ctx.beginPath(); ctx.ellipse(-21, hy - 2, 7, 13, 0.4, 0, 7); ctx.fill(); }

    // 腿、身體、後手
    ctx.fillStyle = dark; rr(ctx, -9 + w * 4, -12, 8, 12, 3); rr(ctx, 1 - w * 4, -12, 8, 12, 3);
    ctx.fillStyle = c.color; rr(ctx, -12, -33 - bob, 24, 24, 7);
    ctx.fillStyle = dark; ctx.fillRect(-12, -18 - bob, 24, 4);
    if (has('scarf')) { ctx.fillStyle = '#d33'; rr(ctx, -11, -36 - bob, 22, 6, 3); }
    ctx.fillStyle = c.color; rr(ctx, -17, -30 - bob, 7, 14, 3);
    ctx.fillStyle = skin; dot(ctx, -13.5, -15 - bob, 3.5);

    // 頭
    ctx.fillStyle = skin; dot(ctx, 0, hy, 17);

    // 頭髮
    ctx.fillStyle = c.hair;
    if (hs !== 'bald') { ctx.beginPath(); ctx.arc(0, hy - 4, 18, Math.PI, 0); ctx.closePath(); ctx.fill(); }
    if (hs === 'spiky' || hs === 'wild') {
      [-14, -7, 0, 7, 14].forEach((x, i) => {
        const tip = hy - 24 - (i % 2 ? 0 : 6) - (hs === 'wild' ? 6 : 0);
        ctx.beginPath(); ctx.moveTo(x - 6, hy - 8); ctx.lineTo(x, tip); ctx.lineTo(x + 6, hy - 8); ctx.fill();
      });
    }
    if (hs === 'bun') { dot(ctx, -13, hy - 21, 6); dot(ctx, 13, hy - 21, 6); }
    if (hs === 'bowl') ctx.fillRect(-18, hy - 6, 36, 7);
    else if (hs !== 'bald' && hs !== 'hood') {
      ctx.beginPath(); ctx.moveTo(-17, hy - 6); ctx.lineTo(-8, hy + 4); ctx.lineTo(-2, hy - 4);
      ctx.lineTo(6, hy + 3); ctx.lineTo(12, hy - 4); ctx.lineTo(17, hy - 6); ctx.closePath(); ctx.fill();
    }
    if (band) {
      ctx.fillStyle = band; ctx.fillRect(-17.5, hy - 9, 35, 6);
      ctx.fillStyle = '#cfd8e8'; ctx.fillRect(2, hy - 9, 12, 6);
    }

    // 臉
    const eyes = [-3, 9], ey = hy + 3;
    eyes.forEach(ex => {
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.ellipse(ex, ey, 4.2, 5, 0, 0, 7); ctx.fill();
      ctx.fillStyle = has('sharingan') ? '#d22' : '#231c2a'; dot(ctx, ex + 1, ey + 0.5, 2.9);
      ctx.fillStyle = '#fff'; dot(ctx, ex + 2, ey - 1, 1);
    });
    ctx.fillStyle = 'rgba(255,120,120,.4)';
    ctx.beginPath(); ctx.ellipse(-8, hy + 10, 3.5, 2, 0, 0, 7); ctx.ellipse(13, hy + 10, 3.5, 2, 0, 0, 7); ctx.fill();
    if (has('marks')) {
      ctx.strokeStyle = '#7a4a4a'; ctx.lineWidth = 1.4; ctx.beginPath();
      eyes.forEach(ex => { ctx.moveTo(ex - 3, ey + 6); ctx.lineTo(ex, ey + 10); });
      ctx.stroke();
    }
    if (has('whiskers')) {
      ctx.strokeStyle = '#6a4a3a'; ctx.lineWidth = 1.2; ctx.beginPath();
      [-8, 13].forEach(cx => [-1, 0, 1].forEach(k => { ctx.moveTo(cx - 4, hy + 10 + k * 3); ctx.lineTo(cx + 4, hy + 10 + k * 3 + k); }));
      ctx.stroke();
    }
    if (has('mask')) { ctx.fillStyle = '#3d4258'; rr(ctx, -16, hy + 6, 32, 12, 5); }
    else if (has('bandage')) { ctx.fillStyle = '#e8e8e8'; rr(ctx, -15, hy + 7, 30, 9, 3); }
    else { ctx.strokeStyle = '#8a4a3a'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(3, hy + 9, 3, 0.2, Math.PI - 0.2); ctx.stroke(); }
    if (has('glasses')) { ctx.strokeStyle = '#333'; ctx.lineWidth = 1.6; eyes.forEach(ex => { ctx.beginPath(); ctx.arc(ex, ey, 6.2, 0, 7); ctx.stroke(); }); }

    // 前手與攻擊
    if (o.atk > 0) {
      ctx.fillStyle = c.color; rr(ctx, 8, -34 - bob, 16, 7, 3);
      ctx.fillStyle = skin; dot(ctx, 25, -31 - bob, 4);
      ctx.strokeStyle = '#e8eef8'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(26, -31 - bob); ctx.lineTo(52, -46 - bob); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,.8)'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(6, -34, 52, -1.0, 0.9); ctx.stroke();
    } else {
      ctx.fillStyle = c.color; rr(ctx, 9, -31 - bob, 7, 14, 3);
      ctx.fillStyle = skin; dot(ctx, 12.5, -15 - bob, 3.5);
    }
  };
})();

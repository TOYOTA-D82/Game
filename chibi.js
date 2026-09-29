// Q 版角色繪圖：全部用程式畫，沒有外部圖檔。
// STYLE 格式：id: [髮型, 護額顏色|null, '配件 配件', {額外設定}]
// 髮型：spiky 刺蝟頭 / long 長髮 / pony 馬尾 / twin 雙馬尾 / bun 雙丸子 / short 短髮 / wild 長刺髮 / bowl 鍋蓋頭 / hood 頭巾 / bald 光頭
// 配件：whiskers 鬍鬚 / mask 面罩 / glasses 眼鏡 / marks 臉部紋路 / sharingan 寫輪眼 / byakugan 白眼 / rinnegan 輪迴眼
//       akatsuki 曉袍 / vest 木葉背心 / armor 鎧甲 / cape 披風 / gourd 葫蘆 / sword 背劍 / fan 大扇 / bundle 傀儡包
//       scarf 圍巾 / bandage 繃帶 / collar 高領 / kanji 額頭愛字 / diamond 額頭菱形 / rings 黑眼圈 / brows 濃眉
//       goggles 護目鏡 / scar 鼻樑疤 / piercings 穿環 / scope 單眼鏡 / swirlmask 漩渦面具 / horns 角 / hokagehat 火影帽 / warmers 護腿
// 額外設定：skin 膚色 / pants 褲色 / trim 肩線色 / mark 紋路色 / eye 瞳色 / scarf 圍巾色
(function () {
  const L = '#2a4fa0'; // 木葉護額
  const STYLE = {
    _d: ['hood', null, 'mask'],
    // ★1
    ino: ['pony', L, '', { pants: '#7a4fbf' }],
    iruka: ['pony', L, 'vest scar'],
    konohamaru: ['spiky', null, 'scarf goggles', { scarf: '#3a5ac0' }],
    karin: ['long', null, 'glasses'],
    // ★2
    tenten: ['bun', L, '', { pants: '#5a3a4a' }],
    choji: ['short', L, 'marks', { mark: '#d94a4a', pants: '#e8e0d0' }],
    kiba: ['spiky', L, 'marks', { mark: '#c33', pants: '#555' }],
    shino: ['hood', null, 'glasses collar'],
    temari: ['pony', L, 'fan'],
    kankuro: ['hood', null, 'marks bundle', { mark: '#7a3aa0' }],
    shizune: ['short', null, ''],
    kurenai: ['long', null, '', { eye: '#c22' }],
    sai: ['short', null, '', { skin: '#f4ece4' }],
    suigetsu: ['spiky', null, 'sword'],
    // ★3
    hinata: ['long', L, 'byakugan'],
    neji: ['long', L, 'byakugan', { pants: '#eee' }],
    rocklee: ['bowl', L, 'brows warmers'],
    shikamaru: ['pony', L, 'vest'],
    sakura: ['short', '#d33', '', { pants: '#2a2233' }],
    hidan: ['short', '#888', 'akatsuki'],
    zabuza: ['short', '#8a94a8', 'bandage sword'],
    haku: ['long', null, ''],
    asuma: ['short', L, 'vest'],
    anko: ['pony', L, ''],
    yamato: ['short', L, 'vest'],
    jugo: ['spiky', null, ''],
    // ★4
    naruto: ['spiky', L, 'whiskers', { pants: '#f28a1e', trim: '#2a3f8f' }],
    sasuke: ['spiky', L, 'collar', { pants: '#eef0f6' }],
    kakashi: ['spiky', L, 'mask vest'],
    gaara: ['short', null, 'gourd kanji rings'],
    deidara: ['pony', L, 'akatsuki scope'],
    sasori: ['short', null, 'akatsuki'],
    kisame: ['spiky', L, 'akatsuki sword marks', { skin: '#8fb4d8', mark: '#345a86' }],
    kakuzu: ['hood', null, 'akatsuki mask'],
    konan: ['bun', null, 'akatsuki'],
    guy: ['bowl', L, 'brows warmers vest'],
    killerbee: ['short', L, 'sword glasses', { skin: '#c98f6a' }],
    tobirama: ['spiky', L, 'armor marks', { mark: '#c33' }],
    sarutobi: ['short', null, 'hokagehat'],
    danzo: ['short', L, ''],
    kabuto: ['pony', L, 'glasses'],
    // ★5
    itachi: ['pony', L, 'akatsuki sharingan marks', { mark: '#8a5a5a' }],
    jiraiya: ['wild', L, 'marks', { mark: '#c33' }],
    tsunade: ['twin', null, 'diamond'],
    orochimaru: ['long', null, 'marks', { skin: '#f0e6f4', mark: '#7a3aa0', eye: '#d8c020' }],
    minato: ['spiky', L, 'cape'],
    pain: ['spiky', L, 'akatsuki rinnegan piercings'],
    obito: ['spiky', null, 'akatsuki swirlmask sharingan'],
    madara: ['wild', null, 'sharingan armor'],
    hashirama: ['long', L, 'armor'],
    kaguya: ['long', null, 'horns diamond', { skin: '#f8f0f0' }],
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
  function drawChibi(ctx, c, o, T) {
    o = o || {}; T = T || 0;
    const st = STYLE[c.id] || STYLE._d, hs = st[0], band = st[1], acc = st[2] || '', ex = st[3] || {};
    const has = k => acc.indexOf(k) >= 0;
    const w = o.walk ? Math.sin(T * 16) : 0, bob = o.walk ? Math.abs(w) * 2 : 0;
    const skin = ex.skin || '#ffe2c6', dark = '#2a2233', pants = ex.pants || dark, hy = -50 - bob;
    const akat = has('akatsuki'), body = akat ? '#1c1622' : c.color;

    ctx.fillStyle = 'rgba(0,0,0,.25)'; ctx.beginPath(); ctx.ellipse(0, 0, 20, 5, 0, 0, 7); ctx.fill();

    // ---- 背後的東西 ----
    if (has('gourd')) { ctx.fillStyle = '#b8894a'; dot(ctx, -19, -30 - bob, 11); dot(ctx, -19, -42 - bob, 6); ctx.fillStyle = '#8a6230'; ctx.fillRect(-21, -50 - bob, 4, 5); }
    if (has('sword')) {
      ctx.strokeStyle = '#8a94a8'; ctx.lineWidth = 7; ctx.beginPath(); ctx.moveTo(-14, -8 - bob); ctx.lineTo(12, -66 - bob); ctx.stroke();
      ctx.strokeStyle = '#cfd5e0'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-14, -8 - bob); ctx.lineTo(12, -66 - bob); ctx.stroke();
    }
    if (has('fan')) { ctx.fillStyle = '#d8c8a0'; ctx.beginPath(); ctx.ellipse(-16, -34 - bob, 13, 22, 0.3, 0, 7); ctx.fill(); ctx.strokeStyle = '#8a3a3a'; ctx.lineWidth = 2; ctx.stroke(); }
    if (has('bundle')) { ctx.fillStyle = '#b89a6a'; rr(ctx, -22, -46 - bob, 12, 34, 4); ctx.fillStyle = '#6a4a2a'; ctx.fillRect(-22, -34 - bob, 12, 3); }
    if (has('cape')) {
      ctx.fillStyle = '#f4f4f4'; rr(ctx, -19, -40 - bob, 38, 34, 9);
      ctx.fillStyle = '#e4572e'; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(-17 + i * 9, -6 - bob); ctx.lineTo(-13 + i * 9, -16 - bob); ctx.lineTo(-8 + i * 9, -6 - bob); ctx.fill(); }
    }
    ctx.fillStyle = c.hair;
    if (hs === 'long' || hs === 'wild') rr(ctx, -19, hy - 4, 38, 36, 14);
    if (hs === 'pony') { ctx.beginPath(); ctx.ellipse(-21, hy - 2, 7, 13, 0.4, 0, 7); ctx.fill(); }
    if (hs === 'twin') { ctx.beginPath(); ctx.ellipse(-21, hy + 6, 6, 15, 0.25, 0, 7); ctx.ellipse(21, hy + 6, 6, 15, -0.25, 0, 7); ctx.fill(); }

    // ---- 腿、身體 ----
    ctx.fillStyle = pants; rr(ctx, -9 + w * 4, -12, 8, 12, 3); rr(ctx, 1 - w * 4, -12, 8, 12, 3);
    if (has('warmers')) { ctx.fillStyle = '#f28a1e'; rr(ctx, -9 + w * 4, -7, 8, 5, 2); rr(ctx, 1 - w * 4, -7, 8, 5, 2); }
    ctx.fillStyle = dark; rr(ctx, -10 + w * 4, -3, 10, 3, 1); rr(ctx, 0 - w * 4, -3, 10, 3, 1);
    ctx.fillStyle = body; rr(ctx, akat ? -13 : -12, -33 - bob, akat ? 26 : 24, akat ? 28 : 24, 7);
    if (has('vest')) {
      ctx.fillStyle = '#4a6a3a'; rr(ctx, -11, -32 - bob, 22, 22, 6);
      ctx.fillStyle = '#3a5a2a'; ctx.fillRect(-1, -32 - bob, 2, 22);
      ctx.fillStyle = '#5a7a4a'; ctx.fillRect(-9, -22 - bob, 6, 5); ctx.fillRect(3, -22 - bob, 6, 5);
    }
    if (ex.trim) { ctx.fillStyle = ex.trim; rr(ctx, -12, -33 - bob, 24, 7, 4); }
    if (has('armor')) {
      ctx.fillStyle = '#444a58'; dot(ctx, -13, -32 - bob, 6); dot(ctx, 13, -32 - bob, 6);
      ctx.fillStyle = '#5a6070'; ctx.fillRect(-9, -30 - bob, 18, 3); ctx.fillRect(-9, -24 - bob, 18, 3);
    }
    if (akat) {
      ctx.fillStyle = '#d02a2a';
      [[-5, -18], [6, -25]].forEach(([cx, cy]) => { dot(ctx, cx, cy - bob, 4); dot(ctx, cx + 5, cy + 1 - bob, 3); dot(ctx, cx - 4, cy + 2 - bob, 3); });
      ctx.fillStyle = '#1c1622'; rr(ctx, -13, -40 - bob, 26, 9, 4);
      ctx.fillStyle = '#d02a2a'; ctx.fillRect(-13, -33 - bob, 26, 1.5);
    }
    if (has('collar')) { ctx.fillStyle = body; rr(ctx, -13, -40 - bob, 26, 9, 4); }
    ctx.fillStyle = dark; ctx.fillRect(-12, -18 - bob, 24, 3);
    if (has('scarf')) { ctx.fillStyle = ex.scarf || '#d33'; rr(ctx, -11, -37 - bob, 22, 6, 3); ctx.fillRect(-17, -34 - bob, 5, 18); }
    ctx.fillStyle = body; rr(ctx, -17, -30 - bob, 7, 14, 3);
    ctx.fillStyle = skin; dot(ctx, -13.5, -15 - bob, 3.5);

    // ---- 頭 ----
    ctx.fillStyle = skin; dot(ctx, 0, hy, 17);
    if (has('horns')) { ctx.fillStyle = '#f0e8e0'; [-1, 1].forEach(s => { ctx.beginPath(); ctx.moveTo(s * 6, hy - 16); ctx.lineTo(s * 10, hy - 30); ctx.lineTo(s * 14, hy - 14); ctx.fill(); }); }

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
    if (has('kanji')) { ctx.fillStyle = '#c22'; ctx.fillRect(-1, hy - 7, 6, 6); }
    if (has('diamond')) { ctx.fillStyle = '#8a4ac8'; ctx.beginPath(); ctx.moveTo(3, hy - 12); ctx.lineTo(7, hy - 8); ctx.lineTo(3, hy - 4); ctx.lineTo(-1, hy - 8); ctx.fill(); }
    if (band) {
      ctx.fillStyle = band; ctx.fillRect(-17.5, hy - 9, 35, 6);
      ctx.fillStyle = '#cfd8e8'; ctx.fillRect(2, hy - 9, 12, 6);
      ctx.fillStyle = '#8a94a8'; ctx.fillRect(6, hy - 8, 4, 4);
    }
    if (has('goggles')) {
      ctx.fillStyle = '#555'; ctx.fillRect(-17, hy - 12, 34, 3);
      ctx.fillStyle = '#7ac8e8'; dot(ctx, -7, hy - 12, 5); dot(ctx, 7, hy - 12, 5);
      ctx.strokeStyle = '#222'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(-7, hy - 12, 5, 0, 7); ctx.arc(7, hy - 12, 5, 0, 7); ctx.stroke();
    }
    if (has('hokagehat')) {
      ctx.fillStyle = '#c8382e'; ctx.beginPath(); ctx.moveTo(-21, hy - 12); ctx.lineTo(21, hy - 12); ctx.lineTo(13, hy - 34); ctx.lineTo(-13, hy - 34); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.fillRect(-4, hy - 30, 8, 10); ctx.fillStyle = '#c8382e'; ctx.fillRect(-2, hy - 28, 4, 6);
    }

    // ---- 臉 ----
    const eyes = [-3, 9], ey = hy + 3;
    eyes.forEach((exx, i) => {
      ctx.fillStyle = has('byakugan') ? '#eeeaff' : '#fff'; ctx.beginPath(); ctx.ellipse(exx, ey, 4.2, 5, 0, 0, 7); ctx.fill();
      if (has('byakugan')) { ctx.strokeStyle = '#b8b0e8'; ctx.lineWidth = 1; ctx.stroke(); }
      else {
        ctx.fillStyle = has('sharingan') ? '#d22' : has('rinnegan') ? '#b89ae8' : (ex.eye || '#231c2a');
        dot(ctx, exx + 1, ey + 0.5, 2.9);
        if (has('sharingan')) { ctx.fillStyle = '#111'; dot(ctx, exx + 1, ey + 0.5, 1); }
        if (has('rinnegan')) { ctx.strokeStyle = '#6a4ab0'; ctx.lineWidth = 0.8; ctx.beginPath(); ctx.arc(exx + 1, ey + 0.5, 2, 0, 7); ctx.stroke(); }
        ctx.fillStyle = '#fff'; dot(ctx, exx + 2, ey - 1, 1);
      }
      if (has('scope') && i === 0) { ctx.fillStyle = '#c22'; dot(ctx, exx, ey, 6); ctx.fillStyle = '#111'; dot(ctx, exx, ey, 2.5); }
      if (has('rings')) { ctx.strokeStyle = '#3a2a4a'; ctx.lineWidth = 2.2; ctx.beginPath(); ctx.ellipse(exx, ey, 6, 7, 0, 0, 7); ctx.stroke(); }
      if (has('brows')) { ctx.fillStyle = '#111'; ctx.fillRect(exx - 5, ey - 10, 10, 3.5); }
    });
    ctx.fillStyle = 'rgba(255,120,120,.4)';
    ctx.beginPath(); ctx.ellipse(-8, hy + 10, 3.5, 2, 0, 0, 7); ctx.ellipse(13, hy + 10, 3.5, 2, 0, 0, 7); ctx.fill();
    if (has('marks')) {
      ctx.strokeStyle = ex.mark || '#7a4a4a'; ctx.lineWidth = 1.6; ctx.beginPath();
      eyes.forEach(exx => { ctx.moveTo(exx - 3, ey + 6); ctx.lineTo(exx, ey + 11); });
      ctx.stroke();
    }
    if (has('whiskers')) {
      ctx.strokeStyle = '#6a4a3a'; ctx.lineWidth = 1.2; ctx.beginPath();
      [-8, 13].forEach(cx => [-1, 0, 1].forEach(k => { ctx.moveTo(cx - 4, hy + 10 + k * 3); ctx.lineTo(cx + 4, hy + 10 + k * 3 + k); }));
      ctx.stroke();
    }
    if (has('scar')) { ctx.strokeStyle = '#b06a5a'; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.moveTo(-2, hy + 8); ctx.lineTo(13, hy + 8); ctx.stroke(); }
    if (has('piercings')) { ctx.fillStyle = '#c8ccd8'; [[-11, 9], [-13, 12], [14, 8], [16, 11], [3, 6], [3, 10]].forEach(p => dot(ctx, p[0], hy + p[1], 1)); }
    const noMouth = has('mask') || has('bandage') || has('swirlmask');
    if (has('mask')) { ctx.fillStyle = '#3d4258'; rr(ctx, -16, hy + 6, 32, 12, 5); }
    else if (has('bandage')) { ctx.fillStyle = '#e8e8e8'; rr(ctx, -15, hy + 7, 30, 9, 3); }
    else if (!noMouth) { ctx.strokeStyle = '#8a4a3a'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(3, hy + 9, 3, 0.2, Math.PI - 0.2); ctx.stroke(); }
    if (has('glasses')) { ctx.strokeStyle = '#333'; ctx.lineWidth = 1.6; eyes.forEach(exx => { ctx.beginPath(); ctx.arc(exx, ey, 6.2, 0, 7); ctx.stroke(); }); }
    if (has('swirlmask')) {
      ctx.fillStyle = '#e8842a'; ctx.beginPath(); ctx.ellipse(2, hy + 3, 15, 14, 0, 0, 7); ctx.fill();
      ctx.strokeStyle = '#222'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(5, hy + 2, 8, 0, 4.5); ctx.arc(5, hy + 2, 4, 0, 4); ctx.stroke();
      ctx.fillStyle = '#111'; dot(ctx, 9, ey, 3); ctx.fillStyle = '#d22'; dot(ctx, 9, ey, 2);
    }

    // ---- 前手與攻擊 ----
    if (o.atk > 0) {
      ctx.fillStyle = body; rr(ctx, 8, -34 - bob, 16, 7, 3);
      ctx.fillStyle = skin; dot(ctx, 25, -31 - bob, 4);
      ctx.strokeStyle = '#e8eef8'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(26, -31 - bob); ctx.lineTo(52, -46 - bob); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,.8)'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(6, -34, 52, -1.0, 0.9); ctx.stroke();
    } else {
      ctx.fillStyle = body; rr(ctx, 9, -31 - bob, 7, 14, 3);
      ctx.fillStyle = skin; dot(ctx, 12.5, -15 - bob, 3.5);
    }
  }

  // 頭像：把整隻 Q 版角色放大後只露出頭肩，裁成圓形。結果快取。
  const cache = {};
  function portrait(c) {
    if (cache[c.id]) return cache[c.id];
    const cv = document.createElement('canvas'); cv.width = cv.height = 96;
    const x = cv.getContext('2d');
    x.save(); x.beginPath(); x.arc(48, 48, 48, 0, 7); x.clip();
    const g = x.createRadialGradient(48, 40, 6, 48, 48, 60);
    g.addColorStop(0, '#ffffff33'); g.addColorStop(1, '#00000055');
    x.fillStyle = c.color; x.fillRect(0, 0, 96, 96); x.fillStyle = g; x.fillRect(0, 0, 96, 96);
    x.translate(48, 176); x.scale(2.4, 2.4);
    drawChibi(x, c, {}, 0);
    x.restore();
    cache[c.id] = cv;
    return cv;
  }

  window.drawChibi = drawChibi;
  window.chibiPortrait = portrait;
  window.chibiPortraitURL = c => portrait(c).toDataURL();
})();

// 技能特效：每個角色對應一個「特效主題」，主題決定飛行物、爆發、突進的畫法與配色。
// 要改某角色的特效：改 CHAR_THEME；要新增主題：在 THEMES 加一筆。
(function () {
  // shot 飛行物：orb 光球 / bolt 雷 / flame 火焰 / crescent 風刃 / dragon 水龍 / star 手裡劍 / shard 針 / snake 蛇
  // burst 範圍：ring 波紋 / spiral 螺旋丸 / bolt 雷 / flame 火柱 / wave 水浪 / sand 砂 / wood 木刺 / petal 花瓣 / trigram 八卦
  //            smoke 煙 / boom 爆炸 / spike 尖刺 / heal 治療 / vortex 漩渦 / susanoo 須佐能乎 / moon 月
  // dash 突進：bolt 雷光 / flash 閃光殘影 / slash 斬擊 / spin 旋轉 / wind 疾風
  const THEMES = {
    rasengan:  { c1: '#5ab8ff', c2: '#ffffff', shot: 'orb', burst: 'spiral', dash: 'flash' },
    chidori:   { c1: '#8fd6ff', c2: '#ffffff', shot: 'bolt', burst: 'bolt', dash: 'bolt' },
    thunder:   { c1: '#ffe45a', c2: '#ffffff', shot: 'bolt', burst: 'bolt', dash: 'bolt' },
    amaterasu: { c1: '#150b1a', c2: '#c0203a', shot: 'flame', burst: 'flame', dash: 'flash' },
    fire:      { c1: '#ff7a2a', c2: '#ffd84a', shot: 'flame', burst: 'flame', dash: 'flash' },
    wind:      { c1: '#bfeecf', c2: '#ffffff', shot: 'crescent', burst: 'ring', dash: 'slash' },
    water:     { c1: '#4aa8ff', c2: '#cfeaff', shot: 'dragon', burst: 'wave', dash: 'slash' },
    sand:      { c1: '#d8b070', c2: '#a8803e', shot: 'orb', burst: 'sand', dash: 'slash' },
    wood:      { c1: '#5aa84a', c2: '#8a5a2a', shot: 'orb', burst: 'wood', dash: 'slash' },
    paper:     { c1: '#ffffff', c2: '#8fb0ff', shot: 'star', burst: 'petal', dash: 'slash' },
    ink:       { c1: '#222222', c2: '#888888', shot: 'shard', burst: 'ring', dash: 'slash' },
    shadow:    { c1: '#3a2a5a', c2: '#8a6ad0', shot: 'shard', burst: 'ring', dash: 'slash' },
    bug:       { c1: '#2a2a2a', c2: '#7a7a3a', shot: 'shard', burst: 'smoke', dash: 'slash' },
    gentle:    { c1: '#7ad0ff', c2: '#ffffff', shot: 'orb', burst: 'trigram', dash: 'flash' },
    lotus:     { c1: '#5aff8a', c2: '#ffffff', shot: 'orb', burst: 'ring', dash: 'spin' },
    gate:      { c1: '#ff8a3a', c2: '#ffffff', shot: 'orb', burst: 'ring', dash: 'wind' },
    explosion: { c1: '#ffb040', c2: '#fff2c0', shot: 'orb', burst: 'boom', dash: 'flash' },
    puppet:    { c1: '#c8c8d0', c2: '#cc3333', shot: 'shard', burst: 'ring', dash: 'slash' },
    snake:     { c1: '#8a5ad0', c2: '#c8ff6a', shot: 'snake', burst: 'ring', dash: 'slash' },
    ice:       { c1: '#bfe8ff', c2: '#ffffff', shot: 'shard', burst: 'spike', dash: 'slash' },
    blade:     { c1: '#e8eef8', c2: '#9aa4b8', shot: 'crescent', burst: 'ring', dash: 'slash' },
    shuriken:  { c1: '#cfd8ff', c2: '#ffffff', shot: 'star', burst: 'ring', dash: 'slash' },
    fang:      { c1: '#c8a878', c2: '#ffffff', shot: 'orb', burst: 'ring', dash: 'spin' },
    boulder:   { c1: '#a87a4a', c2: '#6a4a2a', shot: 'orb', burst: 'ring', dash: 'spin' },
    petal:     { c1: '#ff9ac8', c2: '#ffffff', shot: 'star', burst: 'petal', dash: 'slash' },
    smoke:     { c1: '#ffd0e8', c2: '#ffffff', shot: 'orb', burst: 'smoke', dash: 'flash' },
    heal:      { c1: '#6fe08a', c2: '#ffffff', shot: 'orb', burst: 'heal', dash: 'slash' },
    medblade:  { c1: '#6fe08a', c2: '#e8fff0', shot: 'crescent', burst: 'ring', dash: 'slash' },
    flash:     { c1: '#ffe45a', c2: '#ffffff', shot: 'star', burst: 'ring', dash: 'flash' },
    shinra:    { c1: '#c9a0ff', c2: '#ffffff', shot: 'orb', burst: 'ring', dash: 'flash' },
    kamui:     { c1: '#b06aff', c2: '#181020', shot: 'orb', burst: 'vortex', dash: 'flash' },
    susanoo:   { c1: '#a06aff', c2: '#e0d0ff', shot: 'orb', burst: 'susanoo', dash: 'flash' },
    mugen:     { c1: '#c8a0ff', c2: '#ffffff', shot: 'orb', burst: 'moon', dash: 'flash' },
    curse:     { c1: '#e0873a', c2: '#3a2a1a', shot: 'orb', burst: 'spike', dash: 'slash' },
  };
  const BY_TYPE = { rush: 'blade', fire: 'fire', burst: 'ring', barrage: 'shuriken', heal: 'heal' };
  const CHAR_THEME = {
    naruto: 'rasengan', sasuke: 'chidori', kakashi: 'chidori', killerbee: 'thunder', itachi: 'amaterasu',
    sarutobi: 'fire', jiraiya: 'fire', temari: 'wind', asuma: 'wind', danzo: 'wind', kakuzu: 'wind',
    tobirama: 'water', kisame: 'water', gaara: 'sand', yamato: 'wood', hashirama: 'wood', konan: 'paper',
    sai: 'ink', shikamaru: 'shadow', shino: 'bug', hinata: 'gentle', neji: 'gentle', rocklee: 'lotus', guy: 'gate',
    deidara: 'explosion', sasori: 'puppet', kankuro: 'puppet', orochimaru: 'snake', anko: 'snake', haku: 'ice',
    zabuza: 'blade', hidan: 'blade', suigetsu: 'blade', iruka: 'blade', tenten: 'shuriken', ino: 'shuriken',
    kiba: 'fang', choji: 'boulder', kurenai: 'petal', konohamaru: 'smoke', karin: 'heal', shizune: 'heal',
    sakura: 'heal', tsunade: 'heal', kabuto: 'medblade', minato: 'flash', pain: 'shinra', obito: 'kamui',
    madara: 'susanoo', kaguya: 'mugen', jugo: 'curse',
  };
  function theme(c) {
    return THEMES[CHAR_THEME[c.id]] || THEMES[BY_TYPE[c.skill.type]] || THEMES.blade;
  }

  const rnd = (i, k) => { const s = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return s - Math.floor(s); };
  function circle(ctx, x, y, r) { ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); }
  function glow(ctx, x, y, r, c1, c2) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, c2); g.addColorStop(0.5, c1); g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g; circle(ctx, x, y, r);
  }
  function bolt(ctx, x1, y1, x2, y2, seed, amp) {
    const n = 6; ctx.beginPath(); ctx.moveTo(x1, y1);
    for (let i = 1; i < n; i++) {
      const t = i / n;
      ctx.lineTo(x1 + (x2 - x1) * t + (rnd(seed, i) - 0.5) * amp, y1 + (y2 - y1) * t + (rnd(seed, i + 9) - 0.5) * amp);
    }
    ctx.lineTo(x2, y2); ctx.stroke();
  }

  // ---- 範圍爆發（f: x,y,age,dur,max,face,theme） ----
  function burst(ctx, f, T) {
    const th = f.theme, k = f.age / f.dur, r = f.max, x = f.x, y = f.y, fade = 1 - k;
    ctx.save();
    ctx.globalAlpha = Math.max(0, fade);
    switch (th.burst) {
      case 'spiral': { // 螺旋丸
        const ox = x + f.face * 60, R = 26 + k * 40;
        glow(ctx, ox, y, R * 1.8, th.c1, th.c2);
        ctx.strokeStyle = th.c2; ctx.lineWidth = 3;
        for (let i = 0; i < 4; i++) { const a = T * 18 + i * 1.57; ctx.beginPath(); ctx.arc(ox, y, R * (0.5 + i * 0.15), a, a + 2.2); ctx.stroke(); }
        ctx.strokeStyle = th.c1; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(x, y, r * k, 0, 7); ctx.stroke();
        break;
      }
      case 'bolt': {
        ctx.strokeStyle = th.c1; ctx.lineWidth = 3; ctx.shadowColor = th.c1; ctx.shadowBlur = 12;
        for (let i = 0; i < 10; i++) { const a = i / 10 * 6.283 + T * 3; bolt(ctx, x, y, x + Math.cos(a) * r * (0.5 + k * 0.5), y + Math.sin(a) * r * 0.6 * (0.5 + k * 0.5), i + Math.floor(T * 30), 24); }
        break;
      }
      case 'flame': {
        for (let i = 0; i < 26; i++) {
          const a = rnd(i, 1) * 6.283, d = rnd(i, 2) * r * (0.3 + k * 0.7), h = k * 70 * rnd(i, 3);
          const fx = x + Math.cos(a) * d, fy = y + Math.sin(a) * d * 0.4 - h;
          glow(ctx, fx, fy, 16 + rnd(i, 4) * 16, th.c1, th.c2);
        }
        break;
      }
      case 'wave': {
        ctx.strokeStyle = th.c1; ctx.lineWidth = 8; ctx.beginPath();
        for (let i = -r; i <= r; i += 6) { const yy = y + 20 - Math.abs(i) * 0.15 - Math.sin(i * 0.08 + T * 12) * 14 * (1 - k * 0.3) - k * 30; i === -r ? ctx.moveTo(x + i, yy) : ctx.lineTo(x + i, yy); }
        ctx.stroke(); ctx.strokeStyle = th.c2; ctx.lineWidth = 3; ctx.stroke();
        break;
      }
      case 'sand': {
        for (let i = 0; i < 60; i++) {
          const a = rnd(i, 1) * 6.283 + k * 3, d = (0.2 + rnd(i, 2) * 0.8) * r * (0.4 + k * 0.6);
          ctx.fillStyle = i % 2 ? th.c1 : th.c2; circle(ctx, x + Math.cos(a) * d, y + Math.sin(a) * d * 0.55, 3 + rnd(i, 3) * 4);
        }
        break;
      }
      case 'wood': {
        ctx.globalAlpha = Math.max(0, Math.min(1, fade * 2.2));
        for (let i = -3; i <= 3; i++) {
          const bx = x + i * 42, hgt = Math.min(1, k * 3) * (90 + rnd(i, 5) * 50);
          ctx.fillStyle = th.c2; ctx.beginPath(); ctx.moveTo(bx - 10, y + 30); ctx.lineTo(bx + rnd(i, 6) * 14 - 7, y + 30 - hgt); ctx.lineTo(bx + 10, y + 30); ctx.fill();
          ctx.fillStyle = th.c1; circle(ctx, bx, y + 30 - hgt, 9);
        }
        break;
      }
      case 'petal': {
        for (let i = 0; i < 40; i++) {
          const a = rnd(i, 1) * 6.283, d = rnd(i, 2) * r * (0.3 + k * 0.7);
          ctx.fillStyle = i % 3 ? th.c1 : th.c2; ctx.beginPath();
          ctx.ellipse(x + Math.cos(a) * d, y + Math.sin(a) * d * 0.6 - k * 30, 6, 3, a + T * 4, 0, 7); ctx.fill();
        }
        break;
      }
      case 'trigram': { // 八卦
        ctx.translate(x, y + 24); ctx.scale(1, 0.35); ctx.rotate(T * 5);
        ctx.strokeStyle = th.c1; ctx.fillStyle = th.c1; ctx.lineWidth = 4; ctx.shadowColor = th.c1; ctx.shadowBlur = 14;
        const R = r * Math.min(1, k * 3 + 0.3);
        ctx.beginPath(); ctx.arc(0, 0, R, 0, 7); ctx.stroke(); ctx.beginPath(); ctx.arc(0, 0, R * 0.7, 0, 7); ctx.stroke();
        for (let i = 0; i < 8; i++) { ctx.save(); ctx.rotate(i * 0.785); ctx.fillRect(R * 0.74, -3, R * 0.2, 6); ctx.restore(); }
        ctx.beginPath(); ctx.arc(0, 0, R * 0.3, 0, 7); ctx.stroke();
        break;
      }
      case 'smoke': {
        for (let i = 0; i < 18; i++) {
          const a = rnd(i, 1) * 6.283, d = rnd(i, 2) * r * 0.8 * (0.3 + k * 0.7);
          ctx.fillStyle = i % 3 ? th.c1 : th.c2; circle(ctx, x + Math.cos(a) * d, y + Math.sin(a) * d * 0.6 - k * 20, 14 + rnd(i, 3) * 14);
        }
        break;
      }
      case 'boom': {
        glow(ctx, x, y, r * (0.4 + k * 1.1), th.c1, th.c2);
        ctx.strokeStyle = th.c1; ctx.lineWidth = 8; ctx.beginPath(); ctx.arc(x, y, r * k * 1.1, 0, 7); ctx.stroke();
        if (k < 0.25) { ctx.fillStyle = '#fff'; circle(ctx, x, y, r * 0.5); }
        break;
      }
      case 'spike': {
        for (let i = 0; i < 12; i++) {
          const a = i / 12 * 6.283, L = r * (0.4 + rnd(i, 1) * 0.5) * Math.min(1, k * 3);
          ctx.fillStyle = i % 2 ? th.c1 : th.c2; ctx.beginPath();
          ctx.moveTo(x + Math.cos(a - 0.12) * 14, y + Math.sin(a - 0.12) * 8);
          ctx.lineTo(x + Math.cos(a) * L, y + Math.sin(a) * L * 0.6);
          ctx.lineTo(x + Math.cos(a + 0.12) * 14, y + Math.sin(a + 0.12) * 8); ctx.fill();
        }
        break;
      }
      case 'heal': {
        ctx.strokeStyle = th.c1; ctx.lineWidth = 5; ctx.beginPath(); ctx.ellipse(x, y + 26, r * (0.4 + k * 0.6), r * 0.18, 0, 0, 7); ctx.stroke();
        ctx.fillStyle = th.c1;
        for (let i = 0; i < 8; i++) { const px = x - 60 + rnd(i, 1) * 120, py = y + 20 - k * 90 - rnd(i, 2) * 30; ctx.fillRect(px - 6, py - 2, 12, 4); ctx.fillRect(px - 2, py - 6, 4, 12); }
        break;
      }
      case 'vortex': {
        ctx.strokeStyle = th.c1; ctx.lineWidth = 4;
        for (let arm = 0; arm < 4; arm++) {
          ctx.beginPath();
          for (let t = 0; t < 30; t++) { const a = arm * 1.57 + t * 0.3 + T * 10, d = t * r / 30 * (0.4 + k * 0.6); const px = x + Math.cos(a) * d, py = y + Math.sin(a) * d * 0.6; t ? ctx.lineTo(px, py) : ctx.moveTo(px, py); }
          ctx.stroke();
        }
        ctx.fillStyle = th.c2; circle(ctx, x, y, 14);
        break;
      }
      case 'susanoo': {
        ctx.globalAlpha = Math.max(0, fade) * 0.75;
        ctx.fillStyle = th.c1; ctx.beginPath(); ctx.ellipse(x, y - 10, 80, 110 * Math.min(1, k * 3 + 0.3), 0, Math.PI, 0); ctx.fill();
        ctx.strokeStyle = th.c2; ctx.lineWidth = 3;
        for (let i = 1; i < 5; i++) { ctx.beginPath(); ctx.ellipse(x, y - 10, 80 - i * 14, Math.max(1, 100 * Math.min(1, k * 3 + 0.3) - i * 14), 0, Math.PI, 0); ctx.stroke(); }
        ctx.beginPath(); ctx.arc(x, y - 10, r * k, 0, 7); ctx.stroke();
        break;
      }
      case 'moon': {
        ctx.globalAlpha = Math.max(0, fade) * 0.85;
        glow(ctx, x, y - 60, 130 * (0.5 + k * 0.5), th.c1, th.c2);
        ctx.strokeStyle = th.c2; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(x, y - 60, 60, 0, 7); ctx.arc(x, y - 60, 36, 0, 7); ctx.stroke();
        ctx.beginPath(); ctx.arc(x, y, r * k, 0, 7); ctx.stroke();
        break;
      }
      default: { // ring
        ctx.strokeStyle = th.c1; ctx.lineWidth = 7;
        for (let i = 0; i < 3; i++) { const kk = Math.max(0, k - i * 0.12); ctx.globalAlpha = Math.max(0, fade - i * 0.15); ctx.beginPath(); ctx.ellipse(x, y + 10, r * kk, r * kk * 0.55, 0, 0, 7); ctx.stroke(); }
        ctx.strokeStyle = th.c2; ctx.lineWidth = 2; ctx.beginPath(); ctx.ellipse(x, y + 10, r * k, r * k * 0.55, 0, 0, 7); ctx.stroke();
      }
    }
    ctx.restore();
  }

  // ---- 飛行物（s: x,y,w,h,vx,theme,shape） ----
  function shot(ctx, s, T) {
    const th = s.theme, d = Math.sign(s.vx) || 1, x = s.x, y = s.y;
    ctx.save();
    switch (th.shot) {
      case 'bolt':
        ctx.strokeStyle = th.c1; ctx.lineWidth = 4; ctx.shadowColor = th.c1; ctx.shadowBlur = 10;
        bolt(ctx, x - d * s.w, y, x + d * s.w * 0.6, y, Math.floor(T * 40), 14);
        ctx.strokeStyle = th.c2; ctx.lineWidth = 1.5; bolt(ctx, x - d * s.w, y, x + d * s.w * 0.6, y, Math.floor(T * 40), 14);
        break;
      case 'flame':
        for (let i = 0; i < 7; i++) glow(ctx, x - d * i * s.w * 0.22, y + Math.sin(T * 20 + i) * 4, s.h * (0.9 - i * 0.08), th.c1, i < 2 ? th.c2 : th.c1);
        break;
      case 'crescent':
        ctx.strokeStyle = th.c1; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(x - d * 8, y, s.w * 0.8 + 6, d > 0 ? -1.0 : Math.PI - 1.0, d > 0 ? 1.0 : Math.PI + 1.0); ctx.stroke();
        ctx.strokeStyle = th.c2; ctx.lineWidth = 2; ctx.stroke();
        break;
      case 'dragon':
        for (let i = 0; i < 9; i++) { ctx.fillStyle = i % 2 ? th.c1 : th.c2; circle(ctx, x - d * i * 9, y + Math.sin(T * 14 + i * 0.8) * 8, Math.max(4, s.h * 0.6 - i * 0.6)); }
        ctx.fillStyle = th.c1; circle(ctx, x + d * 6, y, 10); ctx.fillStyle = '#fff'; circle(ctx, x + d * 9, y - 3, 2);
        break;
      case 'star':
        ctx.translate(x, y); ctx.rotate(T * 20);
        ctx.fillStyle = th.c1; ctx.beginPath();
        for (let i = 0; i < 8; i++) { const r = i % 2 ? 4 : 11; ctx.lineTo(Math.cos(i * 0.785) * r, Math.sin(i * 0.785) * r); }
        ctx.closePath(); ctx.fill(); ctx.strokeStyle = th.c2; ctx.lineWidth = 1; ctx.stroke();
        break;
      case 'shard':
        ctx.fillStyle = th.c1; ctx.beginPath(); ctx.moveTo(x + d * s.w * 0.6, y); ctx.lineTo(x, y - s.h * 0.7); ctx.lineTo(x - d * s.w * 0.6, y); ctx.lineTo(x, y + s.h * 0.7); ctx.closePath(); ctx.fill();
        ctx.strokeStyle = th.c2; ctx.lineWidth = 1; ctx.stroke();
        break;
      case 'snake':
        ctx.strokeStyle = th.c1; ctx.lineWidth = 6; ctx.lineCap = 'round'; ctx.beginPath();
        for (let i = 0; i < 10; i++) { const px = x - d * i * 5, py = y + Math.sin(T * 18 + i * 0.9) * 6; i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); }
        ctx.stroke(); ctx.fillStyle = th.c2; circle(ctx, x + d * 2, y, 4);
        break;
      default: // orb
        glow(ctx, x, y, Math.max(s.w, s.h) * 0.9, th.c1, th.c2);
    }
    ctx.restore();
  }

  // ---- 突進（k：剩餘時間比例 1→0） ----
  function dash(ctx, x, y, face, th, k, T, drawBody) {
    ctx.save();
    switch (th.dash) {
      case 'bolt':
        ctx.strokeStyle = th.c1; ctx.lineWidth = 3; ctx.shadowColor = th.c1; ctx.shadowBlur = 14;
        for (let i = 0; i < 9; i++) bolt(ctx, x - face * (30 + i * 9), y - 10 - rnd(i, 1) * 50, x + face * 10, y - 20 - rnd(i, 2) * 30, i + Math.floor(T * 40), 18);
        ctx.strokeStyle = th.c2; ctx.lineWidth = 1.5;
        for (let i = 0; i < 5; i++) bolt(ctx, x - face * 20, y - 30, x + face * 24, y - 30 + (i - 2) * 12, i + Math.floor(T * 40), 12);
        break;
      case 'flash':
        for (let i = 1; i <= 4; i++) { ctx.globalAlpha = 0.35 - i * 0.07; if (drawBody) drawBody(x - face * i * 26); }
        ctx.globalAlpha = 0.9; ctx.fillStyle = th.c1; ctx.fillRect(face > 0 ? x - 160 : x, y - 34, 160, 4); ctx.fillStyle = th.c2; ctx.fillRect(face > 0 ? x - 160 : x, y - 33, 160, 2);
        break;
      case 'spin':
        ctx.strokeStyle = th.c1; ctx.lineWidth = 5; ctx.translate(x, y - 30);
        for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(0, 0, 32 + i * 6, T * 22 + i * 2, T * 22 + i * 2 + 2); ctx.stroke(); }
        break;
      case 'wind':
        ctx.strokeStyle = th.c1; ctx.lineWidth = 3;
        for (let i = 0; i < 8; i++) { const yy = y - 12 - i * 8; ctx.beginPath(); ctx.moveTo(x - face * 20, yy); ctx.lineTo(x - face * (60 + rnd(i, 1) * 60), yy); ctx.stroke(); }
        break;
      default: // slash
        ctx.strokeStyle = th.c1; ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(x + face * 6, y - 34, 50, face > 0 ? -1.2 : Math.PI - 1.2, face > 0 ? 1.2 : Math.PI + 1.2); ctx.stroke();
        ctx.strokeStyle = th.c2; ctx.lineWidth = 2; ctx.stroke();
        ctx.strokeStyle = th.c1; ctx.lineWidth = 2;
        for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(x - face * 20, y - 16 - i * 14); ctx.lineTo(x - face * 70, y - 16 - i * 14); ctx.stroke(); }
    }
    ctx.restore();
  }

  window.FX = { THEMES, theme, burst, shot, dash };
})();

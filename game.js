(() => {
  const W = 960, H = 540, GROUND = 450, WORLD = 4200;
  const cv = document.getElementById('cv'), ctx = cv.getContext('2d');
  const R = window.ROSTER, byId = Object.fromEntries(R.map(c => [c.id, c]));
  const $ = id => document.getElementById(id);
  const SAVE_KEY = 'ninja-game-save-v2';

  // ---------- 存檔 ----------
  function defaultSave() {
    const owned = {}; R.forEach(c => owned[c.id] = 1); // 全角色開通
    return { owned, coins: 5000, team: ['naruto', 'sasuke', 'sakura'], stage: 1, maxStage: 99, lv: {}, xp: {} };
  }
  function loadSave() {
    try {
      const s = JSON.parse(localStorage.getItem(SAVE_KEY));
      if (s && s.owned && s.team) { s.lv = s.lv || {}; s.xp = s.xp || {}; return s; }
    } catch (e) {}
    return defaultSave();
  }
  let save = loadSave();
  function persist() { try { localStorage.setItem(SAVE_KEY, JSON.stringify(save)); } catch (e) {} }
  const mult = id => 1 + 0.1 * ((save.owned[id] || 1) - 1);           // 抽卡重複強化
  const lvOf = id => (save.lv && save.lv[id]) || 1;
  const lvMult = id => 1 + 0.06 * (lvOf(id) - 1);                     // 等級強化
  const xpNeed = lv => lv * 100;

  // ---------- 畫面切換 ----------
  const screens = ['menu', 'gacha', 'coll', 'help', 'result'];
  function show(name) {
    screens.forEach(s => $(s).classList.toggle('on', s === name));
    if (name === 'menu') refreshMenu();
    if (name === 'coll') refreshColl();
    if (name === 'gacha') $('coins2').textContent = save.coins;
    $('touch').classList.toggle('on', name === null);
  }

  function faceEl(c, extra) {
    if (window.chibiPortraitURL) return `<img class="face" alt="${c.name}" src="${window.chibiPortraitURL(c)}" style="${extra || ''}">`;
    return `<div class="face" style="background:${c.color};${extra || ''}">${c.name[0]}</div>`;
  }
  function cardHtml(c, opts = {}) {
    const stars = '★'.repeat(c.rarity);
    const lv = save.owned[c.id] || 0;
    return `<div class="card ${opts.locked ? 'locked' : ''} ${opts.team ? 'team' : ''}" data-id="${c.id}">
      ${opts.tag ? `<span class="tag">${opts.tag}</span>` : ''}
      ${opts.locked ? '<div class="face" style="background:#333">?</div>' : faceEl(c)}
      <b>${opts.locked ? '???' : c.name}</b><br>
      <span class="r${c.rarity}">${stars}</span>${!opts.locked ? ` <span class="sub">Lv${lvOf(c.id)}${lv > 1 ? '+' + (lv - 1) : ''}</span>` : ''}
      ${opts.locked ? '' : `<div class="sub">${c.skill.name}</div>`}
    </div>`;
  }

  function refreshMenu() {
    $('coins').textContent = save.coins;
    $('stg-n').textContent = save.stage;
    $('team-preview').innerHTML = save.team.map(id => cardHtml(byId[id])).join('');
  }
  function refreshColl() {
    const own = R.filter(c => save.owned[c.id]).length;
    $('coll-count').textContent = `(${own}/${R.length})`;
    $('coll-team').innerHTML = save.team.map(id => cardHtml(byId[id], { team: true })).join('');
    const sorted = [...R].sort((a, b) => b.rarity - a.rarity);
    $('coll-grid').innerHTML = sorted.map(c => cardHtml(c, { locked: !save.owned[c.id], team: save.team.includes(c.id) })).join('');
  }

  $('coll-grid').addEventListener('click', e => {
    const el = e.target.closest('.card'); if (!el || el.classList.contains('locked')) return;
    const id = el.dataset.id, i = save.team.indexOf(id);
    if (i >= 0) { if (save.team.length > 1) save.team.splice(i, 1); }
    else if (save.team.length < 3) save.team.push(id);
    persist(); refreshColl();
  });

  document.querySelectorAll('[data-d]').forEach(b => b.onclick = () => {
    save.stage = Math.max(1, Math.min(save.maxStage, save.stage + Number(b.dataset.d)));
    persist(); refreshMenu();
  });
  $('b-play').onclick = () => startStage(save.stage);
  $('b-gacha').onclick = () => show('gacha');
  $('b-coll').onclick = () => show('coll');
  $('b-help').onclick = () => show('help');
  $('g-back').onclick = $('c-back').onclick = $('h-back').onclick = $('r-menu').onclick = () => show('menu');

  // ---------- 召喚 ----------
  const WEIGHTS = [[1, 45], [2, 30], [3, 17], [4, 6], [5, 2]];
  function pullOne() {
    let roll = Math.random() * 100, r = 1;
    for (const [rar, w] of WEIGHTS) { if (roll < w) { r = rar; break; } roll -= w; }
    let pool = R.filter(c => c.rarity === r);
    if (!pool.length) pool = R;
    const c = pool[Math.floor(Math.random() * pool.length)];
    const isNew = !save.owned[c.id];
    save.owned[c.id] = (save.owned[c.id] || 0) + 1;
    return { c, isNew };
  }
  function pull(n) {
    const cost = n === 10 ? 900 : 100 * n;
    if (save.coins < cost) return;
    save.coins -= cost;
    const res = Array.from({ length: n }, pullOne);
    persist();
    $('coins2').textContent = save.coins;
    $('pull-res').innerHTML = res.map(x => cardHtml(x.c, { tag: x.isNew ? 'NEW' : '強化' })).join('');
  }
  $('pull1').onclick = () => pull(1);
  $('pull10').onclick = () => pull(10);

  // ---------- 輸入 ----------
  const keys = {}, pressed = {};
  const MAP = { ArrowLeft: 'left', a: 'left', A: 'left', ArrowRight: 'right', d: 'right', D: 'right',
    ArrowUp: 'jump', w: 'jump', W: 'jump', ' ': 'jump', j: 'atk', J: 'atk', z: 'atk', Z: 'atk',
    k: 'skill', K: 'skill', x: 'skill', X: 'skill', l: 'dodge', L: 'dodge', c: 'dodge', C: 'dodge', Shift: 'dodge',
    '1': 's1', '2': 's2', '3': 's3' };
  addEventListener('keydown', e => {
    const k = MAP[e.key]; if (!k) return;
    if (playing) e.preventDefault();
    if (!keys[k]) pressed[k] = true;
    keys[k] = true;
  });
  addEventListener('keyup', e => { const k = MAP[e.key]; if (k) keys[k] = false; });
  document.querySelectorAll('#touch button').forEach(b => {
    const k = b.dataset.k;
    const on = e => { e.preventDefault(); if (!keys[k]) pressed[k] = true; keys[k] = true; };
    const off = e => { e.preventDefault(); keys[k] = false; };
    b.addEventListener('pointerdown', on);
    b.addEventListener('pointerup', off);
    b.addEventListener('pointerleave', off);
  });

  // ---------- 關卡狀態 ----------
  let g = null, playing = false, last = 0, T = 0;
  const rnd = (a, b) => a + Math.random() * (b - a);

  function startStage(n) {
    const members = save.team.map(id => {
      const c = byId[id], m = mult(id) * lvMult(id);
      const maxhp = Math.round(c.hp * m);
      return { c, hp: maxhp, maxhp, atk: c.atk * m, cd: 0 };
    });
    g = {
      stage: n, members, idx: 0,
      p: { x: 120, y: GROUND, vx: 0, vy: 0, face: 1, onG: true, atkT: 0, atkCd: 0, inv: 0, dashT: 0, dashHit: null,
        combo: 0, comboT: 0, rollT: 0, rollCd: 0, theme: null },
      enemies: [], shots: [], texts: [], fx: [],
      earned: 0, kills: 0, nextSpawn: 600, bossSpawned: false, boss: null, cam: 0, over: false,
    };
    playing = true; last = performance.now();
    show(null);
    requestAnimationFrame(loop);
  }

  function finish(win) {
    playing = false;
    const bonus = win ? 100 + g.stage * 20 : 0;
    const total = g.earned + bonus;
    save.coins += total;
    // 經驗與升級（無論勝敗都給，勝利加倍）
    const gain = Math.round((15 + g.stage * 8) * (win ? 2 : 1));
    const ups = [];
    g.members.forEach(mm => {
      const id = mm.c.id;
      save.xp[id] = (save.xp[id] || 0) + gain;
      let lv = save.lv[id] || 1, n = 0;
      while (save.xp[id] >= xpNeed(lv)) { save.xp[id] -= xpNeed(lv); lv++; n++; }
      if (n) { save.lv[id] = lv; ups.push(`${mm.c.name} Lv${lv}`); }
    });
    if (win && g.stage >= save.maxStage) save.maxStage = g.stage + 1;
    if (win) save.stage = Math.min(save.maxStage, g.stage + 1);
    persist();
    $('res-title').textContent = win ? `第 ${g.stage} 關 通關！` : '全隊倒下了…';
    $('res-text').innerHTML = `獲得查克拉幣 ${total}（擊敗 ${g.kills} 人${win ? ` + 通關獎勵 ${bonus}` : ''}）<br>` +
      `全隊 +${gain} 經驗${ups.length ? `　<span style="color:#ffd35c">升級！${ups.join('、')}</span>` : ''}`;
    $('r-next').textContent = win ? '下一關' : '再挑戰一次';
    $('r-next').onclick = () => startStage(save.stage);
    show('result');
  }

  // ---------- 戰鬥邏輯 ----------
  const active = () => g.members[g.idx];
  const overlap = (ax, ay, aw, ah, bx, by, bw, bh) => ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  const text = (x, y, s, color) => g.texts.push({ x, y, s, color: color || '#fff', t: 0.8 });

  function spawnEnemy(type, x) {
    const s = 1 + 0.3 * (g.stage - 1), dm = 1 + 0.15 * (g.stage - 1);
    const defs = {
      grunt:   { hp: 40 * s, dmg: 8 * dm,  spd: 95, range: 42, reward: 5,  w: 32, h: 60, color: '#6a4a8a' },
      shooter: { hp: 30 * s, dmg: 7 * dm,  spd: 70, range: 42, reward: 8,  w: 32, h: 60, color: '#4a6a4a' },
      boss:    { hp: 600 * s, dmg: 18 * dm, spd: 75, range: 80, reward: 100, w: 70, h: 112, color: '#8a2a2a' },
    };
    const d = defs[type];
    const e = { type, x, y: GROUND, vy: 0, hp: d.hp, maxhp: d.hp, dmg: d.dmg, spd: d.spd, range: d.range, reward: d.reward,
      w: d.w, h: d.h, color: d.color, face: -1, cd: rnd(0.5, 1.5), hurt: 0, windup: 0 };
    g.enemies.push(e);
    if (type === 'boss') g.boss = e;
  }

  function hitEnemy(e, dmg, kx) {
    if (e.hp <= 0) return;
    e.hp -= dmg; e.hurt = 0.15; e.x += kx * 10;
    text(e.x, e.y - e.h - 6, Math.round(dmg), '#ffd35c');
    if (e.hp <= 0) {
      g.earned += e.reward; g.kills++;
      text(e.x, e.y - e.h - 22, `+${e.reward}`, '#ffc93c');
      if (e === g.boss) { g.over = true; setTimeout(() => finish(true), 1200); }
    }
  }

  function hurtPlayer(d, fromX) {
    const p = g.p; if (p.inv > 0 || g.over) return;
    const m = active();
    m.hp -= d; p.inv = 0.9; p.vy = -180; p.vx = (p.x < fromX ? -1 : 1) * 150;
    p.combo = 0; p.comboT = 0;
    text(p.x, p.y - 80, Math.round(d), '#ff6b6b');
    if (m.hp <= 0) {
      m.hp = 0;
      const next = g.members.findIndex(x => x.hp > 0);
      if (next < 0) { g.over = true; setTimeout(() => finish(false), 900); }
      else { g.idx = next; p.inv = 1.2; text(p.x, p.y - 100, `${g.members[next].c.name} 上場！`, '#8fd6ff'); }
    }
  }

  function shoot(x, y, vx, dmg, team, opt = {}) {
    g.shots.push({ x, y, vx, vy: opt.vy || 0, dmg, team, life: opt.life || 1.4, pierce: !!opt.pierce,
      w: opt.w || 22, h: opt.h || 10, color: opt.color || '#ddd', theme: opt.theme || null, hit: new Set() });
  }

  function useSkill() {
    const m = active(), c = m.c, p = g.p, sk = c.skill;
    if (m.cd > 0 || g.over) return;
    m.cd = sk.cd;
    const dmg = m.atk * sk.mult, f = p.face;
    const th = window.FX ? window.FX.theme(c) : null;
    const addFx = (max, dur) => g.fx.push({ x: p.x, y: p.y - 30, age: 0, dur, max, face: f, theme: th, color: c.color });
    text(p.x, p.y - 100, sk.name, '#fff');
    if (sk.type === 'rush') { p.dashT = 0.25; p.dashHit = new Set(); p.inv = Math.max(p.inv, 0.3); p.vx = f * 900; p.theme = th; }
    else if (sk.type === 'fire') shoot(p.x + f * 30, p.y - 40, f * 520, dmg, 'p', { w: 60, h: 40, pierce: true, color: '#ff7a2a', life: 1.2, theme: th });
    else if (sk.type === 'burst') {
      addFx(150, 0.5);
      g.enemies.forEach(e => { if (Math.abs(e.x - p.x) < 150 + e.w / 2 && Math.abs(e.y - p.y) < 90) hitEnemy(e, dmg, e.x > p.x ? 1 : -1); });
    } else if (sk.type === 'barrage') {
      for (let i = -2; i <= 2; i++) shoot(p.x + f * 20, p.y - 40, f * 620, dmg, 'p', { vy: i * 60, color: '#cfd8ff', w: 18, h: 10, life: 0.9, theme: th });
    } else if (sk.type === 'heal') {
      const heal = Math.round(m.maxhp * 0.3);
      g.members.forEach(x => { if (x.hp > 0) x.hp = Math.min(x.maxhp, x.hp + heal); });
      addFx(120, 0.7);
      text(p.x, p.y - 90, `全隊 +${heal}`, '#6fe08a');
    }
  }

  function updatePlayer(dt) {
    const p = g.p, m = active(), c = m.c;
    p.atkCd -= dt; p.atkT -= dt; p.inv -= dt; m.cd -= dt; p.rollCd -= dt;
    if (p.comboT > 0) { p.comboT -= dt; if (p.comboT <= 0) p.combo = 0; }
    for (let i = 1; i <= 3; i++) {
      if (pressed['s' + i] && g.members[i - 1] && g.members[i - 1].hp > 0 && g.idx !== i - 1) { g.idx = i - 1; p.inv = Math.max(p.inv, 0.4); }
    }
    const dir = (keys.right ? 1 : 0) - (keys.left ? 1 : 0);

    // 技能突進（rush 技能用）
    if (p.dashT > 0) {
      p.dashT -= dt;
      const dmg = m.atk * c.skill.mult;
      g.enemies.forEach(e => {
        if (!p.dashHit.has(e) && overlap(p.x - 20, p.y - 64, 40, 64, e.x - e.w / 2, e.y - e.h, e.w, e.h)) { p.dashHit.add(e); hitEnemy(e, dmg, p.face); }
      });
      if (p.dashT <= 0) p.vx = 0;
      p.vy += 1800 * dt; p.x = clampX(p.x + p.vx * dt); p.y = Math.min(GROUND, p.y + p.vy * dt);
      if (p.y >= GROUND) { p.y = GROUND; p.vy = 0; p.onG = true; }
      return;
    }

    // 翻滾閃避：無敵幀，直接躲傷害
    if (pressed.dodge && p.rollCd <= 0 && p.rollT <= 0) {
      p.rollT = 0.42; p.rollCd = 1.0; p.inv = Math.max(p.inv, 0.5);
      p.face = dir || p.face; p.vx = p.face * 640; p.combo = 0;
    }
    if (p.rollT > 0) {
      p.rollT -= dt; p.vx *= 0.9;
      p.vy += 1800 * dt; p.x = clampX(p.x + p.vx * dt); p.y = Math.min(GROUND, p.y + p.vy * dt);
      if (p.y >= GROUND) { p.y = GROUND; p.vy = 0; p.onG = true; }
      return;
    }

    // 移動與跳躍
    if (dir) { p.face = dir; p.vx = dir * c.spd; }
    else p.vx *= 0.8;
    if (pressed.jump && p.onG) { p.vy = -640; p.onG = false; }
    if (pressed.skill) useSkill();

    // 普攻連段：三段，第三段擊飛
    if (keys.atk && p.atkCd <= 0) {
      p.combo = (p.combo % 3) + 1; p.comboT = 0.7; p.atkT = 0.16;
      const hard = p.combo === 3;
      p.atkCd = hard ? 0.5 : 0.24;
      const reach = hard ? 96 : 76, dmg = m.atk * (hard ? 1.9 : 1);
      const x0 = p.face > 0 ? p.x + 6 : p.x - 6 - reach;
      let hit = false;
      g.enemies.forEach(e => {
        if (e.hp > 0 && overlap(x0, p.y - 74, reach, 74, e.x - e.w / 2, e.y - e.h, e.w, e.h)) {
          hitEnemy(e, dmg, p.face * (hard ? 3 : 1)); if (hard) { e.vy = -320; e.air = 0.5; } hit = true;
        }
      });
      if (hard && hit) p.vx = p.face * 220;
      g.fx.push({ slash: 1, x: p.x + p.face * (reach * 0.5), y: p.y - 38, face: p.face, age: 0, dur: 0.16, max: reach, hard });
    }

    p.vy += 1800 * dt;
    p.x = clampX(p.x + p.vx * dt);
    p.y += p.vy * dt;
    if (p.y >= GROUND) { p.y = GROUND; p.vy = 0; p.onG = true; }
  }
  const clampX = x => Math.max(20, Math.min(WORLD - 20, x));

  function updateEnemies(dt) {
    const p = g.p;
    for (const e of g.enemies) {
      if (e.hp <= 0) continue;
      e.hurt -= dt;
      if (e.air > 0) { // 被擊飛，落地前無法行動
        e.air -= dt; e.vy = (e.vy || 0) + 1800 * dt; e.y += e.vy * dt;
        if (e.y >= GROUND) { e.y = GROUND; e.vy = 0; e.air = 0; }
        continue;
      }
      e.cd -= dt;
      const dx = p.x - e.x, dist = Math.abs(dx);
      e.face = dx >= 0 ? 1 : -1;
      if (e.windup > 0) {
        e.windup -= dt;
        if (e.windup <= 0 && Math.abs(p.x - e.x) < e.range + 30 && p.y > e.y - e.h) hurtPlayer(e.dmg, e.x);
        continue;
      }
      if (e.type === 'shooter') {
        if (dist < 260) e.x -= e.face * e.spd * dt;
        else if (dist > 380) e.x += e.face * e.spd * dt;
        if (e.cd <= 0 && dist < 520) { e.cd = 2; shoot(e.x, e.y - 36, e.face * 340, e.dmg, 'e', { color: '#8a8a8a', w: 16, h: 5, life: 2 }); }
      } else {
        if (dist > e.range) e.x += e.face * e.spd * dt;
        else if (e.cd <= 0) { e.cd = e.type === 'boss' ? 1.7 : 1.5; e.windup = e.type === 'boss' ? 0.55 : 0.5; }
        if (e.type === 'boss' && e.cd <= 0 && dist > 200) {
          e.cd = 2.2;
          for (let i = -1; i <= 1; i++) shoot(e.x, e.y - 60, e.face * 380, e.dmg * 0.7, 'e', { vy: i * 50, color: '#c22', w: 20, h: 8, life: 2 });
        }
      }
      // 別讓敵人重疊
      for (const o of g.enemies) if (o !== e && o.hp > 0 && Math.abs(o.x - e.x) < 26) e.x += (e.x < o.x ? -1 : 1) * 40 * dt;
    }
    g.enemies = g.enemies.filter(e => e.hp > 0 || (e.dead = (e.dead || 0) + dt) < 0.3);
  }

  function updateShots(dt) {
    const p = g.p;
    for (const s of g.shots) {
      s.x += s.vx * dt; s.y += s.vy * dt; s.life -= dt;
      if (s.team === 'p') {
        for (const e of g.enemies) {
          if (e.hp > 0 && !s.hit.has(e) && overlap(s.x - s.w / 2, s.y - s.h / 2, s.w, s.h, e.x - e.w / 2, e.y - e.h, e.w, e.h)) {
            s.hit.add(e); hitEnemy(e, s.dmg, Math.sign(s.vx));
            if (!s.pierce) s.life = 0;
          }
        }
      } else if (overlap(s.x - s.w / 2, s.y - s.h / 2, s.w, s.h, p.x - 15, p.y - 64, 30, 64)) {
        hurtPlayer(s.dmg, s.x); s.life = 0;
      }
    }
    g.shots = g.shots.filter(s => s.life > 0 && s.x > -50 && s.x < WORLD + 50);
  }

  function updateSpawns() {
    const p = g.p, alive = g.enemies.filter(e => e.hp > 0).length;
    if (!g.bossSpawned && p.x > WORLD - 800) { g.bossSpawned = true; spawnEnemy('boss', Math.min(WORLD - 60, g.cam + W + 80)); }
    if (!g.bossSpawned && p.x > g.nextSpawn - 500 && g.nextSpawn < WORLD - 900) {
      const n = Math.min(5, 2 + Math.floor(g.stage / 2));
      for (let i = 0; i < n && alive + i < 8; i++) spawnEnemy(Math.random() < 0.3 ? 'shooter' : 'grunt', g.cam + W + 40 + i * 70);
      g.nextSpawn += 450;
    }
  }

  function update(dt) {
    T += dt;
    if (!g.over) { updatePlayer(dt); updateSpawns(); }
    else { g.p.vy += 1800 * dt; g.p.y = Math.min(GROUND, g.p.y + g.p.vy * dt); }
    updateEnemies(dt); updateShots(dt);
    g.cam = Math.max(0, Math.min(WORLD - W, g.p.x - 330));
    g.texts.forEach(t => { t.t -= dt; t.y -= 30 * dt; });
    g.texts = g.texts.filter(t => t.t > 0);
    g.fx.forEach(f => { f.age += dt; });
    g.fx = g.fx.filter(f => f.age < f.dur);
    for (const k in pressed) pressed[k] = false;
  }

  // ---------- 繪圖 ----------
  function drawBg() {
    const grad = ctx.createLinearGradient(0, 0, 0, GROUND);
    grad.addColorStop(0, '#1c2b5a'); grad.addColorStop(1, '#e9a56a');
    ctx.fillStyle = grad; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = 'rgba(255,240,200,.9)'; ctx.beginPath(); ctx.arc(760, 120, 40, 0, 7); ctx.fill();
    // 遠山（視差）
    ctx.fillStyle = '#2a2f4a';
    for (let i = -1; i < 8; i++) {
      const x = i * 300 - (g.cam * 0.2) % 300;
      ctx.beginPath(); ctx.moveTo(x, GROUND); ctx.lineTo(x + 150, 260 + (i % 3) * 20); ctx.lineTo(x + 300, GROUND); ctx.fill();
    }
    // 樹（視差）
    ctx.fillStyle = '#1d3a2a';
    for (let i = -1; i < 12; i++) {
      const x = i * 130 - (g.cam * 0.55) % 130;
      ctx.fillRect(x + 20, GROUND - 90, 14, 90);
      ctx.beginPath(); ctx.arc(x + 27, GROUND - 100, 42, 0, 7); ctx.fill();
    }
    ctx.fillStyle = '#5a3f2a'; ctx.fillRect(0, GROUND, W, H - GROUND);
    ctx.fillStyle = '#3f7a3a'; ctx.fillRect(0, GROUND, W, 8);
  }

  function drawNinja(x, y, face, c, o = {}) {
    ctx.save(); ctx.translate(x, y); ctx.scale(face, 1);
    if (o.flash) ctx.globalAlpha = 0.5;
    const walk = o.walk ? Math.sin(T * 16) * 5 : 0, s = o.scale || 1;
    ctx.scale(s, s);
    if (window.drawChibi) { window.drawChibi(ctx, c, o, T); ctx.restore(); return; }
    ctx.fillStyle = '#20232f';
    ctx.fillRect(-10 + walk, -22, 9, 22); ctx.fillRect(1 - walk, -22, 9, 22);
    ctx.fillStyle = c.color; ctx.fillRect(-14, -48, 28, 28);
    ctx.fillStyle = '#f2c9a0'; ctx.beginPath(); ctx.arc(0, -58, 11, 0, 7); ctx.fill();
    ctx.fillStyle = c.hair; ctx.beginPath(); ctx.arc(0, -61, 11.5, Math.PI, 0); ctx.fill();
    ctx.beginPath(); ctx.moveTo(-10, -64); ctx.lineTo(-4, -76); ctx.lineTo(2, -65); ctx.lineTo(8, -75); ctx.lineTo(11, -63); ctx.fill();
    if (!o.enemy) { ctx.fillStyle = '#8fa4c8'; ctx.fillRect(-11, -62, 22, 4); ctx.fillStyle = '#dde'; ctx.fillRect(-3, -62, 6, 4); }
    else { ctx.fillStyle = '#222'; ctx.fillRect(-11, -56, 22, 6); }
    ctx.fillStyle = '#111'; ctx.fillRect(3, -60, 3, 3);
    if (o.atk > 0) {
      ctx.strokeStyle = 'rgba(255,255,255,.85)'; ctx.lineWidth = 5;
      ctx.beginPath(); ctx.arc(8, -36, 46, -1.1, 0.9); ctx.stroke();
    } else { ctx.fillStyle = c.color; ctx.fillRect(10, -44, 12, 7); }
    ctx.restore();
  }

  function draw() {
    drawBg();
    ctx.save(); ctx.translate(-Math.round(g.cam), 0);
    // 敵人
    for (const e of g.enemies) {
      const c = { color: e.color, hair: '#222' };
      const dying = e.hp <= 0;
      if (dying) ctx.globalAlpha = 0.4;
      drawNinja(e.x, e.y, e.face, c, { enemy: true, scale: e.type === 'boss' ? 1.7 : 1, flash: e.hurt > 0, atk: e.windup > 0 ? 1 : 0, walk: true });
      ctx.globalAlpha = 1;
      if (!dying) {
        const bw = e.type === 'boss' ? 90 : 40, by = e.y - e.h - 22;
        ctx.fillStyle = '#000a'; ctx.fillRect(e.x - bw / 2, by, bw, 5);
        ctx.fillStyle = '#e04a4a'; ctx.fillRect(e.x - bw / 2, by, bw * Math.max(0, e.hp / e.maxhp), 5);
        if (e.windup > 0) { // 出手預警
          ctx.fillStyle = Math.floor(T * 12) % 2 ? '#ff3b3b' : '#ffd35c';
          ctx.font = 'bold 22px sans-serif'; ctx.textAlign = 'center';
          ctx.fillText('!', e.x, e.y - e.h - 26);
        }
      }
    }
    // 玩家
    const p = g.p, m = active();
    const blink = p.inv > 0 && Math.floor(T * 20) % 2 === 0;
    const dashing = p.dashT > 0 && window.FX && p.theme;
    if (dashing) window.FX.dash(ctx, p.x, p.y, p.face, p.theme, p.dashT / 0.25, T, bx => drawNinja(bx, p.y, p.face, m.c, { atk: 1 }));
    drawNinja(p.x, p.y, p.face, m.c, { walk: Math.abs(p.vx) > 40 && p.onG, atk: dashing ? 1 : p.atkT, flash: blink });
    ctx.fillStyle = '#fff'; ctx.font = '12px sans-serif'; ctx.textAlign = 'center';
    ctx.fillText(m.c.name, p.x, p.y - 84);
    // 飛行物與技能特效
    for (const s of g.shots) {
      if (window.FX && s.theme) window.FX.shot(ctx, s, T);
      else { ctx.fillStyle = s.color; ctx.beginPath(); ctx.ellipse(s.x, s.y, s.w / 2, s.h / 2, 0, 0, 7); ctx.fill(); }
    }
    for (const f of g.fx) {
      if (f.slash) {
        const k = f.age / f.dur;
        ctx.strokeStyle = f.hard ? '#ffd35c' : '#ffffff'; ctx.globalAlpha = Math.max(0, 1 - k); ctx.lineWidth = f.hard ? 7 : 4;
        ctx.beginPath(); ctx.arc(f.x - f.face * 20, f.y, f.max * 0.7, f.face > 0 ? -1.1 : Math.PI - 1.1, f.face > 0 ? 1.1 : Math.PI + 1.1); ctx.stroke();
        ctx.globalAlpha = 1;
      } else if (window.FX && f.theme) window.FX.burst(ctx, f, T);
      else { ctx.strokeStyle = f.color; ctx.globalAlpha = Math.max(0, 1 - f.age / f.dur); ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(f.x, f.y, f.max * f.age / f.dur, 0, 7); ctx.stroke(); ctx.globalAlpha = 1; }
    }
    ctx.font = 'bold 18px sans-serif';
    for (const t of g.texts) { ctx.fillStyle = t.color; ctx.strokeStyle = '#000'; ctx.lineWidth = 3; ctx.strokeText(t.s, t.x, t.y); ctx.fillText(t.s, t.x, t.y); }
    ctx.restore();
    drawHud();
  }

  function drawHud() {
    ctx.textAlign = 'left';
    g.members.forEach((m, i) => {
      const x = 12 + i * 178, y = 12, on = i === g.idx;
      ctx.fillStyle = on ? '#000c' : '#0008'; ctx.fillRect(x, y, 170, 50);
      if (on) { ctx.strokeStyle = '#ff8a1f'; ctx.lineWidth = 2; ctx.strokeRect(x, y, 170, 50); }
      if (window.chibiPortrait) ctx.drawImage(window.chibiPortrait(m.c), x + 5, y + 5, 40, 40);
      else { ctx.fillStyle = m.c.color; ctx.beginPath(); ctx.arc(x + 25, y + 25, 18, 0, 7); ctx.fill(); }
      if (m.hp <= 0) { ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.beginPath(); ctx.arc(x + 25, y + 25, 20, 0, 7); ctx.fill(); }
      ctx.fillStyle = '#fff'; ctx.font = '12px sans-serif'; ctx.fillText(`[${i + 1}] ${m.c.name}`, x + 50, y + 16);
      ctx.fillStyle = '#ffd35c'; ctx.font = '10px sans-serif'; ctx.textAlign = 'right'; ctx.fillText(`Lv${lvOf(m.c.id)}`, x + 165, y + 16); ctx.textAlign = 'left';
      ctx.fillStyle = '#333'; ctx.fillRect(x + 50, y + 22, 110, 8);
      ctx.fillStyle = m.hp > 0 ? '#5ad07a' : '#555'; ctx.fillRect(x + 50, y + 22, 110 * m.hp / m.maxhp, 8);
      ctx.fillStyle = '#333'; ctx.fillRect(x + 50, y + 34, 110, 6);
      const ready = m.cd <= 0;
      ctx.fillStyle = ready ? '#4aa8ff' : '#2a5a8a'; ctx.fillRect(x + 50, y + 34, 110 * (ready ? 1 : 1 - m.cd / m.c.skill.cd), 6);
    });
    ctx.fillStyle = '#ffc93c'; ctx.font = 'bold 18px sans-serif'; ctx.textAlign = 'right';
    ctx.fillText(`本關 +${g.earned}`, W - 14, 30);
    ctx.fillStyle = '#fff'; ctx.font = '13px sans-serif'; ctx.fillText(`第 ${g.stage} 關`, W - 14, 50);
    // 連段數
    if (g.p.combo > 1 && g.p.comboT > 0) {
      ctx.textAlign = 'center'; ctx.fillStyle = '#ffd35c'; ctx.font = 'bold 30px sans-serif';
      ctx.fillText(`${g.p.combo} 連段`, W / 2, 96);
    }
    // 閃避冷卻
    ctx.textAlign = 'left';
    const rr = g.p.rollCd <= 0;
    ctx.fillStyle = rr ? '#7ad0ff' : '#345'; ctx.font = '12px sans-serif';
    ctx.fillText(rr ? '閃避 就緒 (L)' : '閃避 冷卻中', 14, H - 30);
    // 進度條
    ctx.fillStyle = '#0008'; ctx.fillRect(W / 2 - 150, H - 20, 300, 8);
    ctx.fillStyle = '#ff8a1f'; ctx.fillRect(W / 2 - 150, H - 20, 300 * g.p.x / WORLD, 8);
    if (g.boss && g.boss.hp > 0) {
      ctx.fillStyle = '#0009'; ctx.fillRect(W / 2 - 200, H - 44, 400, 12);
      ctx.fillStyle = '#e04a4a'; ctx.fillRect(W / 2 - 200, H - 44, 400 * g.boss.hp / g.boss.maxhp, 12);
    }
  }

  function loop(now) {
    if (!playing) return;
    const dt = Math.min(0.033, (now - last) / 1000); last = now;
    update(dt); draw();
    requestAnimationFrame(loop);
  }

  show('menu');
})();

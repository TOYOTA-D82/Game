// Chained Tower trailer: real course data (levels.json, exported from the
// game's own generator) rendered with three.js. Fully deterministic:
// window.renderAt(t) draws the frame for time t (seconds).
import * as THREE from 'three';

const params = new URLSearchParams(location.search);
const W = +(params.get('w') || 1080);
const H = +(params.get('h') || 1920);
const VERTICAL = H > W;
const U = Math.min(W, H) / 1080; // UI scale

const levels = await (await fetch('levels.json')).json();
const LV = Object.fromEntries(levels.map((l) => [l.id, l]));

// ---------------------------------------------------------------- renderer
const stage = document.getElementById('stage');
stage.style.width = W + 'px';
stage.style.height = H + 'px';
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
stage.prepend(renderer.domElement);

const camera = new THREE.PerspectiveCamera(VERTICAL ? 68 : 52, W / H, 0.5, 5000);
const V = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const col = (c) => new THREE.Color().setRGB(c[0] / 255, c[1] / 255, c[2] / 255, THREE.SRGBColorSpace);
const lerpC = (a, b, k) => a.clone().lerp(b, k);
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const smooth = (x) => x * x * (3 - 2 * x);

// ---------------------------------------------------------------- textures
function radialTexture(inner, outer) {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const grd = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  grd.addColorStop(0, inner);
  grd.addColorStop(0.35, outer);
  grd.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
function starTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const grd = g.createRadialGradient(32, 32, 0, 32, 32, 30);
  grd.addColorStop(0, 'rgba(255,255,255,1)');
  grd.addColorStop(0.15, 'rgba(255,255,255,0.9)');
  grd.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grd;
  g.beginPath();
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    const r = i % 2 === 0 ? 30 : 7;
    g.lineTo(32 + Math.cos(a) * r, 32 + Math.sin(a) * r);
  }
  g.fill();
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const TEX = {
  glow: radialTexture('rgba(255,255,255,1)', 'rgba(255,255,255,0.55)'),
  star: starTexture(),
};

// ---------------------------------------------------------------- level meshes
const BOX = new THREE.BoxGeometry(1, 1, 1);
const EDGES = new THREE.EdgesGeometry(BOX);
const edgeMat = new THREE.LineBasicMaterial({ color: 0x1b1636, transparent: true, opacity: 0.28 });

function mat(color, o = {}) {
  return new THREE.MeshStandardMaterial({
    color,
    roughness: o.rough ?? 0.75,
    metalness: o.metal ?? 0.0,
    emissive: o.emissive ? color : 0x000000,
    emissiveIntensity: o.emissive ?? 0,
    transparent: o.opacity !== undefined,
    opacity: o.opacity ?? 1,
  });
}

function boxMesh(group, c, z, material, edges = true) {
  const m = new THREE.Mesh(BOX, material);
  m.position.set(c[0], c[1], c[2]);
  m.scale.set(z[0], z[1], z[2]);
  m.castShadow = true;
  m.receiveShadow = true;
  group.add(m);
  if (edges) {
    const e = new THREE.LineSegments(EDGES, edgeMat);
    m.add(e);
  }
  return m;
}

function skyFor(L) {
  const atm = col(L.sky.atmosphere);
  const night = L.sky.clock >= 19 || L.sky.clock < 6;
  const top = night ? lerpC(atm, new THREE.Color(0x070718), 0.75) : lerpC(atm, col([60, 120, 230]), 0.55);
  const horizon = night ? lerpC(atm, new THREE.Color(0x222244), 0.3) : lerpC(atm, new THREE.Color(0xffffff), 0.35);
  return { top, horizon, night, atm };
}

function buildLevel(L) {
  const g = new THREE.Group();
  const pal = L.colors.map(col);
  const lm = L.landmark.colors.map(col);
  const anim = [];
  const pick = (s) => pal[((s % pal.length) + pal.length) % pal.length];
  for (const p of L.pieces) {
    const base = pick(p.s ?? 0);
    let m;
    let o = {};
    let color = base;
    switch (p.k) {
      case 'checkpoint': color = col(L.checkpoint); break;
      case 'win': color = col([255, 205, 60]); o = { emissive: 0.35 }; break;
      case 'kill': color = col([255, 95, 20]); o = { emissive: 1.4, rough: 0.4 }; break;
      case 'breakable': color = col([190, 120, 70]); break;
      case 'truss': color = col([200, 200, 210]); o = { metal: 0.6, rough: 0.35 }; break;
      case 'pad': color = col(L.pad); o = { emissive: 0.8 }; break;
      case 'vanish': color = lerpC(base, new THREE.Color(1, 1, 1), 0.45); o = { opacity: 0.72, rough: 0.1 }; break;
      case 'current': color = p.style === 'belt' ? col([45, 45, 50]) : col([50, 150, 255]); o = p.style === 'belt' ? { metal: 0.5 } : { opacity: 0.78, rough: 0.1, emissive: 0.15 }; break;
      case 'mover': color = lerpC(base, col([255, 220, 90]), 0.5); break;
      case 'crumble': color = lerpC(base, col([150, 110, 80]), 0.6); break;
      case 'fragile': color = col([170, 230, 255]); o = { opacity: 0.75, rough: 0.1 }; break;
      case 'slide': color = col([190, 235, 255]); o = { rough: 0.15 }; break;
      case 'sweeper': color = p.z[1] <= 3 ? col([255, 170, 40]) : col([230, 60, 60]); break;
      case 'spinner': color = col([235, 70, 70]); o = { emissive: 0.7 }; break;
      case 'pivot': color = col([60, 60, 70]); o = { metal: 0.5 }; break;
      case 'building': color = lerpC(lm[0], base, 0.3); break;
      case 'wall': color = lm[0]; break;
      case 'roof': color = lm[1] || lm[0]; break;
      case 'rock': color = lerpC(base, col([80, 75, 85]), 0.35); break;
      default: break;
    }
    m = boxMesh(g, p.c, p.z, mat(color, o), p.k !== 'kill');
    if (p.k === 'mover' || p.k === 'sweeper') {
      anim.push({ type: 'move', m, p });
    } else if (p.k === 'spinner') {
      anim.push({ type: 'spin', m, p });
    } else if (p.k === 'building') {
      // window rows
      const top = p.c[1] + p.z[1] / 2;
      for (let row = 1; row <= Math.floor((p.z[1] - 4) / 5); row++) {
        boxMesh(g, [p.c[0], top - 2 - row * 5, p.c[2]], [p.z[0] + 0.12, 1.2, p.z[2] + 0.12], mat(col([255, 235, 170]), { emissive: 0.9, opacity: 0.6 }), false).castShadow = false;
      }
    } else if (p.k === 'checkpoint' && (p.index ?? 0) > 0) {
      // trim + flag, like in the game
      const t = p.c[1] + p.z[1] / 2;
      const cc = col(L.checkpoint);
      boxMesh(g, [p.c[0], t + 0.12, p.c[2]], [p.z[0] + 0.3, 0.25, p.z[2] + 0.3], mat(cc, { emissive: 0.6 }), false);
      const fx = p.c[0] + p.z[0] / 2 - 0.8, fz = p.c[2] + p.z[2] / 2 - 0.8;
      boxMesh(g, [fx, t + 3, fz], [0.25, 6, 0.25], mat(new THREE.Color(0xffffff)), false);
      boxMesh(g, [fx + 1.1, t + 5.2, fz], [2, 1.3, 0.12], mat(cc, { emissive: 0.4 }), false);
    } else if (p.k === 'win') {
      const t = p.c[1] + p.z[1] / 2;
      const cup = new THREE.Group();
      const gold = mat(col([255, 205, 60]), { metal: 0.8, rough: 0.25, emissive: 0.25 });
      const bowl = new THREE.Mesh(new THREE.CylinderGeometry(1.6, 0.7, 2.2, 20), gold);
      bowl.position.y = 3.6;
      const stem = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 1.4, 12), gold);
      stem.position.y = 1.9;
      const foot = new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.1, 0.5, 20), gold);
      foot.position.y = 1.0;
      cup.add(bowl, stem, foot);
      cup.position.set(p.c[0], t, p.c[2]);
      cup.traverse((x) => (x.castShadow = true));
      g.add(cup);
      anim.push({ type: 'trophy', m: cup });
    }
  }
  // the goal landmark
  const cps = L.checkpoints;
  const last = cps[cps.length - 1];
  const height = L.top - L.bottom + 60;
  let lx, lz;
  if (L.mode === 'tower') {
    lx = L.center[0];
    lz = L.center[1];
  } else {
    lx = last[0] + L.finishDir[0] * 75;
    lz = last[2] + L.finishDir[1] * 75;
  }
  const lmMat = mat(lm[0], { rough: 0.9 });
  if (L.landmark.shape === 'taper') {
    const r = L.mode === 'tower' ? 20 : 48;
    const cone = new THREE.Mesh(L.landmark.round ? new THREE.ConeGeometry(r, height, 7) : new THREE.ConeGeometry(r, height, 4), lmMat);
    cone.position.set(lx, L.bottom - 30 + height / 2, lz);
    cone.receiveShadow = true;
    g.add(cone);
    if (L.landmark.cap) {
      const cap = new THREE.Mesh(L.landmark.round ? new THREE.ConeGeometry(r * 0.28, height * 0.28, 7) : new THREE.ConeGeometry(r * 0.28, height * 0.28, 4), mat(col(L.landmark.cap), { emissive: 0.15 }));
      cap.position.set(lx, L.bottom - 30 + height - height * 0.14 + 0.5, lz);
      g.add(cap);
    }
  } else {
    const r = L.mode === 'tower' ? 15 : 13;
    const colH = L.top - L.bottom + 45;
    const geo = L.landmark.round ? new THREE.CylinderGeometry(r, r * 1.1, colH, 16) : new THREE.BoxGeometry(r * 2, colH, r * 2);
    const tower = new THREE.Mesh(geo, lmMat);
    tower.position.set(lx, L.bottom - 20 + colH / 2, lz);
    tower.receiveShadow = true;
    g.add(tower);
    if (lm[1]) {
      for (let i = 1; i <= 6; i++) {
        const band = new THREE.Mesh(L.landmark.round ? new THREE.CylinderGeometry(r + 0.4, r + 0.4, 1.2, 16) : new THREE.BoxGeometry(r * 2 + 0.8, 1.2, r * 2 + 0.8), mat(lm[1], { emissive: 0.9 }));
        band.position.set(lx, L.bottom - 20 + (colH * i) / 7, lz);
        g.add(band);
      }
    }
  }
  // ground far below
  if (L.floor) {
    const fl = new THREE.Mesh(new THREE.PlaneGeometry(6000, 6000), mat(col(L.floor.color), { rough: 1 }));
    fl.rotation.x = -Math.PI / 2;
    fl.position.y = L.bottom - 40;
    fl.receiveShadow = true;
    g.add(fl);
  }
  // scattered background blocks/clouds so the world doesn't feel empty
  let seed = 1234 + L.id.length * 77;
  const rnd = () => ((seed = (seed * 48271) % 2147483647) / 2147483647);
  const sky = skyFor(L);
  const cloudMat = mat(sky.night ? new THREE.Color(0x30305a) : new THREE.Color(0xffffff), { opacity: sky.night ? 0.5 : 0.85, rough: 1 });
  let cx = 0, cz = 0;
  for (const c of cps) { cx += c[0] / cps.length; cz += c[2] / cps.length; }
  for (let i = 0; i < 26; i++) {
    const a = rnd() * Math.PI * 2;
    const r = 260 + rnd() * 420;
    const y = L.bottom + 10 + rnd() * (L.top - L.bottom + 90);
    const s = 18 + rnd() * 40;
    const m = new THREE.Mesh(BOX, cloudMat);
    m.position.set(cx + Math.cos(a) * r, y, cz + Math.sin(a) * r);
    m.scale.set(s * 1.8, s * 0.35, s);
    g.add(m);
  }
  return { g, anim, L, sky };
}

// ---------------------------------------------------------------- sky + lights
const scene = new THREE.Scene();
const skyMat = new THREE.ShaderMaterial({
  side: THREE.BackSide,
  depthWrite: false,
  uniforms: { top: { value: new THREE.Color() }, horizon: { value: new THREE.Color() } },
  vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
  fragmentShader: 'uniform vec3 top; uniform vec3 horizon; varying vec3 vP; void main(){ float k = clamp(vP.y*1.6+0.15,0.0,1.0); gl_FragColor = vec4(mix(horizon, top, k),1.0); }',
});
const skyDome = new THREE.Mesh(new THREE.SphereGeometry(2400, 32, 16), skyMat);
scene.add(skyDome);
const hemi = new THREE.HemisphereLight(0xffffff, 0x445566, 1.1);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xffffff, 2.2);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.camera.left = -70;
sun.shadow.camera.right = 70;
sun.shadow.camera.top = 70;
sun.shadow.camera.bottom = -70;
sun.shadow.camera.near = 1;
sun.shadow.camera.far = 400;
sun.shadow.bias = -0.0006;
scene.add(sun, sun.target);

// stars for night skies
const starGeo = new THREE.BufferGeometry();
{
  const pts = [];
  let s = 99;
  const r = () => ((s = (s * 48271) % 2147483647) / 2147483647);
  for (let i = 0; i < 900; i++) {
    const a = r() * Math.PI * 2, y = r() * 0.9 + 0.08;
    const k = Math.sqrt(1 - y * y);
    pts.push(Math.cos(a) * k * 2200, y * 2200, Math.sin(a) * k * 2200);
  }
  starGeo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
}
const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({ color: 0xffffff, size: 3, sizeAttenuation: false }));
scene.add(stars);

// ---------------------------------------------------------------- avatars
function makeAvatar(color) {
  const g = new THREE.Group();
  const body = mat(col(color), { rough: 0.55 });
  const dark = mat(lerpC(col(color), new THREE.Color(0, 0, 0), 0.25), { rough: 0.55 });
  const part = (size, pos, m) => {
    const x = new THREE.Mesh(BOX, m);
    x.scale.set(...size);
    x.position.set(...pos);
    x.castShadow = true;
    x.add(new THREE.LineSegments(EDGES, new THREE.LineBasicMaterial({ color: 0x1b1636, transparent: true, opacity: 0.55 })));
    return x;
  };
  const pivot = (pos) => {
    const p = new THREE.Group();
    p.position.set(...pos);
    g.add(p);
    return p;
  };
  const torso = part([2, 2, 1], [0, 3, 0], body);
  const head = part([1.35, 1.35, 1.35], [0, 4.75, 0], body);
  const eyeM = mat(new THREE.Color(0x1b1636));
  for (const x of [-0.3, 0.3]) {
    const e = new THREE.Mesh(BOX, eyeM);
    e.scale.set(0.16, 0.3, 0.05);
    e.position.set(x, 0.12 * 1, 0.7);
    head.add(e);
    e.scale.divide(head.scale);
    e.position.divide(head.scale);
  }
  g.add(torso, head);
  const hipL = pivot([-0.5, 2, 0]), hipR = pivot([0.5, 2, 0]);
  const shL = pivot([-1.5, 4, 0]), shR = pivot([1.5, 4, 0]);
  hipL.add(part([1, 2, 1], [0, -1, 0], dark));
  hipR.add(part([1, 2, 1], [0, -1, 0], dark));
  shL.add(part([1, 2, 1], [0, -1, 0], body));
  shR.add(part([1, 2, 1], [0, -1, 0], body));
  scene.add(g);
  return { g, hipL, hipR, shL, shR };
}
const red = makeAvatar([235, 70, 70]);
const yellow = makeAvatar([255, 205, 50]);

function pose(av, st, t) {
  const { kind } = st;
  if (kind === 'run') {
    const ph = t * 13;
    const s = Math.sin(ph);
    av.hipL.rotation.x = s * 0.9;
    av.hipR.rotation.x = -s * 0.9;
    av.shL.rotation.x = -s * 0.8;
    av.shR.rotation.x = s * 0.8;
    av.shL.rotation.z = 0;
    av.shR.rotation.z = 0;
  } else if (kind === 'jump' || kind === 'ride') {
    av.hipL.rotation.x = 0.5;
    av.hipR.rotation.x = -0.35;
    av.shL.rotation.x = -2.6;
    av.shR.rotation.x = -2.2;
    av.shL.rotation.z = -0.3;
    av.shR.rotation.z = 0.3;
  } else if (kind === 'climb') {
    const s = Math.sin(t * 10);
    av.shL.rotation.x = -2.9 + s * 0.4;
    av.shR.rotation.x = -2.9 - s * 0.4;
    av.hipL.rotation.x = s * 0.5;
    av.hipR.rotation.x = -s * 0.5;
    av.shL.rotation.z = 0;
    av.shR.rotation.z = 0;
  } else {
    av.hipL.rotation.x = av.hipR.rotation.x = 0;
    av.shL.rotation.x = av.shR.rotation.x = 0;
    av.shL.rotation.z = -0.15;
    av.shR.rotation.z = 0.15;
  }
}

// ---------------------------------------------------------------- path timeline
function timeline(L, speed = 16) {
  const P = L.path;
  const low = L.gravity < 120;
  const segs = [];
  let t = 0;
  const center = (s) => V(s.x, s.top, s.z);
  const into = (s, p) => {
    const ix = s.maxX - s.minX > 1.8 ? clamp(p.x, s.minX + 0.9, s.maxX - 0.9) : s.x;
    const iz = s.maxZ - s.minZ > 1.8 ? clamp(p.z, s.minZ + 0.9, s.maxZ - 0.9) : s.z;
    return V(ix, s.top, iz);
  };
  let entry = center(P[0]);
  for (let i = 0; i < P.length; i++) {
    const s = P[i], n = P[i + 1];
    const exit = n ? into(s, center(n)) : center(s);
    const d = entry.distanceTo(exit);
    if (d > 0.05) {
      segs.push({ kind: 'run', a: entry.clone(), b: exit.clone(), t0: t, t1: t + d / speed });
      t += d / speed;
    }
    if (!n) break;
    const next = into(n, exit);
    const h = Math.hypot(next.x - exit.x, next.z - exit.z);
    const dy = next.y - exit.y;
    if (h < 3 && Math.abs(dy) > 3) {
      const dur = Math.abs(dy) / 11 + 0.15;
      segs.push({ kind: 'climb', a: exit.clone(), b: next.clone(), t0: t, t1: t + dur });
      t += dur;
    } else if (h > 9.5 && Math.abs(dy) < 4) {
      // long gap: there's a moving platform (or a long boosted jump) — ride it
      const mid = exit.clone().lerp(next, 0.5);
      const mover = L.pieces.find((p) => p.k === 'mover' && Math.hypot(p.c[0] - mid.x, p.c[2] - mid.z) < h);
      const dur = h / (speed * 0.75) + 0.3;
      segs.push({ kind: mover ? 'ride' : 'jump', a: exit.clone(), b: next.clone(), t0: t, t1: t + dur, mover, h: low ? 7 : 4 });
      t += dur;
    } else {
      let dur = clamp(0.34 + h * 0.045 + Math.max(dy, 0) * 0.05, 0.36, 0.9);
      if (low) dur *= 1.35;
      const arc = (low ? 4.5 : 2.4) + Math.abs(dy) * 0.45;
      segs.push({ kind: 'jump', a: exit.clone(), b: next.clone(), t0: t, t1: t + dur, h: arc });
      t += dur;
    }
    entry = next;
  }
  // index of the first segment of each section, for picking scene starts
  const sectionStart = {};
  for (let i = 0, k = 0; i < P.length && k < segs.length; i++) {
    const s = P[i].section;
    if (sectionStart[s] === undefined) {
      const seg = segs.find((x) => Math.abs(x.a.x - P[i].x) < 30 && Math.abs(x.a.z - P[i].z) < 30 && Math.abs(x.a.y - P[i].top) < 0.5);
      if (seg) sectionStart[s] = seg.t0;
    }
  }
  return { segs, total: t, sectionStart };
}

function stateAt(tl, t) {
  const segs = tl.segs;
  if (t <= 0) return { p: segs[0].a.clone(), kind: 'idle', dir: segs[0].b.clone().sub(segs[0].a), seg: segs[0] };
  let seg = segs[segs.length - 1];
  for (const s of segs) {
    if (t < s.t1) { seg = s; break; }
  }
  const u = clamp((t - seg.t0) / Math.max(1e-3, seg.t1 - seg.t0), 0, 1);
  const p = seg.a.clone().lerp(seg.b, u);
  if (seg.kind === 'jump') {
    p.y = seg.a.y + (seg.b.y - seg.a.y) * u + 4 * seg.h * u * (1 - u);
  }
  const dir = seg.b.clone().sub(seg.a);
  dir.y = 0;
  return { p, kind: t >= tl.total ? 'idle' : seg.kind, dir, seg, u };
}

function placeAvatar(av, tl, t, lastDir) {
  const st = stateAt(tl, t);
  av.g.position.copy(st.p);
  let dir = st.dir;
  if (dir.lengthSq() < 0.01) dir = lastDir || V(0, 0, 1);
  av.g.rotation.y = Math.atan2(dir.x, dir.z);
  pose(av, st, t);
  return st;
}

// ---------------------------------------------------------------- trails + chain
const spritePool = [];
function sprite() {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: TEX.glow, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  scene.add(s);
  spritePool.push(s);
  return s;
}
for (let i = 0; i < 160; i++) sprite();
let spriteUsed = 0;
function useSprite(pos, scale, color, opacity, tex = TEX.glow) {
  const s = spritePool[spriteUsed++];
  if (!s) return;
  s.visible = true;
  s.position.copy(pos);
  s.scale.set(scale, scale, scale);
  s.material.color.copy(color);
  s.material.opacity = opacity;
  if (s.material.map !== tex) { s.material.map = tex; s.material.needsUpdate = true; }
}
function hideSprites() {
  for (let i = spriteUsed; i < spritePool.length; i++) spritePool[i].visible = false;
  spriteUsed = 0;
}

const FIRE = [new THREE.Color(1, 0.75, 0.25), new THREE.Color(1, 0.42, 0.06), new THREE.Color(0.8, 0.12, 0.03)];
function fireTrail(tl, t) {
  for (let k = 1; k <= 26; k++) {
    const st = stateAt(tl, t - k * 0.028);
    const f = k / 26;
    const c = f < 0.4 ? lerpC(FIRE[0], FIRE[1], f / 0.4) : lerpC(FIRE[1], FIRE[2], (f - 0.4) / 0.6);
    const wob = Math.sin(t * 20 + k) * 0.25;
    useSprite(st.p.clone().add(V(wob, 0.6 + f * 1.6, 0)), 2.1 * (1 - f * 0.5), c, 0.55 * (1 - f));
  }
}
const GAL = [new THREE.Color(1, 0.6, 1), new THREE.Color(0.6, 0.45, 1), new THREE.Color(0.5, 0.85, 1)];
function galaxyTrail(tl, t) {
  for (let k = 1; k <= 30; k++) {
    const st = stateAt(tl, t - k * 0.035);
    const f = k / 30;
    const a = k * 2.4 + t * 3;
    const off = V(Math.cos(a) * 1.3 * f, 2 + Math.sin(a * 1.3) * 1.2, Math.sin(a) * 1.3 * f);
    const tw = 0.6 + 0.4 * Math.sin(t * 12 + k * 1.7);
    useSprite(st.p.clone().add(off), 1.6 * tw * (1 - f * 0.5), GAL[k % 3], 0.95 * (1 - f), TEX.star);
  }
}

const chainLinks = [];
const linkMat = mat(new THREE.Color(0x8a8fa0), { metal: 0.85, rough: 0.3 });
const linkHot = mat(new THREE.Color(0xff6a20), { emissive: 1.2 });
for (let i = 0; i < 16; i++) {
  const l = new THREE.Mesh(new THREE.TorusGeometry(0.42, 0.15, 6, 12), linkMat);
  l.castShadow = true;
  scene.add(l);
  chainLinks.push(l);
}
function chain(a, b, t, burning) {
  const A = a.g.position.clone().add(V(0, 0.6, 0));
  const B = b.g.position.clone().add(V(0, 0.6, 0));
  const dist = A.distanceTo(B);
  const sag = clamp(12 - dist, 0, 12) * 0.35;
  const n = chainLinks.length;
  for (let i = 0; i < n; i++) {
    const u = (i + 0.5) / n;
    const p = A.clone().lerp(B, u);
    p.y -= Math.sin(u * Math.PI) * sag;
    const l = chainLinks[i];
    l.visible = true;
    l.position.copy(p);
    l.lookAt(B);
    l.rotation.z += (i % 2) * Math.PI / 2;
    l.material = burning ? linkHot : linkMat;
    if (burning) {
      const c = lerpC(FIRE[0], FIRE[2], (Math.sin(t * 9 + i) + 1) / 2);
      useSprite(p.clone().add(V(0, 0.8 + Math.sin(t * 14 + i * 2) * 0.3, 0)), 2.6, c, 0.85);
    }
  }
}
function hideChain() { for (const l of chainLinks) l.visible = false; }

// ---------------------------------------------------------------- camera helpers
function followCam(tl, t, o = {}) {
  const dist = o.dist ?? (VERTICAL ? 17 : 19);
  const height = o.height ?? (VERTICAL ? 9 : 8);
  const tgt = V();
  for (let k = 0; k < 8; k++) tgt.add(stateAt(tl, t - k * 0.1).p);
  tgt.multiplyScalar(1 / 8);
  const f = stateAt(tl, t + 0.5).p.sub(stateAt(tl, t - 1.2).p);
  f.y = 0;
  if (f.lengthSq() < 0.01) f.set(0, 0, 1);
  f.normalize();
  const side = V(f.z, 0, -f.x).multiplyScalar(o.side ?? 4);
  camera.position.copy(tgt).addScaledVector(f, -dist).add(V(0, height, 0)).add(side);
  camera.lookAt(tgt.clone().add(V(0, 2.5, 0)).addScaledVector(f, 5));
  return tgt;
}

function orbitCam(c, r, h, a) {
  camera.position.set(c.x + Math.cos(a) * r, c.y + h, c.z + Math.sin(a) * r);
  camera.lookAt(c);
}

// ---------------------------------------------------------------- scenes
const built = {};
function level(id) {
  if (!built[id]) {
    const b = buildLevel(LV[id]);
    b.tl = timeline(LV[id]);
    b.g.visible = false;
    scene.add(b.g);
    built[id] = b;
  }
  return built[id];
}
let active = null;
function show(b) {
  if (active !== b) {
    if (active) active.g.visible = false;
    b.g.visible = true;
    active = b;
    skyMat.uniforms.top.value.copy(b.sky.top);
    skyMat.uniforms.horizon.value.copy(b.sky.horizon);
    scene.fog = new THREE.Fog(b.sky.horizon, 140, 900);
    stars.visible = b.sky.night;
    hemi.color.copy(lerpC(b.sky.top, new THREE.Color(1, 1, 1), 0.5));
    hemi.groundColor.copy(lerpC(b.sky.atm, new THREE.Color(0.2, 0.2, 0.25), 0.6));
    hemi.intensity = b.sky.night ? 1.6 : 1.15;
    sun.intensity = b.sky.night ? 1.7 : 2.3;
    sun.color.copy(b.sky.night ? new THREE.Color(0.7, 0.75, 1) : new THREE.Color(1, 0.97, 0.9));
  }
}
function animateLevel(b, t) {
  for (const a of b.anim) {
    if (a.type === 'move') {
      const p = a.p;
      const ph = 0.5 - 0.5 * Math.cos((2 * Math.PI * t) / (p.period || 6));
      a.m.position.set(p.c[0] + (p.mv ? p.mv[0] : 0) * (p.travel || 0) * ph, p.c[1], p.c[2] + (p.mv ? p.mv[1] : 0) * (p.travel || 0) * ph);
    } else if (a.type === 'spin') {
      a.m.rotation.y = (a.p.spin || 2) * t;
    } else if (a.type === 'trophy') {
      a.m.rotation.y = t * 1.5;
    }
  }
}
function ridingMover(b, st) {
  if (st.seg && st.seg.kind === 'ride' && st.seg.mover && st.kind === 'ride') {
    const a = b.anim.find((x) => x.p === st.seg.mover);
    if (a) {
      const top = a.p.c[1] + a.p.z[1] / 2;
      a.m.position.set(st.p.x, a.p.c[1], st.p.z);
      st.p.y = top;
    }
  }
}
function sunFollow(target) {
  sun.position.copy(target).add(V(60, 120, 40));
  sun.target.position.copy(target);
}

// time when the runner reaches section s of a level (falls back to 0)
const startOf = (b, s) => b.tl.sectionStart[s] ?? 0;

const SCENES = [
  { t0: 0, t1: 3.4, id: 'Candy', cam: 'orbit', title: true },
  { t0: 3.4, t1: 8.6, id: 'Meadow', cam: 'follow', from: 1, runners: ['red'],
    cap: ['闖過 <span class="hl">16 個</span>主題關卡', '16 themed obstacle levels'] },
  { t0: 8.6, t1: 13.6, id: 'Castle', cam: 'follow', from: 2, runners: ['red', 'yellow'], chain: true,
    cap: ['和朋友用<span class="cool">鎖鏈</span>綁在一起！', 'Chained to your friends!'] },
  { t0: 13.6, t1: 18.2, id: 'Volcano', cam: 'follow', from: 1, runners: ['red', 'yellow'], chain: true, burn: 2.2, trail: 'fire',
    cap: ['碰到<span class="hot">岩漿</span><br>整條鏈一起燒！🔥', 'Lava burns the whole chain!'] },
  { t0: 18.2, t1: 22.4, id: 'Space', cam: 'follow', from: 1, runners: ['yellow'], trail: 'galaxy',
    cap: ['旋轉棒、移動平台、<br>消失的地板…', 'Spinners, movers, vanishing floors…'] },
  { t0: 22.4, t1: 26.6, id: 'Challenge', cam: 'follow', from: 6, runners: ['red'], trail: 'fire', speed: 1.15,
    cap: ['⚡ <span class="hl">每日挑戰</span><br>所有機關一次來！', 'Daily Challenge: every trap at once'],
    badge: '🏆 最快前 3 名拿限定稱號' },
  { t0: 26.6, t1: 29.0, id: 'Neon', cam: 'orbit',
    cap: ['路線<span class="hl">每天</span>都會換！', 'New routes every day!'] },
  { t0: 29.0, t1: 33.0, id: 'Neon', cam: 'orbit', end: true },
];
const DURATION = SCENES[SCENES.length - 1].t1;

// ---------------------------------------------------------------- UI
const ui = document.getElementById('ui');
const capEls = SCENES.map((s) => {
  if (!s.cap) return null;
  const el = document.createElement('div');
  el.className = 'cap';
  el.innerHTML = `${s.cap[0]}<span class="en">${s.cap[1]}</span>`;
  el.style.fontSize = (VERTICAL ? 84 : 66) * U + 'px';
  el.style.setProperty('--stroke', 14 * U + 'px');
  el.style.setProperty('--sh', 6 * U + 'px');
  el.style.top = VERTICAL ? 13 + '%' : 7 + '%';
  el.querySelector('.en').style.fontSize = (VERTICAL ? 46 : 38) * U + 'px';
  el.querySelector('.en').style.marginTop = 10 * U + 'px';
  ui.appendChild(el);
  return el;
});
const title = document.getElementById('title');
const end = document.getElementById('end');
const badge = document.getElementById('badge');
const flash = document.getElementById('flash');
for (const [id, size] of [['titleIcon', VERTICAL ? 330 : 260], ['endIcon', VERTICAL ? 300 : 230]]) {
  const e = document.getElementById(id);
  e.style.width = e.style.height = size * U + 'px';
  e.style.marginBottom = 30 * U + 'px';
}
for (const id of ['titleLogo', 'endLogo']) {
  const e = document.getElementById(id);
  e.style.fontSize = (VERTICAL ? 118 : 104) * U + 'px';
  e.style.setProperty('--stroke', 16 * U + 'px');
  e.style.setProperty('--sh', 8 * U + 'px');
}
for (const id of ['titleZh', 'endZh']) {
  const e = document.getElementById(id);
  e.style.fontSize = (VERTICAL ? 150 : 120) * U + 'px';
  e.style.setProperty('--stroke', 18 * U + 'px');
  e.style.setProperty('--sh', 9 * U + 'px');
  e.style.marginTop = -10 * U + 'px';
}
const pill = document.getElementById('endPill');
pill.style.fontSize = (VERTICAL ? 58 : 48) * U + 'px';
pill.style.marginTop = 40 * U + 'px';
const sub = document.getElementById('endSub');
sub.style.fontSize = (VERTICAL ? 42 : 36) * U + 'px';
sub.style.marginTop = 34 * U + 'px';
sub.style.setProperty('--stroke', 12 * U + 'px');
badge.style.fontSize = (VERTICAL ? 44 : 36) * U + 'px';
badge.style.left = '0';
badge.style.right = '0';
badge.style.margin = '0 auto';
badge.style.width = 'fit-content';
badge.style.bottom = VERTICAL ? '24%' : '9%';
badge.style.whiteSpace = 'nowrap';

function pop(el, t, t0, t1) {
  // scale-in pop at t0, fade out before t1
  const a = clamp((t - t0) / 0.28, 0, 1);
  const b = clamp((t1 - t) / 0.25, 0, 1);
  const k = Math.min(a, b);
  const s = a < 1 ? 0.6 + 0.4 * smooth(a) + Math.sin(a * Math.PI) * 0.12 : 1;
  el.style.opacity = k;
  el.style.transform = `scale(${s.toFixed(3)})`;
}

// ---------------------------------------------------------------- render
const lastDirs = new Map();
function renderAt(T) {
  const sc = SCENES.find((s) => T < s.t1) || SCENES[SCENES.length - 1];
  const local = T - sc.t0;
  const b = level(sc.id);
  show(b);
  animateLevel(b, T);
  hideChain();
  red.g.visible = false;
  yellow.g.visible = false;

  if (sc.cam === 'orbit') {
    const L = b.L;
    let cx = 0, cz = 0;
    for (const c of L.checkpoints) { cx += c[0] / L.checkpoints.length; cz += c[2] / L.checkpoints.length; }
    if (L.mode === 'tower') { cx = L.center[0]; cz = L.center[1]; }
    const mid = (L.top + L.bottom) / 2;
    const r = (VERTICAL ? 150 : 125) - local * 6;
    const c = V(cx, mid + (sc.end ? 10 : 0) + local * 3, cz);
    orbitCam(c, r, 18, 0.6 + (sc.t0 + local) * 0.18);
    sunFollow(c);
    // a runner climbing in the distance
    const st = placeAvatar(red, b.tl, startOf(b, 2) + T * 0.9, null);
    red.g.visible = true;
    ridingMover(b, st);
  } else {
    const speed = sc.speed ?? 1;
    const tRun = startOf(b, sc.from ?? 0) + local * speed;
    const lead = sc.runners.includes('red') ? red : yellow;
    const st = placeAvatar(lead, b.tl, tRun, lastDirs.get(lead));
    ridingMover(b, st);
    lead.g.position.copy(st.p);
    lead.g.visible = true;
    lastDirs.set(lead, st.dir);
    if (sc.runners.length > 1) {
      const other = lead === red ? yellow : red;
      const st2 = placeAvatar(other, b.tl, tRun - 0.42, lastDirs.get(other));
      ridingMover(b, st2);
      other.g.position.copy(st2.p);
      other.g.visible = true;
      // stand a little to the side so both are visible
      const sideV = V(st2.dir.z, 0, -st2.dir.x);
      if (sideV.lengthSq() > 0.01) other.g.position.addScaledVector(sideV.normalize(), 2.2);
    }
    if (sc.trail === 'fire') fireTrail(b.tl, tRun);
    if (sc.trail === 'galaxy') galaxyTrail(b.tl, tRun);
    if (sc.chain) chain(red, yellow, T, sc.burn !== undefined && local > sc.burn && local < sc.burn + 1.6);
    const camOpts = sc.id === 'Space' ? { dist: VERTICAL ? 20 : 22, height: 10 } : sc.chain ? { dist: VERTICAL ? 19 : 21, height: 8, side: -10 } : {};
    const tgt = followCam(b.tl, sc.chain ? tRun - 0.2 : tRun, camOpts);
    sunFollow(tgt);
  }
  hideSprites();

  // UI
  SCENES.forEach((s, i) => {
    const el = capEls[i];
    if (!el) return;
    if (T >= s.t0 && T < s.t1) pop(el, T, s.t0 + 0.15, s.t1);
    else el.style.opacity = 0;
  });
  const ts = SCENES[0];
  if (T < ts.t1) pop(title, T, 0.1, ts.t1);
  else title.style.opacity = 0;
  const es = SCENES[SCENES.length - 1];
  if (T >= es.t0) {
    pop(end, T, es.t0 + 0.1, es.t1 + 10);
    renderer.domElement.style.filter = `brightness(${1 - 0.35 * clamp((T - es.t0) / 0.5, 0, 1)}) blur(${3 * clamp((T - es.t0) / 0.5, 0, 1)}px)`;
  } else {
    end.style.opacity = 0;
    renderer.domElement.style.filter = '';
  }
  if (sc.badge && local > 1.0) {
    badge.textContent = sc.badge;
    pop(badge, T, sc.t0 + 1.0, sc.t1);
  } else badge.style.opacity = 0;
  // white flash on cuts
  let fl = 0;
  for (const s of SCENES) {
    if (s.t0 > 0 && s.id !== SCENES[SCENES.indexOf(s) - 1]?.id) fl = Math.max(fl, 1 - Math.abs(T - s.t0) / 0.12);
  }
  flash.style.opacity = clamp(fl, 0, 1) * 0.85;

  renderer.render(scene, camera);
}

window.DURATION = DURATION;
window.renderAt = renderAt;
await document.fonts.ready;
// warm up every level so frame timing is steady
for (const s of SCENES) level(s.id);
renderAt(0);
window.READY = true;

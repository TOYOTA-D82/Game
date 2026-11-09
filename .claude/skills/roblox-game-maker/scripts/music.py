# Original upbeat chiptune-style backing track (synthesised from scratch, no samples, no copyright issues).
# Usage: python3 music.py out.wav <seconds> [hit1,hit2,...]  (hits = cut times in seconds that get a crash)
import numpy as np, wave, sys
SR = 44100
DUR = float(sys.argv[2]) if len(sys.argv) > 2 else 33.0
BPM = 128.0
beat = 60.0 / BPM
n = int(SR * DUR)
L = np.zeros(n); R = np.zeros(n)
t_all = np.arange(n) / SR

def note_freq(m):  # midi -> Hz
    return 440.0 * 2 ** ((m - 69) / 12)

def env(length, a=0.005, d=0.12, s=0.5, r=0.08):
    k = np.arange(length) / SR
    e = np.ones(length) * s
    ai = k < a
    e[ai] = k[ai] / a
    di = (k >= a) & (k < a + d)
    e[di] = 1 - (1 - s) * (k[di] - a) / d
    tail = int(r * SR)
    if tail < length:
        e[-tail:] *= np.linspace(1, 0, tail)
    return e

def add(buf, start, sig, pan=0.0, gain=1.0):
    i = int(start * SR)
    if i >= n: return
    sig = sig[: n - i]
    L[i:i + len(sig)] += sig * gain * (1 - max(0, pan))
    R[i:i + len(sig)] += sig * gain * (1 + min(0, pan))

def osc(kind, f, length, duty=0.5):
    k = np.arange(length) / SR
    ph = (k * f) % 1.0
    if kind == 'square': return np.where(ph < duty, 1.0, -1.0)
    if kind == 'tri': return 4 * np.abs(ph - 0.5) - 1
    if kind == 'saw': return 2 * ph - 1
    return np.sin(2 * np.pi * f * k)

rng = np.random.default_rng(7)
def noise(length): return rng.uniform(-1, 1, length)

def lowpass(x, a):  # simple one-pole
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y

# I - V - vi - IV in C
chords = [[60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60]]
bass_roots = [36, 31, 33, 29]
bar = 4 * beat
nbars = int(DUR / bar) + 1
END = DUR - 3.2  # last few seconds: big held chord + fade

for b in range(nbars):
    t0 = b * bar
    if t0 >= END: break
    ch = chords[b % 4]
    root = bass_roots[b % 4]
    # bass: eighth notes, octave jump on offbeats
    for e in range(8):
        tt = t0 + e * beat / 2
        if tt >= END: break
        m = root + (12 if e % 2 else 0)
        ln = int(beat / 2 * SR * 0.9)
        sig = lowpass(osc('saw', note_freq(m), ln), 0.12) * env(ln, d=0.08, s=0.6, r=0.03)
        add(None, tt, sig, gain=0.32)
    # arpeggio lead (16ths), only after the intro bar
    if b >= 1:
        pattern = [0, 1, 2, 1, 0, 2, 1, 2]
        for s16 in range(16):
            tt = t0 + s16 * beat / 4
            if tt >= END: break
            m = ch[pattern[s16 % 8]] + 12
            ln = int(beat / 4 * SR)
            sig = osc('square', note_freq(m), ln, duty=0.25) * env(ln, d=0.05, s=0.25, r=0.02)
            add(None, tt, sig, pan=0.25 if s16 % 2 else -0.25, gain=0.07)
    # pad chord
    ln = int(bar * SR)
    pad = sum(osc('tri', note_freq(m), ln) for m in ch) / 3
    add(None, t0, pad * env(ln, a=0.2, d=0.3, s=0.7, r=0.3), gain=0.09)
    # drums
    for q in range(4):
        tt = t0 + q * beat
        if tt >= END: break
        # kick every beat
        ln = int(0.22 * SR); k = np.arange(ln) / SR
        f = 120 * np.exp(-k * 28) + 42
        kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-k * 14)
        add(None, tt, kick, gain=0.75)
        if q in (1, 3):  # snare
            ln = int(0.18 * SR); k = np.arange(ln) / SR
            sn = (noise(ln) * 0.8 + np.sin(2 * np.pi * 190 * k) * 0.4) * np.exp(-k * 20)
            add(None, tt, sn, gain=0.32)
        for h in (0, 0.5):  # hats on 8ths
            ln = int(0.05 * SR); k = np.arange(ln) / SR
            hh = np.diff(np.concatenate([[0], noise(ln)])) * np.exp(-k * 70)
            add(None, tt + h * beat, hh, pan=0.3, gain=0.10 if h else 0.06)

# crash on every scene cut
for cut in [float(x) for x in sys.argv[3].split(',')] if len(sys.argv) > 3 else []:
    ln = int(1.2 * SR); k = np.arange(ln) / SR
    cr = np.diff(np.concatenate([[0], noise(ln)])) * np.exp(-k * 3.5)
    add(None, cut, cr, gain=0.16)
    # little whoosh before the cut
    ln = int(0.35 * SR); k = np.arange(ln) / SR
    wh = lowpass(noise(ln), 0.08) * (k / 0.35) ** 2
    add(None, max(0, cut - 0.35), wh, gain=0.35)

# ending: big C chord held, fades out
ln = int(3.2 * SR)
fin = sum(osc('square', note_freq(m), ln, duty=0.3) * 0.5 + osc('tri', note_freq(m - 12), ln) for m in [60, 64, 67, 72]) / 6
k = np.arange(ln) / SR
add(None, END, fin * np.exp(-k * 0.9), gain=0.35)
ln = int(0.25 * SR); kk = np.arange(ln) / SR
add(None, END, np.sin(2 * np.pi * np.cumsum(120 * np.exp(-kk * 25) + 40) / SR) * np.exp(-kk * 10), gain=0.9)

mix = np.stack([L, R], axis=1)
fade = int(0.25 * SR)
mix[:fade] *= np.linspace(0, 1, fade)[:, None]
mix /= np.max(np.abs(mix)) / 0.89
pcm = (mix * 32767).astype(np.int16)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('wrote', sys.argv[1], DUR, 's')

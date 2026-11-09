#!/usr/bin/env python3
"""Edit a Roblox Studio screen recording into promo videos.

  inspect <video> <workdir>
      contact sheets (1 fps, timestamped), scene-cut list, two full-size frames
  zoom <video> <start> <end> <out.png> [--crop W:H:X:Y]
      4 fps timestamped strip of a short span, to decide exact cut points
  cut <video> <out_dir> --crop W:H:X:Y --keep "a-b,c-d,..." [--short "a-b,..."]
      [--title TEXT --tagline TEXT --search TEXT --sub TEXT --icon PNG]
      full_16x9.mp4, short_16x9.mp4, roblox_1080p.mp4, roblox_720p.mp4,
      shorts_9x16.mp4 (+ music) and a spec check of every file.

Needs ffmpeg/ffprobe, Python 3 with Pillow and numpy; the Shorts overlay needs
Node + Playwright (Chromium). Every hard cut that changes level gets a music hit;
pass --same "i,j" (0-based segment indexes) for segments that continue the
previous one so they don't get a hit.
"""
import argparse, json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height,sample_aspect_ratio,r_frame_rate", "-show_entries",
                          "format=duration,size,bit_rate", "-of", "json", path], capture_output=True, text=True, check=True)
    d = json.loads(out.stdout)
    s, f = d["streams"][0], d["format"]
    return {"w": s["width"], "h": s["height"], "sar": s.get("sample_aspect_ratio", "1:1"), "fps": s.get("r_frame_rate"),
            "dur": float(f["duration"]), "mb": int(f["size"]) / 1e6, "mbps": int(f.get("bit_rate", 0)) / 1e6}


def drawtext(offset=0.0, size=18):
    font = f"fontfile={FONT}:" if os.path.exists(FONT) else ""
    return f"drawtext={font}text='%{{pts\\:hms\\:{offset}}}':x=4:y=4:fontsize={size}:fontcolor=yellow:box=1:boxcolor=black"


def inspect(a):
    os.makedirs(a.workdir, exist_ok=True)
    info = probe(a.video)
    print("video:", info)
    sheet_dir = os.path.join(a.workdir, "sheet")
    os.makedirs(sheet_dir, exist_ok=True)
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", a.video, "-vf", f"fps=1,scale=240:-1,{drawtext()}",
         os.path.join(sheet_dir, "s_%04d.png")])
    from PIL import Image
    frames = sorted(os.listdir(sheet_dir))
    if frames:
        w, h = Image.open(os.path.join(sheet_dir, frames[0])).size
        per = 32
        for part in range(0, len(frames), per):
            sub = frames[part:part + per]
            cols = 8
            rows = (len(sub) + cols - 1) // cols
            out = Image.new("RGB", (cols * w, rows * h), "black")
            for i, f in enumerate(sub):
                out.paste(Image.open(os.path.join(sheet_dir, f)), ((i % cols) * w, (i // cols) * h))
            path = os.path.join(a.workdir, f"contact_{part // per}.png")
            out.save(path)
            print("contact sheet:", path)
    for t in (min(7, info["dur"] / 4), info["dur"] / 2):
        p = os.path.join(a.workdir, f"frame_{t:.0f}s.png")
        run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(t), "-i", a.video, "-frames:v", "1", p])
        print("full frame (measure the game viewport here):", p)
    res = subprocess.run(["ffmpeg", "-i", a.video, "-vf", "scale=320:-1,select='gt(scene,0.25)',showinfo", "-an", "-f", "null", "-"],
                         capture_output=True, text=True)
    cuts = [float(x.split(":")[1]) for x in res.stderr.split() if x.startswith("pts_time:")]
    print("scene cuts (s):", " ".join(f"{c:.2f}" for c in cuts))


def zoom(a):
    vf = (f"crop={a.crop}," if a.crop else "") + f"fps=4,scale=240:-1,{drawtext(a.start, 16)},tile=6x3"
    run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(a.start), "-to", str(a.end), "-i", a.video, "-vf", vf,
         "-frames:v", "1", a.out])
    print("zoom strip:", a.out)


def segs(spec):
    return [tuple(map(float, s.split("-"))) for s in spec.split(",") if s.strip()]


def concat(video, out, crop, parts):
    w, h, x, y = crop.split(":")
    chains, labels = [], []
    for i, (s, e) in enumerate(parts):
        chains.append(f"[0:v]trim=start={s}:end={e},setpts=PTS-STARTPTS,crop={w}:{h}:{x}:{y},"
                      f"scale=1920:1080:flags=lanczos,setsar=1,unsharp=5:5:0.6,fps=30[v{i}]")
        labels.append(f"[v{i}]")
    fc = ";".join(chains) + ";" + "".join(labels) + f"concat=n={len(parts)}:v=1:a=0[outv]"
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-filter_complex", fc, "-map", "[outv]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", out])
    t, hits = 0.0, []
    for s, e in parts[:-1]:
        t += e - s
        hits.append(round(t, 2))
    return round(t + parts[-1][1] - parts[-1][0], 2), hits


def with_music(silent, music, out, dur, hits):
    run([sys.executable, "-I", os.path.join(HERE, "music.py"), music, str(dur), ",".join(map(str, hits))])
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", silent, "-i", music, "-map", "0:v", "-map", "1:a",
         "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out])


def roblox_export(src, out, size, bitrate):
    w, h = size
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-vf", f"scale={w}:{h}:flags=lanczos,setsar=1",
         "-c:v", "libx264", "-preset", "slow", "-b:v", bitrate, "-maxrate", "14M", "-bufsize", "20M",
         "-pix_fmt", "yuv420p", "-profile:v", "high", "-r", "30", "-c:a", "aac", "-b:a", "160k",
         "-movflags", "+faststart", out])


def shorts(src, out, workdir, a):
    overlay = os.path.join(workdir, "overlay.png")
    html = os.path.join(workdir, "overlay.html")
    shutil.copy(os.path.join(HERE, "shorts_overlay.html"), html)
    if a.icon:
        shutil.copy(a.icon, os.path.join(workdir, "icon.png"))
    params = {"title": a.title, "zh": a.zh or "", "tagline": a.tagline or "", "search": a.search or "",
              "sub": a.sub or "", "icon": "icon.png" if a.icon else ""}
    node_path = subprocess.run(["npm", "root", "-g"], capture_output=True, text=True).stdout.strip()
    run(["node", os.path.join(HERE, "render_overlay.js"), html, overlay, json.dumps(params)],
        env={**os.environ, "NODE_PATH": node_path})
    fc = ("[0:v]split[a][b];[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,"
          "boxblur=30:2,eq=brightness=-0.12[bg];[b]crop=1440:1080:240:0,scale=1080:810:flags=lanczos[fg];"
          "[bg][fg]overlay=0:(H-h)/2+40[v1];[v1][1:v]overlay=0:0,setsar=1[v]")
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-i", overlay, "-filter_complex", fc, "-map", "[v]",
         "-map", "0:a", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "copy",
         "-movflags", "+faststart", out])


def cut(a):
    os.makedirs(a.out_dir, exist_ok=True)
    work = os.path.join(a.out_dir, "_work")
    os.makedirs(work, exist_ok=True)
    same = {int(x) for x in a.same.split(",")} if a.same else set()
    made = []
    for name, spec in (("full", a.keep), ("short", a.short)):
        if not spec:
            continue
        parts = segs(spec)
        silent = os.path.join(work, f"{name}_silent.mp4")
        dur, hits = concat(a.video, silent, a.crop, parts)
        if name == "full":
            hits = [h for i, h in enumerate(hits) if (i + 1) not in same]
        out = os.path.join(a.out_dir, f"{name}_16x9.mp4")
        with_music(silent, os.path.join(work, f"{name}.wav"), out, dur, hits)
        made.append(out)
    roblox_src = os.path.join(a.out_dir, "short_16x9.mp4") if a.short else made[0]
    for size, br, label in (((1920, 1080), "12M", "roblox_1080p"), ((1280, 720), "6M", "roblox_720p")):
        out = os.path.join(a.out_dir, f"{label}.mp4")
        roblox_export(roblox_src, out, size, br)
        made.append(out)
    if a.title:
        out = os.path.join(a.out_dir, "shorts_9x16.mp4")
        shorts(made[0], out, work, a)
        made.append(out)
    print("\nfile | size | pixels | sec | MB | Mbps")
    for m in made:
        i = probe(m)
        ok = ""
        if "roblox" in m:
            good = i["w"] <= 1920 and i["h"] <= 1080 and i["sar"] in ("1:1", "N/A") and i["dur"] <= 60 and i["mb"] <= 100 and i["mbps"] <= 15
            ok = "  <- Roblox spec OK" if good else "  <- FAILS Roblox spec"
        print(f"{os.path.basename(m)} | {i['w']}x{i['h']} | sar {i['sar']} | {i['dur']:.1f} | {i['mb']:.1f} | {i['mbps']:.1f}{ok}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("inspect"); s.add_argument("video"); s.add_argument("workdir"); s.set_defaults(fn=inspect)
    s = sub.add_parser("zoom"); s.add_argument("video"); s.add_argument("start", type=float); s.add_argument("end", type=float)
    s.add_argument("out"); s.add_argument("--crop"); s.set_defaults(fn=zoom)
    s = sub.add_parser("cut"); s.add_argument("video"); s.add_argument("out_dir")
    s.add_argument("--crop", required=True, help="W:H:X:Y of a 16:9 area inside the game viewport")
    s.add_argument("--keep", required=True, help="source spans for the full version, e.g. 5.3-8.8,11.9-15")
    s.add_argument("--short", help="source spans for the <=30 s Roblox version")
    s.add_argument("--same", help="0-based indexes of --keep segments that continue the previous level (no music hit)")
    s.add_argument("--title", help="Shorts overlay: big English title, e.g. 'CHAINED<br>TOWER'")
    s.add_argument("--zh", help="Shorts overlay: Chinese title, e.g. 綁腳塔")
    s.add_argument("--tagline", help="Shorts overlay: one line under the title (HTML allowed)")
    s.add_argument("--search", help="Shorts overlay: yellow pill, e.g. Roblox 搜尋「Chained Tower」")
    s.add_argument("--sub", help="Shorts overlay: small line under the pill")
    s.add_argument("--icon", help="Shorts overlay: game icon PNG")
    s.set_defaults(fn=cut)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()

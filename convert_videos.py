#!/usr/bin/env python3
"""Re-encode Silent Hill: The Arcade movies (*.vid) so Wine can play them.

The game renders movies through DirectShow into its own RGB32 renderer. The
original files are XviD AVI (6ch PCM) and MPEG-2 elementary streams, which on
Windows needed K-Lite/ffdshow. Wine's own MPEG/WMV decoders depend on GStreamer
libav, which is often unavailable (e.g. GE-Proton outside the Steam runtime).
Cinepak is decoded by Wine's built-in iccvid through the AVI Decompressor, with
no GStreamer decoder involved, and it outputs RGB32 directly.

Output: AVI, Cinepak video (same size/fps), 16-bit stereo PCM 48 kHz (if the
source had audio). Movies are not covered by the game's boot CRC check
(only KSHG.exe and data\\TestMode\\ are), so replacing them is safe.

Cinepak encoding in ffmpeg is single-threaded and slow, so every movie is cut
into chunks of round(SEG * fps) frames encoded in parallel and joined with the
concat demuxer.

Raw MPEG-2 elementary streams (no container, no index) cannot be cut
accurately with -ss, so they are first remuxed (stream copy) into Matroska
with generated timestamps; cutting the raw stream directly misaligns frames.

Usage: convert_videos.py "<game dir>" [-j JOBS] [--redo NAME ...]
Originals are kept as <name>.vid.orig; re-running skips converted files
unless their name (e.g. sceneA.vid) is given to --redo.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SEG = 10.0

def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)

def duration(info, path):
    d = info.get("format", {}).get("duration")
    if d not in (None, "N/A"):
        return float(d)
    # raw MPEG-2 elementary streams have no duration: count frames
    out = subprocess.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0",
                          "-show_entries", "stream=nb_read_packets,r_frame_rate", "-of", "json", str(path)],
                         check=True, capture_output=True, text=True).stdout
    s = json.loads(out)["streams"][0]
    num, den = map(int, s["r_frame_rate"].split("/"))
    return int(s["nb_read_packets"]) * den / num

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"{' '.join(cmd)}\n{r.stderr[-2000:]}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    ap.add_argument("--redo", nargs="*", default=[], help="re-convert these files from their .orig")
    args = ap.parse_args()
    tmp = Path(tempfile.mkdtemp(prefix="shvid_"))

    vids = sorted(Path(args.game_dir).rglob("*.vid"))
    work = []
    for v in vids:
        orig = v.with_name(v.name + ".orig")
        src = orig if orig.exists() else v
        info = probe(src)
        vcodec = next(s["codec_name"] for s in info["streams"] if s["codec_type"] == "video")
        if vcodec == "cinepak":
            continue
        if probe(v)["streams"][0]["codec_name"] == "cinepak" and orig.exists() and v.name not in args.redo:
            print(f"skip (done) {v}"); continue
        has_audio = any(s["codec_type"] == "audio" for s in info["streams"])
        dur = duration(info, src)
        vs = next(s for s in info["streams"] if s["codec_type"] == "video")
        num, den = map(int, vs["r_frame_rate"].split("/"))
        fps = num / den
        if info["format"]["format_name"] == "mpegvideo":
            mkv = tmp / f"{len(work):03d}_src.mkv"
            run(["ffmpeg", "-v", "error", "-y", "-fflags", "+genpts", "-r", vs["r_frame_rate"],
                 "-i", str(src), "-c", "copy", str(mkv)])
            src = mkv
        work.append((v, src, dur, fps, has_audio))
    jobs = []  # (seg_path, cmd)
    plan = []
    for i, (v, src, dur, fps, has_audio) in enumerate(work):
        d = tmp / f"{i:03d}"; d.mkdir()
        segs = []
        # cut on whole frames: at 29.97 fps a 10.000 s cut yields 300 frames, not
        # 299.7, and the extra frames accumulate into audio/video drift
        seg_frames = round(SEG * fps)
        first = 0
        while first < round(dur * fps):
            seg = d / f"seg{len(segs):04d}.avi"
            jobs.append(["ffmpeg", "-v", "error", "-y", "-ss", f"{first / fps:.6f}", "-i", str(src),
                         "-frames:v", str(seg_frames), "-an", "-c:v", "cinepak", "-f", "avi", str(seg)])
            segs.append(seg); first += seg_frames
        plan.append((v, src, d, segs, has_audio))
    print(f"{len(work)} movies, {len(jobs)} segments, {args.jobs} parallel jobs", flush=True)

    done = 0
    with ThreadPoolExecutor(args.jobs) as ex:
        for _ in ex.map(run, jobs):
            done += 1
            print(f"  encoded {done}/{len(jobs)}", flush=True)   # one line per segment (progress bar)

    for v, src, d, segs, has_audio in plan:
        lst = d / "list.txt"
        lst.write_text("".join(f"file '{s}'\n" for s in segs))
        out = d / "out.avi"
        cmd = ["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst)]
        if has_audio:
            cmd += ["-i", str(src), "-map", "0:v:0", "-map", "1:a:0", "-c:a", "pcm_s16le", "-ac", "2", "-ar", "48000"]
        cmd += ["-c:v", "copy", "-f", "avi", str(out)]
        run(cmd)
        orig = v.with_name(v.name + ".orig")
        if not orig.exists():
            shutil.move(v, orig)
        shutil.move(out, v)
        print(f"converted {v}", flush=True)
    shutil.rmtree(tmp)

if __name__ == "__main__":
    main()

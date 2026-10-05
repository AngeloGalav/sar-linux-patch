#!/usr/bin/env python3
"""Remove the audio track from Silent Hill: The Arcade movies (*.vid).

The game plays each movie's soundtrack itself (Data/Sound/EVENT/EV_*.pcm,
5.1 PCM through its own sound system) while the movie is shown; the AVI files
carry the same audio (sceneB.vid vs EV_B.pcm: 0.97 correlation at 0 s offset).
On the arcade/Windows that track was not heard, but Wine/Proton renders it, so
every line is heard twice, like an echo. Dropping the track (video stream copy,
no re-encoding) leaves the game's own playback as the only one.

Originals are kept as <name>.vid.orig (unless one already exists).
With --from-originals every movie is rebuilt from its .vid.orig, which also
undoes an earlier Cinepak conversion (use this with GE-Proton 11, which plays
the original video).

Usage: strip_movie_audio.py "<game dir>" [--from-originals]
"""
import argparse, json, shutil, subprocess, sys
from pathlib import Path

def streams(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)["streams"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game_dir")
    ap.add_argument("--from-originals", action="store_true",
                    help="rebuild every movie from its .vid.orig (undoes a Cinepak conversion)")
    args = ap.parse_args()

    changed = 0
    root = Path(args.game_dir)
    for v in sorted(root.rglob("*.vid")):
        orig = v.with_name(v.name + ".orig")
        src = orig if (args.from_originals and orig.exists()) else v
        has_audio = any(s["codec_type"] == "audio" for s in streams(src))
        if not has_audio:
            if src is orig and v.read_bytes() != orig.read_bytes():
                shutil.copy2(orig, v)            # original has no audio (raw MPEG-2): just put it back
                print(f"restored {v.relative_to(root)}", flush=True); changed += 1
            continue
        if not orig.exists():
            shutil.move(v, orig)                 # keep the untouched original
            src = orig
        tmp = v.with_name(v.name + ".tmp")
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-map", "0:v:0", "-c:v", "copy",
                            "-an", "-f", "avi", str(tmp)], capture_output=True, text=True)
        if r.returncode:
            tmp.unlink(missing_ok=True)
            sys.exit(f"ffmpeg failed on {src}:\n{r.stderr[-1500:]}")
        tmp.replace(v)
        print(f"removed audio track: {v.relative_to(root)}", flush=True); changed += 1
    print(f"{changed} movies updated")

if __name__ == "__main__":
    main()

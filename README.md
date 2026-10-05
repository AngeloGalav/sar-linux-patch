# Silent Hill: The Arcade on Linux

Patches and a launcher that make the PC release of *Silent Hill: The Arcade*
(the Collection Chamber repack: `KSHG.exe`, `KSHG_no_cursor.exe`,
`shaiolib.CRK.dll`, …) run on Linux with Wine/Proton. No game files are
included: you need your own copy of the game.

## Requirements

- **GE-Proton 11** (recommended, tested with GE-Proton11-7). It plays the
  game's original movies. If you don't have it, the installer can download it
  for you into Steam's `compatibilitytools.d`.
- Without GE-Proton 11, GE-Proton 10 (tested with GE-Proton10-34) or another
  Proton 10 build also runs the game, but the movies have to be converted
  first (see below). Proton 9 and older are not supported.
- `python3`, and `curl` to download GE-Proton
- only for the movie conversion: `ffmpeg` with the Cinepak encoder and about
  7 GB of free space on the game's disk
- optional: `zenity` or `kdialog` for the installer windows

## Install

```sh
./install.sh "/path/to/Silent Hill Arcade"
```

You can also unpack this package straight into the game folder and run
`./install.sh` there without arguments. Without a path, the installer uses the
current folder or its own folder if that is the game folder, and otherwise
asks you to pick it.

The installer guides you with a few windows (zenity or kdialog; it falls back
to questions in the terminal if neither is available):

1. **Welcome**: shows the game folder and the Proton it found, and what it is
   about to do. Nothing is changed until you press *Install*.
2. It patches the game binaries and creates the crosshair version (a few seconds).
3. **Movies**: with GE-Proton 11 the original movies play as they are, so
   nothing else is needed (movies converted by an earlier install are swapped
   back for the originals). Without it you choose between:
   - **Download and install GE-Proton 11** (about 560 MB, recommended): it goes
     into Steam's `compatibilitytools.d`, so Steam can use it too after a
     restart. The download is checked against its published SHA-512 checksum.
   - **Convert the movies** for older Proton versions: slow (about 20-30
     minutes on a fast 16-core desktop CPU, around 2 hours on a Steam Deck)
     and needs about 7 GB of free disk space while it runs. Optional *fast
     conversion* (about 2.5x faster, slightly lower quality) and *delete the
     original movies afterwards* (frees 1.3 GB). A progress bar shows the
     conversion.
   - **Neither**: the game works, but the movies stay black.
4. **Windows-only files**: offers to delete the files the Linux version
   doesn't use (the TTX game loader and `TTX.ini`, `sv/Pad.ini`, the `.bat`
   files, `DSFMgr.exe`, the repack's uninstaller, `README.txt`, `Info.txt`,
   the website link and `images/`).
5. **Installation done! Enjoy SH Arcade!**, with how to start the game.

Every modified file is kept as `<name>.orig`. Running the installer again is
safe (finished steps are skipped), and

```sh
./install.sh --restore "/path/to/Silent Hill Arcade"
```

puts the originals back (except movies whose originals you chose to delete
and Windows files you chose to remove). GE-Proton and the Wine prefix are left
in place.

| Option | Effect |
|---|---|
| `--desktop` | add *Silent Hill: The Arcade* to the application menu |
| `--install-proton` | download GE-Proton 11 if it is missing, without asking |
| `--convert-videos` | if GE-Proton 11 is missing, convert the movies instead |
| `--no-videos` | neither download GE-Proton 11 nor convert the movies |
| `--fast-videos` | convert the movies about 2.5x faster at slightly lower quality |
| `--delete-original-videos` | delete the original movies after converting them |
| `--jobs N` | number of parallel encoders (default: all CPU cores) |
| `--remove-windows-files` / `--keep-windows-files` | answer the Windows-files question in advance |
| `--no-gui` | ask in the terminal instead of opening windows |
| `--yes` | ask nothing: download GE-Proton 11 if needed, keep the Windows files |

## Play

```sh
"/path/to/Silent Hill Arcade/run_linux.sh"           # no cursor
"/path/to/Silent Hill Arcade/run_linux.sh" cursor    # crosshair cursor (sv/CrossHair.cur)
"/path/to/Silent Hill Arcade/run_linux.sh" config    # change the key bindings
```

| Key | Action |
|---|---|
| Mouse / left click | aim / shoot |
| Enter | 1P start (on attract screens: first press skips, second starts a game) |
| 2 | 2P start |
| 3 / 4, 5 / 6 | 1P / 2P option L / R |
| F2 / F1 | test (operator) menu / service |
| Esc | quit |

Paths used by the launcher:

- **game folder**: the folder `run_linux.sh` is in
- **Proton**: `$PROTON_DIR`, else the one chosen by `install.sh`
  (`linux/proton_dir`), else the newest GE-Proton, then Proton Experimental/10,
  in the usual Steam locations (native and Flatpak)
- **Wine prefix**: `$SH_PREFIX`, else `~/.local/share/sh-arcade/pfx`
  (created on first run; key bindings live in
  `drive_c/users/*/AppData/Roaming/bemani_config/sha_v01.cfg`)

## Package contents

```
install.sh        installer (run this)
run_linux.sh      launcher, copied into the game folder by install.sh
proton.sh         Proton lookup shared by the installer and the launcher
patches/          Python scripts used by the installer
  patch_libutil_midi.py    patch_shaiolib_crk.py    patch_kshg_video.py
  patch_kshg_cursor.py     convert_videos.py        make_default_bindings.py
```

Each script in `patches/` can also be run on its own; its docstring explains
what it changes and how to call it. After installing, the game folder contains
`run_linux.sh` and a `linux/` folder with the files the launcher needs
(`proton.sh`, `make_default_bindings.py` and the chosen Proton path).

## What is patched and why

| File | Problem under Wine | Fix | Script |
|---|---|---|---|
| `libutil.dll` | exits if a MIDI input (PipeWire/ALSA port) fails to open | skip that device | `patch_libutil_midi.py` |
| `shaiolib.CRK.dll` | `shaiolib_is_error()` returns a leftover register (1 under Wine), so the game flags an I/O error and won't start | return 0 | `patch_shaiolib_crk.py` |
| `KSHG.exe`, `KSHG_no_cursor.exe` | Wine's async `StopWhenReady` stops movies after the first frame; NULL frame buffer crash when a movie can't be decoded | call `Pause` instead; NULL check. The file CRC checked at boot is preserved | `patch_kshg_video.py` |
| `KSHG_cursor.exe` (new) | the crosshair was drawn by the Windows TTX loader | the game loads `sv/CrossHair.cur` itself | `patch_kshg_cursor.py` |
| `Data/**/*.vid` | XviD / MPEG-2 movies: Proton 10 and older have no decoder for them | none needed with GE-Proton 11 (its DirectShow decodes through FFmpeg); otherwise re-encoded to Cinepak AVI, which Wine decodes itself | `convert_videos.py` |

The launcher uses DXVK for Direct3D 9 (correct 640x480 fullscreen scaling),
caps the game at 60 FPS like the Windows loader did (set `DXVK_FRAME_RATE=0`
to turn the cap off), and sets up Proton's libraries so it works without Steam.

## AI disclosure

The research and development of this project (reverse engineering, patches,
scripts and this README) were done with the assistance of an LLM (specifically Claude Sonnet 5.5). 

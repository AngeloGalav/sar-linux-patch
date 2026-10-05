# Silent Hill: The Arcade on Linux

Patches and a launcher that make the PC release of *Silent Hill: The Arcade*
(the Collection Chamber repack: `KSHG.exe`, `KSHG_no_cursor.exe`,
`shaiolib.CRK.dll`, …) run on Linux with Wine/Proton. No game files are
included: you need your own copy of the game.

## Requirements

- **GE-Proton 10** (tested with GE-Proton10-34; install it with ProtonUp-Qt).
  Proton Experimental / Proton 10 have the same layout and should also work.
  Proton 9 and older are not supported.
- `python3`
- `ffmpeg` with the Cinepak encoder (standard in most distributions)
- about 7 GB free on the game's disk for the movie conversion
- optional: `zenity` or `kdialog` for the installer windows

## Install

```sh
./install.sh "/path/to/Silent Hill Arcade"
```

(Without a path, the installer asks you to pick the game folder.)

The installer guides you with a few windows (zenity or kdialog; it falls back
to questions in the terminal if neither is available):

1. **Welcome**: shows the game folder and the Proton it found, and what it is
   about to do. Nothing is changed until you press *Install*.
2. It patches the game binaries and creates the crosshair version (a few seconds).
3. **Movie conversion**: the movies need re-encoding to a format Wine can play.
   This is slow (about 20-30 minutes on a fast 16-core CPU, longer on slower
   machines; the computer is busy meanwhile) and needs about 7 GB of free disk
   space while it runs. You can *Skip* it (movies then show a black screen, and
   you can run the installer again later) and you can tick **Delete the original
   movies afterwards** to free 1.3 GB. A progress bar shows the conversion.
4. **Installation done! Enjoy SH Arcade!**, with how to start the game.

Every modified file is kept as `<name>.orig`. Running the installer again is
safe (finished steps are skipped), and

```sh
./install.sh --restore "/path/to/Silent Hill Arcade"
```

puts the originals back (except movies whose originals you chose to delete).

| Option | Effect |
|---|---|
| `--desktop` | add *Silent Hill: The Arcade* to the application menu |
| `--no-videos` | skip the movie conversion |
| `--delete-original-videos` | delete the original movies after converting them |
| `--jobs N` | number of parallel encoders (default: all CPU cores) |
| `--no-gui` | ask in the terminal instead of opening windows |
| `--yes` | ask nothing: convert the movies and keep the originals |

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
- **Proton**: `$PROTON_DIR`, else the one found by `install.sh`
  (`linux/proton_dir`), else the newest GE-Proton, then Proton Experimental/10,
  in the usual Steam locations (native and Flatpak)
- **Wine prefix**: `$SH_PREFIX`, else `~/.local/share/sh-arcade/pfx`
  (created on first run; key bindings live in
  `drive_c/users/*/AppData/Roaming/bemani_config/sha_v01.cfg`)

## What is patched and why

| File | Problem under Wine | Fix |
|---|---|---|
| `libutil.dll` | exits if a MIDI input (PipeWire/ALSA port) fails to open | skip that device |
| `shaiolib.CRK.dll` | `shaiolib_is_error()` returns a leftover register (1 under Wine), so the game flags an I/O error and won't start | return 0 |
| `KSHG.exe`, `KSHG_no_cursor.exe` | Wine's async `StopWhenReady` stops movies after the first frame; NULL frame buffer crash when a movie can't be decoded | call `Pause` instead; NULL check. The file CRC checked at boot is preserved |
| `KSHG_cursor.exe` (new) | the crosshair was drawn by the Windows TTX loader | the game loads `sv/CrossHair.cur` itself |
| `Data/**/*.vid` | XviD / MPEG-2 movies need codecs Wine doesn't have | re-encoded to Cinepak AVI, decoded by Wine itself |

The launcher uses DXVK for Direct3D 9 (correct 640x480 fullscreen scaling)
and sets up Proton's libraries so it works without Steam.

## AI disclosure

The research and development of this project (reverse engineering, patches,
scripts and this README) were done with the assistance of an LLM (specifically Claude Sonnet 5.5). 

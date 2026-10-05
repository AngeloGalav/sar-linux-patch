#!/bin/bash
# Silent Hill: The Arcade - Linux installer.
#
#   ./install.sh ["/path/to/Silent Hill Arcade"]   (asks for the folder if not given)
#   ./install.sh --restore "/path/to/Silent Hill Arcade"
#
# Patches the PC release of the game (the Collection Chamber repack with
# KSHG.exe / KSHG_no_cursor.exe / shaiolib.CRK.dll) so it runs under Wine/Proton,
# re-encodes the movies, and installs run_linux.sh into the game folder.
# Every modified file is kept as NAME.orig; --restore puts them back.
# Re-running is safe: finished steps are skipped.
#
#   --no-videos               skip the movie conversion (movies then stay black)
#   --delete-original-videos  delete the original movies after converting them
#   --fast-videos             convert the movies about 2.5x faster at slightly lower quality
#   --jobs N                  parallel encoders for the movie conversion (default: all CPUs)
#   --desktop                 also add "Silent Hill: The Arcade" to the application menu
#   --no-gui                  ask in the terminal instead of opening dialog windows
#   --yes                     don't ask anything (convert movies, keep the originals)
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PATCHES="$HERE/patches"   # Python patchers, movie converter, default key bindings
VIDEOS=1 DELETE_ORIG=0 FAST=0 JOBS="$(nproc)" DESKTOP=0 RESTORE=0 GUI=1 ASSUME_YES=0 GAME_DIR=""
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
while [ $# -gt 0 ]; do
    case "$1" in
        --no-videos) VIDEOS=0 ;;
        --delete-original-videos) DELETE_ORIG=1 ;;
        --fast-videos) FAST=1 ;;
        --jobs) JOBS="$2"; shift ;;
        --desktop) DESKTOP=1 ;;
        --restore) RESTORE=1 ;;
        --no-gui) GUI=0 ;;
        --yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown option $1" >&2; usage >&2; exit 2 ;;
        *) GAME_DIR="$1" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# User interface: zenity (any desktop), else kdialog (KDE), else the terminal.
# Dialog texts avoid < > & because zenity renders them as markup.
# ---------------------------------------------------------------------------
TITLE="Silent Hill: The Arcade - Linux installer"
UI=text
if [ "$GUI" = 1 ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if command -v zenity >/dev/null; then UI=zenity
    elif command -v kdialog >/dev/null; then UI=kdialog; fi
fi

ui_info() {    # ui_info TEXT
    case "$UI" in
        zenity)  zenity --info --title "$TITLE" --width 600 --text "$1" 2>/dev/null || true ;;
        kdialog) kdialog --title "$TITLE" --msgbox "$1" 2>/dev/null || true ;;
        text)    printf '\n%s\n' "$1" ;;
    esac
}
ui_error() {   # ui_error TEXT
    case "$UI" in
        zenity)  zenity --error --title "$TITLE" --width 600 --text "$1" 2>/dev/null || true ;;
        kdialog) kdialog --title "$TITLE" --error "$1" 2>/dev/null || true ;;
    esac
    printf '\nERROR: %s\n' "$1" >&2
}
ui_confirm() { # ui_confirm TEXT OK_LABEL CANCEL_LABEL  -> 0 if accepted
    [ "$ASSUME_YES" = 1 ] && return 0
    case "$UI" in
        zenity)  zenity --question --title "$TITLE" --width 640 --text "$1" \
                        --ok-label "$2" --cancel-label "$3" 2>/dev/null ;;
        kdialog) kdialog --title "$TITLE" --yes-label "$2" --no-label "$3" --yesno "$1" 2>/dev/null ;;
        text)    printf '\n%s\n\n' "$1"; local a; read -r -p "$2? [Y/n] " a < /dev/tty; [[ ! "$a" =~ ^[Nn] ]] ;;
    esac
}
ui_choose_dir() {
    case "$UI" in
        zenity)  zenity --file-selection --directory --title "Select the Silent Hill Arcade game folder" 2>/dev/null ;;
        kdialog) kdialog --title "Select the Silent Hill Arcade game folder" --getexistingdirectory "$HOME" 2>/dev/null ;;
        text)    local d; read -r -p "Path to the Silent Hill Arcade game folder: " d < /dev/tty; echo "$d" ;;
    esac
}
step() { printf '\n==> %s\n' "$*"; }
die() { ui_error "$*"; exit 1; }

# No folder given: use the current folder or the installer's own folder if it is
# the game folder (the package may be unpacked straight into it), else ask.
if [ -z "$GAME_DIR" ]; then
    for d in "$PWD" "$HERE"; do
        [ -f "$d/KSHG.exe" ] && [ -d "$d/Data" ] && { GAME_DIR="$d"; break; }
    done
fi
if [ -z "$GAME_DIR" ]; then
    GAME_DIR="$(ui_choose_dir)" || true
    [ -n "$GAME_DIR" ] || { usage; exit 2; }
fi
[ -d "$GAME_DIR" ] || die "Folder not found: $GAME_DIR"
GAME_DIR="$(cd "$GAME_DIR" && pwd)"
DESKTOP_FILE="$HOME/.local/share/applications/sh-arcade.desktop"
# true if the package itself lives in the game folder (its run_linux.sh is the
# installed launcher, so it must be neither copied onto itself nor deleted)
in_game_dir() { [ "$HERE/run_linux.sh" -ef "$GAME_DIR/run_linux.sh" ]; }

# ---------------------------------------------------------------------------
# --restore
# ---------------------------------------------------------------------------
if [ "$RESTORE" = 1 ]; then
    ui_confirm "This puts back the original game files in

$GAME_DIR

and removes the Linux launcher and the crosshair version of the game.
Movies whose originals were deleted after conversion stay converted." "Restore" "Cancel" || exit 0
    step "Restoring original files in $GAME_DIR"
    find "$GAME_DIR" -name '*.orig' -print0 | while IFS= read -r -d '' f; do
        mv -f "$f" "${f%.orig}"; echo "  restored ${f#"$GAME_DIR"/}"
    done
    in_game_dir || rm -f "$GAME_DIR/run_linux.sh"
    rm -rf "$GAME_DIR/KSHG_cursor.exe" "$GAME_DIR/linux" "$GAME_DIR/.linux-tmp"
    rm -f "$DESKTOP_FILE"
    ui_info "Original files restored.

The Wine prefix (~/.local/share/sh-arcade) was left alone; delete it by hand if you no longer need it."
    exit 0
fi

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
step "Checking the game folder"
for f in KSHG.exe KSHG_no_cursor.exe libutil.dll shaiolib.dll shaiolib.CRK.dll config.exe \
         Data/TestDat/KSHG.crc sv/CrossHair.cur; do
    [ -e "$GAME_DIR/$f" ] || die "$f was not found in
$GAME_DIR

Is this the Silent Hill: The Arcade folder?"
done
echo "  $GAME_DIR"

step "Checking requirements"
command -v python3 >/dev/null || die "python3 is required."
if [ "$VIDEOS" = 1 ]; then
    command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null ||
        die "ffmpeg (with ffprobe) is required to convert the movies. Install it, or run the installer with --no-videos."
    # (no "ffmpeg | grep -q": with pipefail, grep closing early makes ffmpeg die of SIGPIPE)
    encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
    grep -q ' cinepak ' <<< "$encoders" || die "Your ffmpeg has no Cinepak encoder."
fi
export SH_TOOLS="$GAME_DIR/linux"
# shellcheck source=proton.sh
source "$HERE/proton.sh"
PROTON="$(find_proton)" || die "No usable Proton was found.

Install GE-Proton 10 (for example with ProtonUp-Qt) and run the installer again, or point it to a Proton 10 build with PROTON_DIR=/path/to/proton."
echo "  Proton: $PROTON"

# ---------------------------------------------------------------------------
# Welcome
# ---------------------------------------------------------------------------
ui_confirm "This installer makes the PC version of Silent Hill: The Arcade playable on Linux.

Game folder:  $GAME_DIR
Proton:       ${PROTON##*/}

What it does:
  1. Patches the game so it works under Wine/Proton: a MIDI device crash, a
      broken I/O error check that blocked the Start button, and movie playback.
      The checksum the game verifies at boot is preserved.
  2. Creates KSHG_cursor.exe, a version of the game that shows a crosshair.
  3. Converts the movies to a format Wine can play. This takes a while;
      the next window lets you choose.
  4. Installs run_linux.sh in the game folder to start the game.

Every file it changes is kept as a .orig copy, so you can undo everything with
  ./install.sh --restore \"$GAME_DIR\"" "Install" "Cancel" || { echo "Installation cancelled."; exit 0; }

# ---------------------------------------------------------------------------
# Patches
# ---------------------------------------------------------------------------
step "Patching libutil.dll (MIDI input that fails to open no longer kills the game)"
python3 "$PATCHES/patch_libutil_midi.py" "$GAME_DIR/libutil.dll"

step "Patching shaiolib.CRK.dll (is_error returned garbage, so the game refused to start)"
python3 "$PATCHES/patch_shaiolib_crk.py" "$GAME_DIR/shaiolib.CRK.dll"

step "Patching KSHG.exe / KSHG_no_cursor.exe (movie fixes, boot checksum kept)"
python3 "$PATCHES/patch_kshg_video.py" "$GAME_DIR/KSHG.exe" "$GAME_DIR/KSHG_no_cursor.exe"

step "Building KSHG_cursor.exe (crosshair cursor version)"
python3 "$PATCHES/patch_kshg_cursor.py" "$GAME_DIR/KSHG_no_cursor.exe" "$GAME_DIR/KSHG_cursor.exe"

# ---------------------------------------------------------------------------
# Movies
# ---------------------------------------------------------------------------
MOVIES_NOTE=""
if [ "$VIDEOS" = 1 ]; then
    step "Checking the movies"
    total=0 pending=0
    while IFS= read -r -d '' v; do
        total=$((total + 1))
        codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$v" </dev/null || true)"
        [ "$codec" = cinepak ] || pending=$((pending + 1))
    done < <(find "$GAME_DIR/Data" -name '*.vid' -print0)
    echo "  $pending of $total movies to convert"

    if [ "$pending" -gt 0 ]; then
        text="Movie conversion

The game's movies are XviD and MPEG-2 videos, which need codecs Wine does not
have, so $pending movies will be re-encoded to Cinepak, a format Wine plays by itself.

This takes a long time: about 20-30 minutes on a fast 16-core CPU (about
10 minutes with fast conversion), and much longer on slower machines. The
Cinepak encoder is old and slow, so the installer runs one encoder per CPU
core ($JOBS here) and your computer will be busy until it finishes. About 7 GB
of free disk space is needed while it runs.

If you skip this step the game still works, but every movie is a black screen.
You can run the installer again later to convert them."
        label_fast="Fast conversion (about 2.5x faster, slightly lower quality)"
        label="Delete the original movies afterwards (frees 1.3 GB; they can't be restored)"
        convert=0
        if [ "$ASSUME_YES" = 1 ]; then
            convert=1
        else
            case "$UI" in
                zenity)
                    if out="$(zenity --list --checklist --title "$TITLE" --width 720 --height 520 \
                                --text "$text" --hide-header --column "" --column "" \
                                "$( [ "$FAST" = 1 ] && echo TRUE || echo FALSE )" "$label_fast" FALSE "$label" \
                                --ok-label "Convert movies" --cancel-label "Skip" 2>/dev/null)"; then
                        convert=1
                        FAST=0; if [[ "$out" == *"$label_fast"* ]]; then FAST=1; fi
                        if [[ "$out" == *"$label"* ]]; then DELETE_ORIG=1; fi
                    fi ;;
                kdialog)
                    if out="$(kdialog --title "$TITLE" --ok-label "Convert movies" --cancel-label "Skip" \
                                --checklist "$text" fast "$label_fast" "$( [ "$FAST" = 1 ] && echo on || echo off )" \
                                delete "$label" off 2>/dev/null)"; then
                        convert=1
                        FAST=0; if [[ "$out" == *fast* ]]; then FAST=1; fi
                        if [[ "$out" == *delete* ]]; then DELETE_ORIG=1; fi
                    fi ;;
                text)
                    printf '\n%s\n\n' "$text"
                    read -r -p "Convert the movies now? [Y/n] " a < /dev/tty
                    if [[ ! "$a" =~ ^[Nn] ]]; then
                        convert=1
                        read -r -p "Fast conversion (about 2.5x faster, slightly lower quality)? [y/N] " a < /dev/tty
                        if [[ "$a" =~ ^[Yy] ]]; then FAST=1; fi
                        read -r -p "Delete the original movies afterwards (they can't be restored then)? [y/N] " a < /dev/tty
                        if [[ "$a" =~ ^[Yy] ]]; then DELETE_ORIG=1; fi
                    fi ;;
            esac
        fi

        if [ "$convert" = 1 ]; then
            need=$((7 * 1024 * 1024))   # KiB: ~5 GB of output + temporary segments
            free=$(df -Pk "$GAME_DIR" | awk 'NR==2 {print $4}')
            [ "$free" -ge "$need" ] ||
                die "About 7 GB of free disk space is needed for the movie conversion, but only $((free / 1024 / 1024)) GB are free on the game's disk."

            step "Converting $pending movies to Cinepak ($JOBS parallel encoders$( [ "$FAST" = 1 ] && echo ", fast mode"))"
            mkdir -p "$GAME_DIR/.linux-tmp"
            LOG="$GAME_DIR/.linux-tmp/convert.log"
            convert_cmd=(nice -n 10 python3 "$PATCHES/convert_videos.py" "$GAME_DIR" -j "$JOBS")
            if [ "$FAST" = 1 ]; then convert_cmd+=(--fast); fi
            if [ "$UI" = zenity ]; then
                # converter output -> percentage and status lines for zenity's progress bar
                if ! TMPDIR="$GAME_DIR/.linux-tmp" "${convert_cmd[@]}" 2>>"$LOG" | tee -a "$LOG" | awk '
                        /segments,/  { print "# Encoding movies..."; fflush() }
                        /^  encoded/ { split($2, a, "/"); printf "%d\n# Encoding movies: %d of %d parts done\n", a[1] * 95 / a[2], a[1], a[2]; fflush() }
                        /^converted/ { sub(/^converted /, ""); n = split($0, p, "/"); print "# Saving " p[n]; fflush() }
                        END          { print 100; fflush() }' |
                     zenity --progress --title "$TITLE" --width 560 --no-cancel --auto-close \
                            --text "Analysing the movies..." --percentage 0 2>/dev/null; then
                    die "The movie conversion failed:

$(tail -n 5 "$LOG")"
                fi
            else
                TMPDIR="$GAME_DIR/.linux-tmp" "${convert_cmd[@]}" | sed '/^skip/d' ||
                    die "The movie conversion failed."
            fi
            rm -rf "$GAME_DIR/.linux-tmp"
            if [ "$DELETE_ORIG" = 1 ]; then
                step "Deleting the original movies"
                find "$GAME_DIR/Data" -name '*.vid.orig' -printf '  Data/%P\n' -delete
            fi
        else
            MOVIES_NOTE="
The movies were not converted, so they will show a black screen.
Run the installer again to convert them."
        fi
    elif [ "$DELETE_ORIG" = 1 ]; then
        step "Deleting the original movies"
        find "$GAME_DIR/Data" -name '*.vid.orig' -printf '  Data/%P\n' -delete
    fi
else
    MOVIES_NOTE="
Movie conversion was skipped (--no-videos), so movies may show a black screen."
fi

# ---------------------------------------------------------------------------
# Launcher
# ---------------------------------------------------------------------------
step "Installing the launcher"
mkdir -p "$GAME_DIR/linux"
cp -f "$HERE/proton.sh" "$PATCHES/make_default_bindings.py" "$GAME_DIR/linux/"
in_game_dir || cp -f "$HERE/run_linux.sh" "$GAME_DIR/run_linux.sh"
# may fail on filesystems without Unix permissions (exFAT, some NTFS mounts);
# the launcher then still works as "bash run_linux.sh"
chmod +x "$GAME_DIR/run_linux.sh" 2>/dev/null ||
    echo "  note: could not make run_linux.sh executable here; start it with: bash run_linux.sh"
echo "$PROTON" > "$GAME_DIR/linux/proton_dir"
echo "  $GAME_DIR/run_linux.sh"

if [ "$DESKTOP" = 1 ]; then
    step "Adding the application menu entry"
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Silent Hill: The Arcade
Comment=Konami light-gun game (Wine/Proton)
Exec="$GAME_DIR/run_linux.sh"
Icon=$GAME_DIR/Icon.ico
Categories=Game;
Actions=cursor;config;

[Desktop Action cursor]
Name=Play with crosshair cursor
Exec="$GAME_DIR/run_linux.sh" cursor

[Desktop Action config]
Name=Key bindings
Exec="$GAME_DIR/run_linux.sh" config
EOF
    echo "  $DESKTOP_FILE"
fi

ui_info "Installation done! Enjoy SH Arcade!

Start the game:
  No cursor:          $GAME_DIR/run_linux.sh
  With crosshair:   $GAME_DIR/run_linux.sh cursor
  Change the keys:  $GAME_DIR/run_linux.sh config

Controls: mouse to aim, left click to shoot, Enter to start (press it twice
on the attract screens), F2 test menu, F1 service, Esc to quit.
$MOVIES_NOTE"

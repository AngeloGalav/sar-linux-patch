#!/bin/bash
# Silent Hill: The Arcade - Linux installer.
#
#   ./install.sh ["/path/to/Silent Hill Arcade"]   (asks for the folder if not given)
#   ./install.sh --restore "/path/to/Silent Hill Arcade"
#
# Patches the PC release of the game (the Collection Chamber repack with
# KSHG.exe / KSHG_no_cursor.exe / shaiolib.CRK.dll) so it runs under Wine/Proton
# and installs run_linux.sh into the game folder.
#
# Movies: GE-Proton 11 plays the original movies as they are. Without it, the
# installer offers to download GE-Proton 11 into Steam's compatibilitytools.d,
# or to re-encode the movies so older Proton versions can play them (slow).
#
# Every patched file is kept as NAME.orig; --restore puts them back.
# Re-running is safe: finished steps are skipped.
#
#   --install-proton          download GE-Proton 11 if it is missing (no question)
#   --convert-videos          if GE-Proton 11 is missing, convert the movies instead of downloading it
#   --no-videos               do neither (movies may stay black)
#   --fast-videos             convert about 2.5x faster at slightly lower quality
#   --delete-original-videos  delete the original movies after converting them
#   --jobs N                  parallel encoders for the conversion (default: all CPUs)
#   --remove-windows-files    delete the Windows-only leftovers (loader, .bat, uninstaller...)
#   --keep-windows-files      keep them (no question)
#   --desktop                 also add "Silent Hill: The Arcade" to the application menu
#   --no-gui                  ask in the terminal instead of opening dialog windows
#   --yes                     don't ask anything (install GE-Proton 11 if missing,
#                             keep the Windows files)
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PATCHES="$HERE/patches"   # Python patchers, movie converter, default key bindings
VIDEO_MODE="" DELETE_ORIG=0 FAST=0 JOBS="$(nproc)" REMOVE_WIN="" DESKTOP=0
RESTORE=0 GUI=1 ASSUME_YES=0 GAME_DIR=""
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
while [ $# -gt 0 ]; do
    case "$1" in
        --install-proton) VIDEO_MODE=install ;;
        --convert-videos) VIDEO_MODE=convert ;;
        --no-videos) VIDEO_MODE=skip ;;
        --fast-videos) FAST=1 ;;
        --delete-original-videos) DELETE_ORIG=1 ;;
        --jobs) JOBS="$2"; shift ;;
        --remove-windows-files) REMOVE_WIN=1 ;;
        --keep-windows-files) REMOVE_WIN=0 ;;
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
ui_choose() {  # ui_choose TEXT TAG LABEL [TAG LABEL ...]  -> prints the chosen TAG (first is default)
    local text="$1"; shift
    local args=() first=1 tag label
    case "$UI" in
        zenity)
            while [ $# -gt 0 ]; do
                args+=("$( [ $first = 1 ] && echo TRUE || echo FALSE )" "$1" "$2"); first=0; shift 2
            done
            zenity --list --radiolist --title "$TITLE" --width 720 --height 480 --text "$text" \
                   --hide-header --column "" --column "tag" --column "" --hide-column 2 --print-column 2 \
                   "${args[@]}" 2>/dev/null ;;
        kdialog)
            while [ $# -gt 0 ]; do
                args+=("$1" "$2" "$( [ $first = 1 ] && echo on || echo off )"); first=0; shift 2
            done
            kdialog --title "$TITLE" --radiolist "$text" "${args[@]}" 2>/dev/null ;;
        text)
            printf '\n%s\n\n' "$text" >&2
            local tags=() n=0 a
            while [ $# -gt 0 ]; do n=$((n + 1)); tags+=("$1"); printf '  %d) %s\n' "$n" "$2" >&2; shift 2; done
            read -r -p "Choice [1]: " a < /dev/tty
            a="${a:-1}"
            [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le "$n" ] || return 1
            echo "${tags[$((a - 1))]}" ;;
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

# Windows-only files of the repack that nothing uses under Linux: the TTX game
# loader and its config, .bat files, the DirectShow filter manager, the
# repack's uninstaller, its readme/links and installer artwork.
WINDOWS_FILES=("Game Loader All RH.exe" "TTX.ini" "sv/Pad.ini" "Run.bat" "config.bat" "DSFMgr.exe"
               "unins000.exe" "unins000.dat" "Uninstall.ico" "README.txt" "Info.txt"
               "The Collection Chamber.URL" "images")

# ---------------------------------------------------------------------------
# --restore
# ---------------------------------------------------------------------------
if [ "$RESTORE" = 1 ]; then
    ui_confirm "This puts back the original game files in

$GAME_DIR

and removes the Linux launcher and the crosshair version of the game.
Movies whose originals were deleted after conversion stay converted, and
Windows files removed by the installer can't be brought back." "Restore" "Cancel" || exit 0
    step "Restoring original files in $GAME_DIR"
    find "$GAME_DIR" -name '*.orig' -print0 | while IFS= read -r -d '' f; do
        mv -f "$f" "${f%.orig}"; echo "  restored ${f#"$GAME_DIR"/}"
    done
    in_game_dir || rm -f "$GAME_DIR/run_linux.sh"
    rm -rf "$GAME_DIR/KSHG_cursor.exe" "$GAME_DIR/linux" "$GAME_DIR/.linux-tmp"
    rm -f "$DESKTOP_FILE"
    ui_info "Original files restored.

The Wine prefix (~/.local/share/sh-arcade) and any GE-Proton installed by the
installer were left alone; delete them by hand if you no longer need them."
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

step "Looking for Proton"
command -v python3 >/dev/null || die "python3 is required."
export SH_TOOLS="$GAME_DIR/linux"
# shellcheck source=proton.sh
source "$HERE/proton.sh"
# PROTON: what the launcher will use. GE-Proton 11+ plays the original movies.
if [ -n "${PROTON_DIR:-}" ]; then
    PROTON="$(find_proton)" || die "PROTON_DIR=$PROTON_DIR is not a usable Proton 10 or newer build."
else
    PROTON="$(find_ge_proton 11 || find_proton || true)"
fi
native_video() { [ -n "$PROTON" ] && [ "$(ge_major "$PROTON")" -ge 11 ]; }
if native_video; then
    echo "  ${PROTON##*/}: plays the original movies"
elif [ -n "$PROTON" ]; then
    echo "  ${PROTON##*/} found, but GE-Proton 11 or newer is needed to play the original movies"
else
    echo "  no usable Proton found"
fi

# ---------------------------------------------------------------------------
# Welcome
# ---------------------------------------------------------------------------
if native_video; then
    proton_line="${PROTON##*/} (plays the original movies)"
else
    proton_line="GE-Proton 11 not found - the installer will offer to download it"
fi
ui_confirm "This installer makes the PC version of Silent Hill: The Arcade playable on Linux.

Game folder:  $GAME_DIR
Proton:       $proton_line

What it does:
  1. Patches the game so it works under Wine/Proton: a MIDI device crash, a
      broken I/O error check that blocked the Start button, and movie playback.
      The checksum the game verifies at boot is preserved.
  2. Creates KSHG_cursor.exe, a version of the game that shows a crosshair.
  3. Makes sure the movies can play. GE-Proton 11 plays them as they are; if you
      don't have it, you can let the installer download it, or convert the movies.
  4. Optionally removes Windows-only files the Linux version doesn't need.
  5. Installs run_linux.sh in the game folder to start the game.

Every file it patches is kept as a .orig copy, so you can undo the changes with
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
# Movies, part 1: GE-Proton 11 download
# ---------------------------------------------------------------------------
install_ge_proton() {
    command -v curl >/dev/null || die "curl is needed to download GE-Proton."
    local arch=x86_64 dest info tag url sum_url size tmp expected actual top
    if [ "$(uname -m)" = aarch64 ]; then arch=aarch64; fi
    dest="$(compat_tools_dir)"
    step "Downloading GE-Proton 11 into $dest"
    # newest release GE-Proton11-* or later, with its tarball and sha512sum
    info="$(curl -fsSL -m 60 "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=30" |
            python3 -c '
import json, re, sys
arch = sys.argv[1]
for r in json.load(sys.stdin):
    m = re.match(r"GE-Proton(\d+)-", r["tag_name"])
    if r.get("prerelease") or not m or int(m.group(1)) < 11:
        continue
    assets = {a["name"]: a for a in r["assets"]}
    tag = r["tag_name"]
    for name in (tag + "-" + arch + ".tar.gz", tag + ".tar.gz"):
        if name in assets and name.replace(".tar.gz", ".sha512sum") in assets:
            a, s = assets[name], assets[name.replace(".tar.gz", ".sha512sum")]
            print(r["tag_name"], a["browser_download_url"], s["browser_download_url"], a["size"])
            sys.exit(0)
sys.exit(1)' "$arch")" || die "Could not find a GE-Proton 11 download on GitHub. Check your internet connection, or install GE-Proton 11 with ProtonUp-Qt and run the installer again."
    read -r tag url sum_url size <<< "$info"
    mkdir -p "$dest"
    tmp="$dest/.$tag.tar.gz.part"
    echo "  $tag ($((size / 1048576)) MB)"
    if [ "$UI" = zenity ]; then
        curl -fL --retry 3 -sS -o "$tmp" "$url" &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            local got; got=$(stat -c %s "$tmp" 2>/dev/null || echo 0)
            echo "$((got * 99 / size))"
            echo "# Downloading $tag: $((got / 1048576)) of $((size / 1048576)) MB"
            sleep 1
        done | zenity --progress --title "$TITLE" --width 560 --no-cancel --auto-close \
                      --text "Downloading $tag..." --percentage 0 2>/dev/null || true
        wait "$pid" || { rm -f "$tmp"; die "The GE-Proton download failed."; }
    else
        curl -fL --retry 3 --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "The GE-Proton download failed."; }
    fi
    expected="$(curl -fsSL -m 60 "$sum_url" | awk '{print $1}')"
    actual="$(sha512sum "$tmp" | awk '{print $1}')"
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
        rm -f "$tmp"; die "The downloaded GE-Proton is damaged (checksum mismatch). Please run the installer again."
    fi
    echo "  checksum ok, unpacking"
    top="$(tar tzf "$tmp" | awk -F/ 'NR == 1 {print $1}')"
    tar xzf "$tmp" -C "$dest" || { rm -f "$tmp"; die "Could not unpack GE-Proton into $dest."; }
    rm -f "$tmp"
    proton_ok "$dest/$top" || die "The downloaded GE-Proton ($dest/$top) looks incomplete."
    PROTON="$dest/$top"
    echo "  installed $PROTON (restart Steam if you also want to use it there)"
}

# ---------------------------------------------------------------------------
# Movies, part 2: conversion for older Proton
# ---------------------------------------------------------------------------
convert_movies() {
    command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null ||
        die "ffmpeg (with ffprobe) is required to convert the movies. Install it and run the installer again."
    # (no "ffmpeg | grep -q": with pipefail, grep closing early makes ffmpeg die of SIGPIPE)
    local encoders; encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
    grep -q ' cinepak ' <<< "$encoders" || die "Your ffmpeg has no Cinepak encoder."

    step "Checking the movies"
    local total=0 pending=0 v codec
    while IFS= read -r -d '' v; do
        total=$((total + 1))
        codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$v" </dev/null || true)"
        [ "$codec" = cinepak ] || pending=$((pending + 1))
    done < <(find "$GAME_DIR/Data" -name '*.vid' -print0)
    echo "  $pending of $total movies to convert"
    [ "$pending" -gt 0 ] || return 0

    local text="Movie conversion

$pending movies will be re-encoded to Cinepak, a format older Proton versions
play by themselves.

This takes a long time: about 20-30 minutes on a fast 16-core desktop CPU
(about 10 minutes with fast conversion), and around 2 hours on a Steam Deck.
The installer runs one encoder per CPU core ($JOBS here), so the computer is
busy until it finishes. About 7 GB of free disk space is needed while it runs."
    local label_fast="Fast conversion (about 2.5x faster, slightly lower quality)"
    local label="Delete the original movies afterwards (frees 1.3 GB; they can't be restored)"
    local convert=0 out a
    if [ "$ASSUME_YES" = 1 ]; then
        convert=1
    else
        case "$UI" in
            zenity)
                if out="$(zenity --list --checklist --title "$TITLE" --width 720 --height 480 \
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
    if [ "$convert" != 1 ]; then
        MOVIES_NOTE="
The movies were not converted, so they will show a black screen.
Run the installer again to convert them or to get GE-Proton 11."
        return 0
    fi

    local need=$((7 * 1024 * 1024)) free   # KiB: ~5 GB of output + temporary segments
    free=$(df -Pk "$GAME_DIR" | awk 'NR==2 {print $4}')
    [ "$free" -ge "$need" ] ||
        die "About 7 GB of free disk space is needed for the movie conversion, but only $((free / 1024 / 1024)) GB are free on the game's disk."

    step "Converting $pending movies to Cinepak ($JOBS parallel encoders$( [ "$FAST" = 1 ] && echo ", fast mode"))"
    mkdir -p "$GAME_DIR/.linux-tmp"
    local LOG="$GAME_DIR/.linux-tmp/convert.log"
    local convert_cmd=(nice -n 10 python3 "$PATCHES/convert_videos.py" "$GAME_DIR" -j "$JOBS")
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
}

# ---------------------------------------------------------------------------
# Movies, part 3: decide
# ---------------------------------------------------------------------------
MOVIES_NOTE=""
if ! native_video && [ "$VIDEO_MODE" != skip ] && [ "$VIDEO_MODE" != convert ]; then
    if [ -z "$VIDEO_MODE" ] && [ "$ASSUME_YES" != 1 ]; then
        choice_text="GE-Proton 11 not found

The game's movies are XviD and MPEG-2 videos. GE-Proton 11 or newer plays
them as they are; older Proton versions show a black screen instead.
How do you want to get working movies?"
        install_label="Download and install GE-Proton 11 (about 560 MB, recommended)"
        convert_label="Convert the movies for older Proton (slow: about 2 hours on a Steam Deck)"
        skip_label="Neither (the game works, but the movies stay black)"
        if [ -n "$PROTON" ]; then
            VIDEO_MODE="$(ui_choose "$choice_text" install "$install_label" convert "$convert_label" skip "$skip_label")" ||
                { echo "Installation cancelled."; exit 0; }
        else
            VIDEO_MODE="$(ui_choose "$choice_text

No other usable Proton was found either, so GE-Proton 11 is needed to play." install "$install_label")" ||
                { echo "Installation cancelled."; exit 0; }
        fi
    fi
    [ -n "$VIDEO_MODE" ] || VIDEO_MODE=install
    if [ "$VIDEO_MODE" = install ]; then install_ge_proton; fi
fi
[ -n "$PROTON" ] || die "No usable Proton was found. Install GE-Proton 11 (for example with ProtonUp-Qt) and run the installer again."

if native_video; then
    step "Movies"
    echo "  ${PROTON##*/} plays the original movies, no conversion needed"
elif [ "$VIDEO_MODE" = convert ]; then
    convert_movies
else
    MOVIES_NOTE="
The movies were not set up, so they may show a black screen.
Run the installer again to get GE-Proton 11 or to convert them."
fi

# The game plays each movie's soundtrack itself (Data/Sound/EVENT), and the
# movie files carry the same audio: under Wine both are heard, like an echo.
# Drop the movies' audio track (stream copy, seconds). With GE-Proton 11 the
# movies are rebuilt from the originals, undoing an earlier Cinepak conversion.
step "Removing the duplicate audio track from the movies"
if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null; then
    strip_args=("$GAME_DIR")
    if native_video; then strip_args+=(--from-originals); fi
    python3 "$PATCHES/strip_movie_audio.py" "${strip_args[@]}" | sed 's/^/  /' ||
        die "Could not remove the audio track from the movies."
else
    echo "  ffmpeg not found: skipped (the movies' voices will be heard twice, like an echo)"
    MOVIES_NOTE="$MOVIES_NOTE
Install ffmpeg and run the installer again to fix the doubled voices in the movies."
fi

# ---------------------------------------------------------------------------
# Windows leftovers
# ---------------------------------------------------------------------------
present=()
for f in "${WINDOWS_FILES[@]}"; do
    if [ -e "$GAME_DIR/$f" ]; then present+=("$f"); fi
done
if [ "${#present[@]}" -gt 0 ]; then
    if [ -z "$REMOVE_WIN" ]; then
        REMOVE_WIN=0
        if [ "$ASSUME_YES" != 1 ] && ui_confirm "Remove Windows-only files?

These files came with the Windows version and are not used on Linux
(the game loader, .bat files, the uninstaller, readme and links):

$(printf '  %s\n' "${present[@]}")
They can't be brought back by --restore." "Remove them" "Keep them"; then
            REMOVE_WIN=1
        fi
    fi
    if [ "$REMOVE_WIN" = 1 ]; then
        step "Removing Windows-only files"
        for f in "${present[@]}"; do rm -rf "${GAME_DIR:?}/$f"; echo "  $f"; done
    fi
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
echo "  $GAME_DIR/run_linux.sh (using ${PROTON##*/})"

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

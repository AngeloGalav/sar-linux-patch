#!/bin/bash
# Silent Hill: The Arcade - Linux launcher (installed into the game folder by install.sh).
#
#   ./run_linux.sh            play, no cursor            (KSHG_no_cursor.exe)
#   ./run_linux.sh cursor     play with crosshair cursor (KSHG_cursor.exe, sv/CrossHair.cur)
#   ./run_linux.sh config     key binding tool           (config.exe sha)
#
# Paths:
#   game folder  the folder this script is in (symlinks are followed)
#   Proton       $PROTON_DIR, else the one chosen by install.sh (linux/proton_dir),
#                else autodetected (newest GE-Proton, then Proton Experimental/10)
#   Wine prefix  $SH_PREFIX, else ~/.local/share/sh-arcade/pfx (created on first run)
#
# Keys: mouse = aim, left click = trigger, Enter = 1P start, 2 = 2P start,
# 3/4 = 1P option L/R, 5/6 = 2P option L/R, F2 = test, F1 = service, Esc = quit.
# In attract mode the first Start skips the current screen, the next starts a game.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export SH_TOOLS="$GAME_DIR/linux"
# shellcheck source=proton.sh
source "$SH_TOOLS/proton.sh"
PROTON_DIR="$(find_proton)" || {
    echo "No usable Proton found. Install GE-Proton (e.g. with ProtonUp-Qt) or set PROTON_DIR." >&2
    exit 1
}
export WINEPREFIX="${SH_PREFIX:-$HOME/.local/share/sh-arcade/pfx}"

LIB="$PROTON_DIR/files/lib"
WINE="$PROTON_DIR/files/bin/wine"
WINESERVER="$PROTON_DIR/files/bin/wineserver"

# Same library/GStreamer environment the proton script sets up (GStreamer does the
# AVI demuxing for the movies; the Cinepak decoding itself is Wine's iccvid).
export LD_LIBRARY_PATH="$LIB/x86_64-linux-gnu:$LIB/i386-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WINEDLLPATH="$LIB/vkd3d:$LIB/wine"
export GST_PLUGIN_SYSTEM_PATH_1_0="$LIB/x86_64-linux-gnu/gstreamer-1.0:$LIB/i386-linux-gnu/gstreamer-1.0"
export WINE_GST_REGISTRY_DIR="$(dirname "$WINEPREFIX")/gstreamer-1.0/"
# DXVK d3d9: proper 640x480 fullscreen scaling (wined3d gives a squashed window).
export WINEDLLOVERRIDES="d3d9=n,b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
# Cap at 60 FPS like the Windows TTX loader did ([FPS] Limit in TTX.ini): the
# arcade game expects a 60 Hz display, so it could run too fast on 120/144 Hz
# monitors. Override with DXVK_FRAME_RATE=0 to disable the cap.
export DXVK_FRAME_RATE="${DXVK_FRAME_RATE:-60}"
export WINEDEBUG="${WINEDEBUG:--all}"

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "Creating Wine prefix in $WINEPREFIX (first run only) ..."
    mkdir -p "$WINEPREFIX"
    "$WINE" wineboot -i >/dev/null 2>&1
    "$WINESERVER" -w
fi
# Copy by content, not date: wineboot's placeholder DLLs are newer than Proton's,
# so `cp -u` would silently keep Wine's own d3d9 instead of DXVK's.
install_dll() { cmp -s "$1" "$2" || cp -f "$1" "$2"; }
for f in "$LIB"/vkd3d/i386-windows/*.dll; do install_dll "$f" "$WINEPREFIX/drive_c/windows/syswow64/${f##*/}"; done
for f in "$LIB"/vkd3d/x86_64-windows/*.dll; do install_dll "$f" "$WINEPREFIX/drive_c/windows/system32/${f##*/}"; done
install_dll "$LIB/wine/dxvk/i386-windows/d3d9.dll" "$WINEPREFIX/drive_c/windows/syswow64/d3d9.dll"

# Default key bindings (only written if missing; config.exe can change them).
APPDATA="$WINEPREFIX/drive_c/users/$("$WINE" cmd /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Roaming"
python3 "$SH_TOOLS/make_default_bindings.py" "$APPDATA" >/dev/null

cd "$GAME_DIR"
case "${1:-play}" in
    config) exec "$WINE" config.exe sha ;;
    cursor) exec "$WINE" KSHG_cursor.exe ;;
    play)   exec "$WINE" KSHG_no_cursor.exe ;;
    *)      echo "usage: $0 [play|cursor|config]" >&2; exit 2 ;;
esac

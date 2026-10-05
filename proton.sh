# Proton lookup shared by install.sh and run_linux.sh (source it, then call find_proton).
#
# A usable Proton is a Proton 10-style build (GE-Proton10+, Proton Experimental,
# Proton 10): Wine in files/bin, DXVK's 32-bit d3d9 in files/lib/wine/dxvk and
# vkd3d in files/lib/vkd3d. Tested with GE-Proton10-34.
#
# Order: $PROTON_DIR, then the path saved by install.sh ($SH_TOOLS/proton_dir),
# then the newest GE-Proton, then Valve's Proton Experimental / Proton 10, in the
# usual Steam locations (native and Flatpak).

proton_ok() {
    [ -x "$1/files/bin/wine" ] &&
    [ -f "$1/files/lib/wine/dxvk/i386-windows/d3d9.dll" ] &&
    [ -d "$1/files/lib/vkd3d/i386-windows" ]
}

find_proton() {
    local p root
    if [ -n "${PROTON_DIR:-}" ]; then
        proton_ok "$PROTON_DIR" && { echo "$PROTON_DIR"; return 0; }
        echo "PROTON_DIR=$PROTON_DIR is not a usable Proton 10-style build" >&2
        return 1
    fi
    if [ -n "${SH_TOOLS:-}" ] && [ -f "$SH_TOOLS/proton_dir" ]; then
        p="$(cat "$SH_TOOLS/proton_dir")"
        proton_ok "$p" && { echo "$p"; return 0; }
    fi
    local roots=("$HOME/.local/share/Steam" "$HOME/.steam/root" "$HOME/.steam/steam"
                 "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" "/usr/share/steam")
    # newest GE-Proton first, then Proton Experimental, then Proton 1x.y
    for root in "${roots[@]}"; do
        while IFS= read -r p; do
            proton_ok "$p" && { echo "$p"; return 0; }
        done < <(ls -d "$root"/compatibilitytools.d/GE-Proton* 2>/dev/null | sort -rV)
    done
    for root in "${roots[@]}"; do
        while IFS= read -r p; do
            proton_ok "$p" && { echo "$p"; return 0; }
        done < <(printf '%s\n' "$root/steamapps/common/Proton - Experimental";
                 ls -d "$root"/steamapps/common/Proton\ 1[0-9]* 2>/dev/null | sort -rV)
    done
    return 1
}

# Major version of a GE-Proton build ("GE-Proton11-7" -> 11), 0 if unknown.
# GE-Proton 11 plays the game's original XviD/MPEG-2 movies (its DirectShow
# goes through FFmpeg), so no movie conversion is needed with it.
ge_major() {
    local v
    v="$(awk '{print $2}' "$1/version" 2>/dev/null)"
    if [[ "$v" =~ ^GE-Proton([0-9]+)- ]]; then echo "${BASH_REMATCH[1]}"; else echo 0; fi
}

# Newest usable GE-Proton whose major version is at least $1.
find_ge_proton() {
    local p root
    for root in "$HOME/.local/share/Steam" "$HOME/.steam/root" "$HOME/.steam/steam" \
                "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" "/usr/share/steam"; do
        while IFS= read -r p; do
            if proton_ok "$p" && [ "$(ge_major "$p")" -ge "$1" ]; then echo "$p"; return 0; fi
        done < <(ls -d "$root"/compatibilitytools.d/GE-Proton* 2>/dev/null | sort -rV)
    done
    return 1
}

# Where to install a downloaded GE-Proton so Steam (and this launcher) find it.
compat_tools_dir() {
    local root
    for root in "$HOME/.local/share/Steam" "$HOME/.steam/root" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
        if [ -d "$root" ]; then echo "$root/compatibilitytools.d"; return 0; fi
    done
    echo "$HOME/.local/share/Steam/compatibilitytools.d"
}

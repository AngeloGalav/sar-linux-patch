#!/usr/bin/env python3
"""Write a default key-binding file for Silent Hill: The Arcade (libutil "sha").

Buttons (start/test/service/exit) reach the game through libutil.dll's
DirectInput bindings, normally created by config.exe ("config sha") in
%APPDATA%\\bemani_config\\sha_v01.cfg. Without that file no button works.
Aim and trigger come straight from the mouse (shaiolib uses GetCursorPos and
GetAsyncKeyState(VK_LBUTTON)), so they need no binding.

File layout (libutil.dll 0x100011f0 load / 0x10001280 save):
  0x000 u32 binding count
  0x004 u32 attribute count
  0x008 wchar[260] x3  e-amusement card / machine-id paths (empty here)
  0x620 binding[count]   4 bytes: device type (0 = keyboard), device index,
                         control (DirectInput DIK scancode), action code
        attr[count]      12 bytes: char name[8], u32 value
Bindings are looked up with a binary search, so they are kept sorted.

Action codes (config.exe "sha" table): 0xff EXIT, 0x01 TEST, 0x02 SERVICE,
0x10 1P_START, 0x11 1P_TRIGGER, 0x12/0x13 1P OPTION L/R, 0x20 2P_START,
0x21 2P_TRIGGER, 0x22/0x23 2P OPTION L/R (names confirmed in INPUT CHECK).

Usage: make_default_bindings.py <APPDATA dir> [--force]
"""
import struct, sys
from pathlib import Path

DIK = {"ESC": 0x01, "2": 0x03, "3": 0x04, "4": 0x05, "5": 0x06, "6": 0x07,
       "ENTER": 0x1C, "F1": 0x3B, "F2": 0x3C}
DEFAULTS = [            # key, action
    ("ESC", 0xFF),      # exit
    ("F2", 0x01),       # test (operator menu)
    ("F1", 0x02),       # service
    ("ENTER", 0x10),    # 1P start
    ("2", 0x20),        # 2P start
    ("3", 0x12),        # 1P option L
    ("4", 0x13),        # 1P option R
    ("5", 0x22),        # 2P option L
    ("6", 0x23),        # 2P option R
]

def build():
    binds = sorted((0, 0, DIK[k], a) for k, a in DEFAULTS)
    header = struct.pack("<II", len(binds), 0) + b"\0" * (0x620 - 8)
    return header + b"".join(bytes(b) for b in binds)

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]) / "bemani_config" / "sha_v01.cfg"
    if out.exists() and "--force" not in sys.argv:
        print(f"{out} exists, leaving it alone (use --force to overwrite)"); return
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(build())
    print(f"wrote {out}: " + ", ".join(f"{k}->{a:#04x}" for k, a in DEFAULTS))

if __name__ == "__main__":
    main()

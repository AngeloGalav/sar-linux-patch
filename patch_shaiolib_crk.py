#!/usr/bin/env python3
"""Patch shaiolib.CRK.dll (Silent Hill: The Arcade I/O emulation) so
shaiolib_is_error() returns 0.

The cracked I/O library implements shaiolib_is_error (0x10001380) as
"log an empty string; ret" without setting eax, so it returns whatever
OutputDebugStringW left there. On Windows that happened to be 0; under Wine it
is 1, the game sets its I/O-error flag (0x6e3a18) every frame and refuses to
start a game from attract mode (buttons still work in test mode).

Patch: add esp,4; nop  ->  pop ecx; xor eax,eax  (same stack effect, eax = 0).
The relocated push at 0x10001381 is left untouched.

Usage: patch_shaiolib_crk.py [path/to/shaiolib.CRK.dll]   (writes .orig backup)
"""
import shutil, sys
from pathlib import Path

TEXT_VA, TEXT_RAW = 0x10001000, 0x400
VA, OLD, NEW = 0x1000138a, bytes.fromhex("83c40490c3"), bytes.fromhex("5933c090c3")

def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "shaiolib.CRK.dll")
    data = bytearray(path.read_bytes())
    o = VA - TEXT_VA + TEXT_RAW
    if data[o:o + len(NEW)] == NEW:
        print(f"{path}: already patched"); return
    if data[o:o + len(OLD)] != OLD:
        sys.exit(f"{path}: unexpected bytes at {VA:#x} ({data[o:o+len(OLD)].hex()}), wrong version?")
    backup = path.with_name(path.name + ".orig")
    if not backup.exists():
        shutil.copy2(path, backup)
    data[o:o + len(NEW)] = NEW
    path.write_bytes(data)
    print(f"{path}: shaiolib_is_error now returns 0, backup in {backup.name}")

if __name__ == "__main__":
    main()

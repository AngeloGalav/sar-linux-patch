#!/usr/bin/env python3
"""Patch libutil.dll (Silent Hill: The Arcade) so a MIDI-in device that fails
to open is skipped instead of killing the process with exit(-1).

Under Wine, winealsa exposes PipeWire/ALSA sequencer ports as MIDI inputs and
midiInOpen() on them returns MMSYSERR_NOTENABLED (3). The original code in the
MIDI init loop (VA 0x10002150) treats any midiInGetDevCaps/midiInOpen/
midiInStart failure as fatal.

Patched flow: every failure path jumps to 0x1000221c, which now logs
"Error opening MIDI device %s" via the non-fatal logger (the loop's own
"Opened %s" call at 0x100021f4) and continues with the next device.
No relocated operand is touched, so the .reloc table stays valid.

Usage: patch_libutil_midi.py [path/to/libutil.dll]   (writes libutil.dll.orig backup)
"""
import hashlib, shutil, sys
from pathlib import Path

TEXT_VA, TEXT_RAW = 0x10001000, 0x400

# (VA, original bytes, patched bytes, comment)
PATCHES = [
    (0x100021ae, "7560", "756c", "midiInGetDevCaps fail -> 0x1000221c (was fatal 0x10002210)"),
    (0x100021e2, "7552", "7538", "midiInStart fail      -> 0x1000221c (was fatal 0x10002236)"),
    (0x10002221, "69ff680100008d4c070c",
                 "8d4c060c660f1f440000", "lea ecx,[esi+eax+0xc]; nop6 (keep edi = loop index)"),
    (0x10002231, "e85afeffff", "e9beffffff", "call fatal_exit -> jmp 0x100021f4 (log + continue)"),
]

def off(va): return va - TEXT_VA + TEXT_RAW

def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "libutil.dll")
    data = bytearray(path.read_bytes())
    if all(data[off(va):off(va) + len(bytes.fromhex(new))] == bytes.fromhex(new) for va, _, new, _ in PATCHES):
        print(f"{path}: already patched"); return
    for va, old, _, _ in PATCHES:
        o = off(va); old = bytes.fromhex(old)
        if data[o:o + len(old)] != old:
            sys.exit(f"{path}: unexpected bytes at {va:#x} ({data[o:o+len(old)].hex()}), wrong libutil.dll version?")
    backup = path.with_name(path.name + ".orig")
    if not backup.exists():
        shutil.copy2(path, backup)
    for va, old, new, why in PATCHES:
        o = off(va); data[o:o + len(bytes.fromhex(new))] = bytes.fromhex(new)
        print(f"  {va:#x}: {old} -> {new}  ; {why}")
    path.write_bytes(data)
    print(f"{path}: patched (sha1 {hashlib.sha1(data).hexdigest()}), backup in {backup.name}")

if __name__ == "__main__":
    main()

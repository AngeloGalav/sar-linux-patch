#!/usr/bin/env python3
"""Patch KSHG.exe / KSHG_no_cursor.exe (Silent Hill: The Arcade) so the movie
frame copy does not dereference a NULL frame buffer.

The game plays .vid movies through DirectShow with its own RGB32 renderer.
When no decoder is available for the video stream (e.g. XviD AVI under Wine,
where Windows users relied on K-Lite/ffdshow), RenderFile only connects the
audio and returns a partial-success code. The renderer never gets SetMediaType,
its frame buffer (renderer+0x160) stays NULL, and the per-frame copy routine
at 0x401bd0 crashes on `movdqu xmm0,[esi+edx]` (0x401c7d).

Patch: 0x401bd0 jumps to a code cave (int3 padding at 0x6174cc) that returns
false ("no new frame", same as the caller's not-ready path) when the renderer
or its buffer is NULL, otherwise runs the original prologue and jumps back.
The exe has no relocations, so absolute addresses are safe.

The game verifies KSHG.exe (and its data) at boot against Data/TestDat/KSHG.crc
(CRC16, table at 0x688330) and shows "SYSTEM ERROR / reinstall" (SYSDCHK2) on a
mismatch. Two unreachable padding bytes at the end of the cave are therefore
chosen so the whole-file CRC16 equals the original one.

Also: IMediaControl::StopWhenReady at 0x401ebf is replaced with Pause, see PATCHES.

Usage: patch_kshg_video.py KSHG.exe KSHG_no_cursor.exe   (writes <exe>.orig backups)
"""
import shutil, struct, sys
from pathlib import Path

IMAGE_BASE, TEXT_VA, TEXT_RAW = 0x400000, 0x401000, 0x1000
FUNC, CAVE = 0x401bd0, 0x6174cc

def rel32(src_next, dst): return struct.pack("<i", dst - src_next)

cave = (bytes.fromhex("8b4108")                # mov eax,[ecx+8]        ; renderer
        + bytes.fromhex("85c0")                # test eax,eax
        + bytes.fromhex("7414")                # je  no_frame
        + bytes.fromhex("83b86001000000")      # cmp dword [eax+0x160],0 ; frame buffer
        + bytes.fromhex("740b")                # je  no_frame
        + bytes.fromhex("558bec83ec18")        # original: push ebp; mov ebp,esp; sub esp,0x18
        + b"\xe9" + rel32(CAVE + 27, FUNC + 6) # jmp 0x401bd6
        + bytes.fromhex("32c0c21000"))         # no_frame: xor al,al; ret 0x10
assert len(cave) == 32

PATCHES = [
    # movie loader thread: IMediaControl::StopWhenReady -> IMediaControl::Pause.
    # Wine runs StopWhenReady asynchronously (a threadpool callback waits for the
    # pause, then calls Stop); the game calls Run right after, so the late Stop
    # kills the running movie after its first frame.
    (0x401ebf, bytes.fromhex("ff523c"), bytes.fromhex("ff5220")),
    (FUNC, bytes.fromhex("558bec83ec18"), b"\xe9" + rel32(FUNC + 5, CAVE) + b"\x90"),
    (CAVE, b"\xcc" * len(cave), cave),
]

FIX = 0x6174fe  # 2 unreachable int3 padding bytes before the next function (0x617500)
CRC_TABLE = 0x688330 - 0x680000 + 0x280000  # file offset of the CRC16 table in .rdata

def off(va): return va - TEXT_VA + TEXT_RAW

def crc16(data, table):
    c = 0xffff
    for b in data:
        c = ((c & 0xff) << 8) ^ table[(c >> 8) ^ b]
    return c

def force_crc(data, target, pos, table):
    """Set data[pos:pos+2] so crc16(data) == target (CRC is affine over GF(2))."""
    data[pos:pos + 2] = b"\0\0"
    base = crc16(data, table)
    cols = []
    for bit in range(16):
        data[pos + bit // 8] = 1 << (bit % 8)
        cols.append(crc16(data, table) ^ base)
        data[pos + bit // 8] = 0
    # solve sum(x_i * cols[i]) == base ^ target by Gaussian elimination
    rows = [(cols[i], 1 << i) for i in range(16)]
    basis = {}
    for v, m in rows:
        for hb in sorted(basis, reverse=True):
            if v >> hb & 1:
                v ^= basis[hb][0]; m ^= basis[hb][1]
        if v:
            basis[v.bit_length() - 1] = (v, m)
    need, x = base ^ target, 0
    for hb in sorted(basis, reverse=True):
        if need >> hb & 1:
            need ^= basis[hb][0]; x ^= basis[hb][1]
    assert need == 0, "cannot force CRC"
    data[pos:pos + 2] = struct.pack("<H", x)
    assert crc16(data, table) == target

def patch(path):
    data = bytearray(path.read_bytes())
    if all(data[off(va):off(va) + len(new)] == new for va, _, new in PATCHES):
        print(f"{path}: already patched"); return
    for va, old, _ in PATCHES + [(FIX, b"\xcc\xcc", None)]:
        if data[off(va):off(va) + len(old)] != old:
            sys.exit(f"{path}: unexpected bytes at {va:#x}, wrong exe version?")
    backup = path.with_name(path.name + ".orig")
    if not backup.exists():
        shutil.copy2(path, backup)
    table = struct.unpack_from("<256H", data, CRC_TABLE)
    target = crc16(data, table)
    for va, _, new in PATCHES:
        data[off(va):off(va) + len(new)] = new
    force_crc(data, target, off(FIX), table)
    path.write_bytes(data)
    print(f"{path}: patched, CRC16 kept at {target:#06x}, backup in {backup.name}")

if __name__ == "__main__":
    for p in sys.argv[1:] or ["KSHG_no_cursor.exe"]:
        patch(Path(p))

#!/usr/bin/env python3
"""Build KSHG_cursor.exe: a variant of KSHG_no_cursor.exe that shows a crosshair.

On Windows the crosshair (sv\\CrossHair.cur) was drawn by the TTX "Game Loader"
(UseCursorSet=1), which hooks the game; KSHG_no_cursor.exe merely avoided hiding
it. Without the loader (e.g. under Wine) no cursor is ever shown. This variant
makes the game show it itself:

- 0x4cfdd0 (window-class vtable: returns the window cursor, normally
  LoadCursorA(NULL, IDC_ARROW)) jumps to a code cave that returns
  LoadCursorFromFileA("sv\\CrossHair.cur"), resolved via GetModuleHandleA +
  GetProcAddress, falling back to the system IDC_CROSS. (Both callers run at
  startup, while the cwd is still the game root; it later becomes Data\\eng.)
- 0x40873f: the input object's constructor did old = SetCursor(NULL);
  [obj+0x48] = old; SetCursor(old), i.e. it kept "whatever cursor was active"
  (on Windows: the arrow, later replaced by the loader's crosshair; under Wine:
  none). It now calls a second cave that loads the crosshair, sets it and
  stores it in [obj+0x48], the cursor the game re-applies when it shows it.
- 0x4062c3: the "cursor hidden" branch (SetCursor(NULL / garbage)) is disabled,
  so the window cursor is always applied.

KSHG_no_cursor.exe uses raw mouse coordinates (no gun calibration), so shots
land exactly under the crosshair. The boot CRC check only reads KSHG.exe, so an
extra executable is fine. The exe has no relocations.

Usage: patch_kshg_cursor.py KSHG_no_cursor.exe KSHG_cursor.exe
"""
import struct, sys
from pathlib import Path

TEXT_VA, TEXT_RAW = 0x401000, 0x1000
IAT_GetModuleHandleA, IAT_GetProcAddress, IAT_LoadCursorA = 0x680248, 0x6801b4, 0x6802d0
STR_CAVE, PATH_CAVE, CODE_CAVE = 0x617598, 0x617658, 0x63c288   # int3 padding runs
CTOR_CAVE = 0x617670                                              # rest of the 0x617655 run

S_USER32 = b"user32.dll\0"
S_LCFF = b"LoadCursorFromFileA\0"
S_PATH = b"sv\\CrossHair.cur\0"
A_USER32, A_LCFF = STR_CAVE, STR_CAVE + len(S_USER32)

def off(va): return va - TEXT_VA + TEXT_RAW
def imm(v): return struct.pack("<I", v)

def code():
    c = b""
    c += b"\x68" + imm(A_USER32)                    # push "user32.dll"
    c += b"\xff\x15" + imm(IAT_GetModuleHandleA)    # call GetModuleHandleA
    c += b"\x68" + imm(A_LCFF)                      # push "LoadCursorFromFileA"
    c += b"\x50"                                    # push eax
    c += b"\xff\x15" + imm(IAT_GetProcAddress)      # call GetProcAddress
    c += b"\x85\xc0"                                # test eax,eax
    c += b"\x74\x0b"                                # jz fallback
    c += b"\x68" + imm(PATH_CAVE)                   # push path
    c += b"\xff\xd0"                                # call eax
    c += b"\x85\xc0"                                # test eax,eax
    c += b"\x75\x0d"                                # jnz done
    # fallback:
    c += b"\x68\x03\x7f\x00\x00"                    # push IDC_CROSS
    c += b"\x6a\x00"                                # push 0
    c += b"\xff\x15" + imm(IAT_LoadCursorA)         # call LoadCursorA
    c += b"\xc3"                                    # done: ret
    return c

CODE = code()
# ctor helper: eax = load_crosshair(); SetCursor(eax); return eax.
# The ctor already pushed edi (=0) as the argument of the removed SetCursor(NULL),
# so this returns with "ret 4" to keep the stack balanced; ebx holds &SetCursor.
CTOR = (b"\xe8" + struct.pack("<i", CODE_CAVE - (CTOR_CAVE + 5))
        + b"\x50\x50"        # push eax (kept), push eax (arg)
        + b"\xff\xd3"        # call ebx = SetCursor
        + b"\x58"             # pop eax
        + b"\xc2\x04\x00")   # ret 4
PATCHES = [  # (va, original bytes, new bytes)
    (0x4cfdd0, bytes.fromhex("68007f00006a00ff15d0026800c3"),
     b"\xe9" + struct.pack("<i", CODE_CAVE - (0x4cfdd0 + 5)) + b"\x90" * 9),
    (0x4062c3, bytes.fromhex("7415"), b"\x90\x90"),
    (STR_CAVE, b"\xcc" * len(S_USER32 + S_LCFF), S_USER32 + S_LCFF),
    (PATH_CAVE, b"\xcc" * len(S_PATH), S_PATH),
    (CODE_CAVE, b"\xcc" * len(CODE), CODE),
    # ctor: "call ebx(SetCursor); push eax; mov [esi+0x48],eax; call ebx" ->
    #       "call CTOR_CAVE; mov [esi+0x48],eax"
    (0x40873f, bytes.fromhex("ffd350894648ffd3"),
     b"\xe8" + struct.pack("<i", CTOR_CAVE - (0x40873f + 5)) + bytes.fromhex("894648")),
    (CTOR_CAVE, b"\xcc" * len(CTOR), CTOR),
]

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    data = bytearray(src.read_bytes())
    # sanity: the jz/jnz displacements above must land on fallback/done
    assert CODE[25:27] == b"\x74\x0b" and 27 + 11 == CODE.index(b"\x68\x03\x7f"), "bad jz"
    assert CODE[36:38] == b"\x75\x0d" and 38 + 13 == len(CODE) - 1, "bad jnz"
    for va, old, _ in PATCHES:
        if data[off(va):off(va) + len(old)] != old:
            sys.exit(f"{src}: unexpected bytes at {va:#x}, expected KSHG_no_cursor.exe")
    for va, _, new in PATCHES:
        data[off(va):off(va) + len(new)] = new
    dst.write_bytes(data)
    print(f"wrote {dst} (crosshair from sv\\CrossHair.cur, fallback IDC_CROSS)")

if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# Cross-check our assembler against the GNU RISC-V assembler.
# Any disagreement means our encoder (or the test file) is wrong.
set -euo pipefail
SRC="$1"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ours
python3 tools/asm.py "$SRC" -o "$TMP/ours" >/dev/null
tr -d ' ' < "$TMP/ours.hex" | grep -v '^$' > "$TMP/ours.txt"

# GNU as -> raw binary -> hex words
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o "$TMP/gnu.o" "$SRC"
riscv64-unknown-elf-objcopy -O binary "$TMP/gnu.o" "$TMP/gnu.bin"
python3 - "$TMP/gnu.bin" "$TMP/gnu.txt" <<'PY'
import sys, struct
data = open(sys.argv[1], 'rb').read()
with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        f.write("%08x\n" % struct.unpack('<I', data[i:i+4])[0])
PY

if diff -u "$TMP/gnu.txt" "$TMP/ours.txt" > "$TMP/diff.txt"; then
    echo "MATCH: $(wc -l < "$TMP/ours.txt") words identical to GNU as  ($SRC)"
else
    echo "MISMATCH ($SRC):"
    paste -d' ' <(nl -ba "$TMP/gnu.txt") <(cat "$TMP/ours.txt") | awk '$2!=$3{print "  word "$1": gnu="$2" ours="$3}'
    exit 1
fi

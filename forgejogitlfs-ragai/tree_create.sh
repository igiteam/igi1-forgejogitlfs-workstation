#!/bin/bash
# tree_create.sh — generate tree.txt + plain + TSV for the ___openofpcwr workspace
# Works on macOS (BSD) and Linux (GNU).
# Usage: ./tree_create.sh [root-dir]

set -uo pipefail
# NOTE: deliberately NOT using `set -e` — the find fallback needs to be able to fail
#       in one branch without killing the script.

ROOT="${1:-.}"
OUT="tree.txt"
PLAIN_OUT="tree-plain.txt"
TSV_OUT="tree-files.tsv"

ROOT_ABS="$(cd "$ROOT" && pwd)"
ROOT_NAME="$(basename "$ROOT_ABS")"

IGNORE='.git|node_modules|.venv|__pycache__|.DS_Store|build|vcpkg_installed'

# --- 1. Full tree with box-drawing ---------------------------------------
if ! command -v tree >/dev/null 2>&1; then
    echo "Error: 'tree' is not installed." >&2
    echo "  macOS: brew install tree" >&2
    echo "  Linux: sudo apt install tree" >&2
    exit 1
fi

cd "$ROOT_ABS" || exit 1

tree -a -I "$IGNORE" . > "$OUT"

# --- 2. Fix the root label (portable sed) --------------------------------
if sed --version >/dev/null 2>&1; then
    sed -i "1s|^\.|$ROOT_NAME|" "$OUT"
else
    sed -i '' "1s|^\.|$ROOT_NAME|" "$OUT"
fi

# --- 3. Plain-text tree (-i strips box-drawing) --------------------------
tree -a -i -I "$IGNORE" . > "$PLAIN_OUT"

# --- 4. TSV: path<TAB>size ------------------------------------------------
# Use `find ... -exec stat` for portability. BSD stat: -f %z
# GNU stat: -c %s. Detect by probing.
if stat -f '%z' /dev/null >/dev/null 2>&1; then
    # BSD stat (macOS)
    STAT_FMT=(-f '%z')
elif stat -c '%s' /dev/null >/dev/null 2>&1; then
    # GNU stat (Linux)
    STAT_FMT=(-c '%s')
else
    STAT_FMT=()
fi

{
    if [ ${#STAT_FMT[@]} -gt 0 ]; then
        find . \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/.venv/*' \
            -not -path '*/build/*' \
            -not -path '*/vcpkg_installed/*' \
            -type f \
            -exec sh -c '
                for f do
                    printf "%s\t%s\n" "$f" "$(stat '"${STAT_FMT[*]}"' "$f")"
                done
            ' sh {} +
    else
        # No stat — fall back to wc -c, slower but universal
        find . \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/.venv/*' \
            -not -path '*/build/*' \
            -not -path '*/vcpkg_installed/*' \
            -type f \
            -exec sh -c '
                for f do
                    printf "%s\t%s\n" "$f" "$(wc -c < "$f")"
                done
            ' sh {} +
    fi
} | LC_ALL=C sort > "$TSV_OUT"

# --- 5. Report ------------------------------------------------------------
echo "Wrote:"
printf '  %s/%s  (%s lines)\n' "$ROOT_ABS" "$OUT"       "$(wc -l < "$OUT" | tr -d ' ')"
printf '  %s/%s  (%s lines)\n' "$ROOT_ABS" "$PLAIN_OUT" "$(wc -l < "$PLAIN_OUT" | tr -d ' ')"
printf '  %s/%s  (%s lines)\n' "$ROOT_ABS" "$TSV_OUT"   "$(wc -l < "$TSV_OUT" | tr -d ' ')"
echo ""
echo "Sanity check:"
file "$OUT"
head -1 "$OUT" | xxd | head -2
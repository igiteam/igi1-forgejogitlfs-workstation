#!/usr/bin/env bash
#
# github_remove_nested.sh
# Finds and fixes nested Git repositories within the main repository.
#

set -uo pipefail

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
error()   { echo -e "${RED}✗${NC} $*"; }

# ---------- Options ----------
AUTO_YES=false
NO_PUSH=false
NO_COMMIT=false
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Finds and removes nested .git folders inside the current Git repository.

Options:
  -y, --yes         Skip confirmation prompts (auto-confirm)
  -n, --no-commit   Remove nested repos but do not commit
  -p, --no-push     Commit but do not push
  -d, --dry-run     Only report what would be done
  -h, --help        Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)        AUTO_YES=true ;;
        -n|--no-commit)  NO_COMMIT=true ;;
        -p|--no-push)    NO_PUSH=true ;;
        -d|--dry-run)    DRY_RUN=true ;;
        -h|--help)       usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

confirm() {
    local prompt="$1"
    if $AUTO_YES; then
        return 0
    fi
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------- Step 1: Validate repo ----------
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "This is not a git repository"
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT" || exit 1

echo "=== Finding and fixing nested Git repositories ==="
info "Repository root: $REPO_ROOT"

# ---------- Step 2: Git LFS detection ----------
LFS_AVAILABLE=false
if command -v git-lfs > /dev/null 2>&1 && git lfs env > /dev/null 2>&1; then
    success "Git LFS is available"
    LFS_AVAILABLE=true
else
    warn "Git LFS is not available"
fi

# ---------- Step 3: Recursive search ----------
declare -a NESTED_REPOS=()

while IFS= read -r gitdir; do
    dirpath=$(dirname "$gitdir")

    # Skip main repo .git and excluded paths
    if [ "$dirpath" = "." ] \
       || [[ "$dirpath" == *"/.git/"* ]] \
       || [[ "$dirpath" == *"/node_modules/"* ]] \
       || [[ "$dirpath" == *"/build/"* ]] \
       || [[ "$dirpath" == *"/dist/"* ]] \
       || [[ "$dirpath" == *"/vendor/"* ]] \
       || [[ "$dirpath" == *"/.venv/"* ]] \
       || [[ "$dirpath" == *"/venv/"* ]]; then
        continue
    fi

    NESTED_REPOS+=("$dirpath")
done < <(find . -name ".git" -type d 2>/dev/null | sort)

if [ ${#NESTED_REPOS[@]} -eq 0 ]; then
    success "No nested repositories found. Nothing to do."
    exit 0
fi

info "Found ${#NESTED_REPOS[@]} nested repo(s):"

# ---------- Step 4: Analysis & reporting ----------
for dirpath in "${NESTED_REPOS[@]}"; do
    echo ""
    echo "Found nested repo: $dirpath"

    lfs_files=0
    if $LFS_AVAILABLE; then
        lfs_files=$(find "$dirpath" -type f -not -path "*/.git/*" \
            -exec grep -lI "version https://git-lfs" {} \; 2>/dev/null | wc -l)
    fi

    file_count=$(find "$dirpath" -type f -not -path "*/.git/*" 2>/dev/null | wc -l)

    if [ "$lfs_files" -gt 0 ]; then
        warn "Contains $lfs_files Git LFS pointer file(s)"
    fi
    info "Contains $file_count file(s)"
done

echo ""
if ! confirm "Proceed with removing nested .git folders?"; then
    info "Aborted by user."
    exit 0
fi

if $DRY_RUN; then
    warn "Dry run — no changes will be made."
    exit 0
fi

# ---------- Step 5: Automatic cleanup ----------
fixed_count=0

for dirpath in "${NESTED_REPOS[@]}"; do
    gitdir="$dirpath/.git"

    if [ ! -d "$gitdir" ]; then
        warn "Skipping $dirpath (already removed)"
        continue
    fi

    rm -rf "$gitdir"
    rm -f "$dirpath/.gitignore"

    git add -A "$dirpath" > /dev/null 2>&1

    fixed_count=$((fixed_count + 1))
    success "Removed .git folder from $dirpath"
done

# ---------- Step 6: Commit & push ----------
echo ""
echo "=== Summary ==="
echo "Found ${#NESTED_REPOS[@]} nested repositories"
echo "Fixed $fixed_count nested repositories"

echo ""
echo "=== Current status ==="
git status --short

if [ "$fixed_count" -eq 0 ]; then
    warn "No repositories were fixed."
    exit 0
fi

if $NO_COMMIT; then
    info "Skipping commit (--no-commit). Review the staged changes above."
    exit 0
fi

if ! confirm "Commit the changes?"; then
    info "Skipping commit."
    exit 0
fi

git commit -m "Fix nested repositories: removed $fixed_count nested .git folders"
success "Changes committed"

if $NO_PUSH; then
    info "Skipping push (--no-push)."
    exit 0
fi

if ! confirm "Push changes to remote?"; then
    info "Skipping push."
    exit 0
fi

if git push; then
    success "Changes pushed"
else
    error "Push failed. You may need to set an upstream or resolve conflicts."
    exit 1
fi

echo ""
success "Done!"
#!/usr/bin/env bash
#
# github_remove_nested.sh
# Finds and fixes nested Git repositories within the main repository,
# including gitlinks, .gitmodules entries, and nested .git files.
#

set -uo pipefail

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

Finds and removes nested .git folders, gitlink entries, and .gitmodules
entries inside the current Git repository.

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
    if $AUTO_YES; then return 0; fi
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
# Look for both .git directories AND .git files (worktrees / submodules).
declare -a NESTED_REPOS=()

while IFS= read -r gitpath; do
    dirpath=$(dirname "$gitpath")

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
done < <(find . \( -name ".git" -type d -o -name ".git" -type f \) 2>/dev/null | sort -u)

# ---------- Step 3b: Find gitlink entries in the index ----------
# Gitlinks have mode 160000 — that's the real "link to a repo" in the parent.
declare -a GITLINK_PATHS=()
while IFS= read -r line; do
    [ -z "$line" ] && continue
    mode=$(echo "$line" | awk '{print $1}')
    path=$(echo "$line" | awk '{print $4}')
    if [ "$mode" = "160000" ]; then
        GITLINK_PATHS+=("$path")
    fi
done < <(git ls-files --stage)

if [ ${#NESTED_REPOS[@]} -eq 0 ] && [ ${#GITLINK_PATHS[@]} -eq 0 ] && [ ! -f .gitmodules ]; then
    success "No nested repositories, gitlinks, or .gitmodules found. Nothing to do."
    exit 0
fi

# ---------- Step 4: Analysis & reporting ----------
if [ ${#NESTED_REPOS[@]} -gt 0 ]; then
    info "Found ${#NESTED_REPOS[@]} nested repo(s):"
fi

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

if [ ${#GITLINK_PATHS[@]} -gt 0 ]; then
    echo ""
    warn "Gitlink entries in index (mode 160000):"
    for p in "${GITLINK_PATHS[@]}"; do
        echo "  - $p"
    done
fi

if [ -f .gitmodules ]; then
    echo ""
    warn ".gitmodules file present — its entries will also be cleaned:"
    grep -E '^\s*(path|url)\s*=' .gitmodules || true
fi

echo ""
if ! confirm "Proceed with removing nested .git folders, gitlinks, and .gitmodules?"; then
    info "Aborted by user."
    exit 0
fi

if $DRY_RUN; then
    warn "Dry run — no changes will be made."
    exit 0
fi

# ---------- Step 5: Automatic cleanup ----------
fixed_count=0

# 5a. Remove gitlink entries from the index (this is what keeps the "link")
for p in "${GITLINK_PATHS[@]:-}"; do
    [ -z "$p" ] && continue
    if git rm --cached -r --ignore-unmatch "$p" > /dev/null 2>&1; then
        success "Removed gitlink from index: $p"
    fi
done

# 5b. Remove nested .git (dir or file) and .gitignore, then re-add
for dirpath in "${NESTED_REPOS[@]}"; do
    gitdir="$dirpath/.git"

    if [ -d "$gitdir" ]; then
        rm -rf "$gitdir"
    elif [ -f "$gitdir" ]; then
        rm -f "$gitdir"
    else
        warn "Skipping $dirpath (no .git found)"
        continue
    fi

    rm -f "$dirpath/.gitignore"

    # In case the nested dir was a gitlink, drop it from the index first,
    # then re-add the actual file contents.
    git rm --cached -r --ignore-unmatch "$dirpath" > /dev/null 2>&1 || true
    git add -A "$dirpath" > /dev/null 2>&1

    fixed_count=$((fixed_count + 1))
    success "Removed .git from $dirpath"
done

# 5c. Clean up .gitmodules if it still references removed paths
if [ -f .gitmodules ]; then
    if [ ${#GITLINK_PATHS[@]} -gt 0 ] || [ ${#NESTED_REPOS[@]} -gt 0 ]; then
        # If no submodule entries remain, delete the file; otherwise leave it.
        remaining=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
            | awk '{print $2}' \
            | while read -r sp; do
                [ -d "$sp/.git" ] || [ -f "$sp/.git" ] && echo "$sp"
              done)
        if [ -z "$remaining" ]; then
            git rm -f .gitmodules > /dev/null 2>&1 && success "Removed .gitmodules"
        else
            warn ".gitmodules still references active submodules — left in place"
        fi
    fi
fi

# ---------- Step 6: Commit & push ----------
echo ""
echo "=== Summary ==="
echo "Found ${#NESTED_REPOS[@]} nested repositories"
echo "Fixed $fixed_count nested repositories"

echo ""
echo "=== Current status ==="
git status --short

if $NO_COMMIT; then
    info "Skipping commit (--no-commit). Review the staged changes above."
    exit 0
fi

if ! confirm "Commit the changes?"; then
    info "Skipping commit."
    exit 0
fi

git commit -m "Fix nested repositories: removed $fixed_count nested .git folders and cleaned gitlinks"

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
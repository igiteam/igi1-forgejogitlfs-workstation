#!/bin/bash
# ===============================================================
# install_pytorch_macosx_intel.sh
#
# Installs PyTorch on Intel Macs. PyTorch dropped Intel macOS wheels
# on PyPI after 2.2.x, so this pins to the last working combo:
#   Python 3.12 + torch 2.2.2 + numpy<2
#
# WHAT THIS DOES NOT DO:
#   Make VoiceStudio work. VoiceStudio requires torch>=2.6, which
#   does not exist for Intel macOS. This script only installs the
#   last officially supported torch version for testing.
#
# Requirements:
#   - Intel Mac (x86_64)
#   - Homebrew (for pyenv)
#   - pyenv
# ===============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[x]${NC} $1" >&2; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# ---------------------------------------------------------------
# Verify we're on Intel macOS
# ---------------------------------------------------------------
ARCH="$(uname -m)"
OS="$(uname -s)"

[ "$OS" = "Darwin" ] || die "This script is for macOS only. Detected: $OS"
[ "$ARCH" = "x86_64" ] || die "This script is for Intel Macs (x86_64). Detected: $ARCH"
info "Confirmed: Intel Mac (x86_64)"

# ---------------------------------------------------------------
# Configuration (edit if needed)
# ---------------------------------------------------------------
PYTHON_VERSION="3.12.13"
TORCH_VERSION="2.2.2"
TORCHVISION_VERSION="0.17.2"
TORCHAUDIO_VERSION="2.2.2"
VENV_DIR="${VENV_DIR:-.venv}"

log "Target Python:   $PYTHON_VERSION"
log "Target torch:    $TORCH_VERSION"
log "Virtual env dir: $VENV_DIR"

# ---------------------------------------------------------------
# Check Homebrew
# ---------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew not found. Install it from https://brew.sh then re-run."
fi

# ---------------------------------------------------------------
# Ensure pyenv
# ---------------------------------------------------------------
if ! command -v pyenv >/dev/null 2>&1; then
    log "Installing pyenv via Homebrew..."
    brew install pyenv
else
    info "pyenv already installed: $(pyenv --version)"
fi

# ---------------------------------------------------------------
# Shell init for pyenv (zsh and bash)
# ---------------------------------------------------------------
setup_pyenv_shell() {
    local rc_file="$1"
    if [ -f "$rc_file" ] && ! grep -q 'pyenv init' "$rc_file"; then
        log "Adding pyenv init to $rc_file"
        {
            echo ''
            echo '# pyenv init (added by install_pytorch_macosx_intel.sh)'
            echo 'export PYENV_ROOT="$HOME/.pyenv"'
            echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
            echo 'eval "$(pyenv init -)"'
        } >> "$rc_file"
    fi
}

setup_pyenv_shell "$HOME/.zshrc"
setup_pyenv_shell "$HOME/.bashrc"

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true

# ---------------------------------------------------------------
# Install Python version
# ---------------------------------------------------------------
if pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
    info "Python $PYTHON_VERSION already installed via pyenv."
else
    log "Installing Python $PYTHON_VERSION via pyenv..."
    pyenv install "$PYTHON_VERSION"
fi

# Set global to this version
log "Setting global Python to $PYTHON_VERSION"
pyenv global "$PYTHON_VERSION"

# Verify
ACTIVE_PY="$(python --version 2>&1)"
info "Active Python: $ACTIVE_PY"

# ---------------------------------------------------------------
# Create virtual environment
# ---------------------------------------------------------------
if [ -d "$VENV_DIR" ]; then
    warn "$VENV_DIR already exists."
    read -p "Remove and recreate? (y/N): " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        rm -rf "$VENV_DIR"
    else
        info "Reusing existing $VENV_DIR"
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    log "Creating virtual environment at $VENV_DIR"
    python -m venv "$VENV_DIR"
fi

# Activate
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# ---------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------
log "Upgrading pip..."
pip install --upgrade pip

log "Installing numpy<2 (required by torch 2.2.2 on Intel)..."
pip install "numpy<2"

log "Installing torch==$TORCH_VERSION torchvision==$TORCHVISION_VERSION torchaudio==$TORCHAUDIO_VERSION"
pip install \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}"

# ---------------------------------------------------------------
# Verify
# ---------------------------------------------------------------
log "Verifying installation..."
python - <<'PYEOF'
import sys
try:
    import torch
    print(f"torch version: {torch.__version__}")
    print(f"Python: {sys.version}")
    print(f"MPS available: {torch.backends.mps.is_available()}")
    print(f"MPS built:     {torch.backends.mps.is_built()}")
    if torch.backends.mps.is_available():
        print("MPS backend is usable — GPU acceleration via Metal works.")
    else:
        print("MPS not available. CPU-only inference.")
except Exception as e:
    print(f"VERIFY FAILED: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   PyTorch installed for Intel macOS                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Python:  $PYTHON_VERSION (via pyenv)"
info "torch:   $TORCH_VERSION"
info "venv:    $(pwd)/$VENV_DIR"
echo ""
info "To activate this environment in a new shell:"
echo "    cd $(pwd)"
echo "    source $VENV_DIR/bin/activate"
echo ""
warn "REMINDER: VoiceStudio requires torch>=2.6. This installation"
warn "uses torch $TORCH_VERSION, the last version with official Intel"
warn "macOS wheels. VoiceStudio will still fail to install its"
warn "dependencies. See the README for alternatives."
echo ""
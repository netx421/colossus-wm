#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Config (edit if you want)
# ----------------------------
WLR_VER="${WLR_VER:-0.19.2}"
SFX_VER="${SFX_VER:-0.4.1}"
PREFIX="${PREFIX:-/usr}"
SYSCONFDIR="${SYSCONFDIR:-/etc}"
WORKDIR="${WORKDIR:-$HOME/src}"

# If you fork scenefx later, set SFX_REPO to your fork URL.
WLR_REPO="${WLR_REPO:-https://gitlab.freedesktop.org/wlroots/wlroots.git}"
SFX_REPO="${SFX_REPO:-https://github.com/wlrfx/scenefx.git}"
COLOSSUS_REPO="${COLOSSUS_REPO:-https://github.com/netx421/colossus-wm.git}"

say() { echo "[COLOSSUS-INSTALL] $*"; }
die() { echo "[COLOSSUS-INSTALL:ERR] $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# ----------------------------
# Preflight
# ----------------------------
need_cmd sudo
need_cmd git

if ! command -v pacman >/dev/null 2>&1; then
  die "This install.sh currently supports Arch Linux (pacman) only."
fi

say "Installing required dependencies (Arch)..."
sudo pacman -Sy --needed --noconfirm \
  base-devel \
  git \
  meson \
  ninja \
  pkgconf \
  cmake \
  wayland \
  wayland-protocols \
  libinput \
  libdrm \
  libxkbcommon \
  pixman \
  pcre2 \
  libdisplay-info \
  libliftoff \
  hwdata \
  seatd \
  xorg-xwayland \
  libxcb \
  xcb-util-wm

say "Enabling seatd + adding user to seat group..."
sudo systemctl enable --now seatd || true
sudo usermod -aG seat "$USER" || true

say "Build workspace: $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ----------------------------
# Build & install wlroots
# ----------------------------
say "Building wlroots v$WLR_VER..."
rm -rf wlroots
git clone -b "$WLR_VER" --depth=1 "$WLR_REPO" wlroots
cd wlroots
rm -rf build
meson setup build --prefix="$PREFIX"
ninja -C build
sudo ninja -C build install
sudo ldconfig || true
cd "$WORKDIR"

# ----------------------------
# Build & install scenefx
# ----------------------------
say "Building scenefx v$SFX_VER..."
rm -rf scenefx
git clone -b "$SFX_VER" --depth=1 "$SFX_REPO" scenefx
cd scenefx
rm -rf build
meson setup build --prefix="$PREFIX"
ninja -C build
sudo ninja -C build install
sudo ldconfig || true
cd "$WORKDIR"

# ----------------------------
# Build & install colossus-wm
# ----------------------------
say "Building colossus-wm..."
rm -rf colossus-wm
git clone --depth=1 "$COLOSSUS_REPO" colossus-wm
cd colossus-wm
rm -rf build
meson setup build --prefix="$PREFIX" --sysconfdir="$SYSCONFDIR"
ninja -C build
sudo ninja -C build install
sudo ldconfig || true

say "Install complete."

say "Verify binary:"
say "  type -a colossus"

say "IMPORTANT:"
say "  You must log out/in (or reboot) for seat group changes to apply."
say "Then start from TTY with:"
say "  colossus"

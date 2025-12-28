#!/usr/bin/env bash
set -euo pipefail

ROOT="${HOME}/src/colossus-stack"
WLR_VER="0.19.2"
SFX_VER="0.4.1"
COLOSSUS_REPO="https://github.com/netx421/colossus-wm.git"

echo "[COL] Using workdir: ${ROOT}"
mkdir -p "${ROOT}"
cd "${ROOT}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "[COL] Missing dependency: $1"; exit 1; }; }

echo "[COL] Checking build tools..."
for b in git meson ninja pkg-config; do need "$b"; done

echo "[COL] Installing runtime/build deps (Arch)..."
if command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm \
    base-devel git meson ninja pkgconf \
    wayland wayland-protocols \
    xorg-xwayland \
    libinput libxkbcommon \
    pcre2 \
    pixman libdrm \
    seatd \
    gcc
fi

echo "[COL] Building wlroots ${WLR_VER}..."
rm -rf wlroots
git clone -b "${WLR_VER}" --depth=1 https://gitlab.freedesktop.org/wlroots/wlroots.git
pushd wlroots >/dev/null
meson setup build --wipe --prefix=/usr --libdir=lib
ninja -C build
sudo ninja -C build install
popd >/dev/null

echo "[COL] Building scenefx ${SFX_VER}..."
rm -rf scenefx
git clone -b "${SFX_VER}" --depth=1 https://github.com/wlrfx/scenefx.git
pushd scenefx >/dev/null
meson setup build --wipe --prefix=/usr --libdir=lib
ninja -C build
sudo ninja -C build install
popd >/dev/null

echo "[COL] Building colossus-wm..."
rm -rf colossus-wm
git clone --depth=1 "${COLOSSUS_REPO}"
pushd colossus-wm >/dev/null
meson setup build --wipe --prefix=/usr --sysconfdir=/etc --libdir=lib
ninja -C build
sudo ninja -C build install
popd >/dev/null

echo "[COL] Refreshing linker cache..."
sudo ldconfig

echo "[COL] Installed binaries:"
command -v colossus || true
command -v colossus-wm || true
command -v mmsg || true

# If your meson.build still installs as 'colossus', this will validate it.
BIN="$(command -v colossus 2>/dev/null || true)"
if [[ -n "${BIN}" ]]; then
  echo "[COL] Checking shared libraries for ${BIN}..."
  if ldd "${BIN}" | grep -q "not found"; then
    echo "[COL] ERROR: Missing shared libraries:"
    ldd "${BIN}" | grep "not found" || true
    exit 1
  fi
  echo "[COL] OK: no missing libs."
fi

echo "[COL] Done."

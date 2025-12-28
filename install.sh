#!/usr/bin/env bash
set -euo pipefail

WLR_VER="${WLR_VER:-0.19.2}"
SFX_VER="${SFX_VER:-0.4.1}"

PREFIX="${PREFIX:-/usr}"
SYSCONFDIR="${SYSCONFDIR:-/etc}"
LIBDIR="${LIBDIR:-lib}"

WORKDIR_DEFAULT="${HOME}/src/colossus-stack"
WORKDIR="${WORKDIR:-$WORKDIR_DEFAULT}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"

say() { printf "\033[1;35m[COL]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[COL:ERR]\033[0m %s\n" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

ARCH_DEPS=(
  base-devel
  git
  meson
  ninja
  pkgconf
  seatd
  wayland
  wayland-protocols
  libinput
  libxkbcommon
  xorg-xwayland
  libdrm
  mesa
  pcre2
  pixman
  pipewire
  pipewire-pulse
  wireplumber
  waybar
  wlr-randr
  papirus-icon-theme
  ttf-jetbrains-mono-nerd
)

say "Repo: ${REPO_NAME}"
say "Workdir: ${WORKDIR}"
say "wlroots: ${WLR_VER}  scenefx: ${SFX_VER}"
say "prefix: ${PREFIX}  sysconfdir: ${SYSCONFDIR}  libdir: ${LIBDIR}"

need git
need meson
need ninja
need pkg-config

if command -v pacman >/dev/null 2>&1; then
  say "Arch detected — installing dependencies..."
  sudo pacman -Syu --noconfirm
  sudo pacman -S --needed --noconfirm "${ARCH_DEPS[@]}"
else
  die "This install.sh currently supports Arch (pacman) only."
fi

say "Enabling seatd (required for wlroots compositors)..."
sudo systemctl enable --now seatd >/dev/null 2>&1 || true
sudo usermod -aG seat "$USER" >/dev/null 2>&1 || true

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

build_meson_project() {
  local name="$1"
  local dir="$2"

  say "Building ${name}..."
  pushd "${dir}" >/dev/null

  meson setup build --wipe \
    --prefix="${PREFIX}" \
    --sysconfdir="${SYSCONFDIR}" \
    --libdir="${LIBDIR}"

  ninja -C build
  sudo ninja -C build install
  popd >/dev/null
}

say "Cloning & installing wlroots ${WLR_VER}..."
rm -rf wlroots
git clone -b "${WLR_VER}" --depth=1 https://gitlab.freedesktop.org/wlroots/wlroots.git
build_meson_project "wlroots" "wlroots"

say "Cloning & installing scenefx ${SFX_VER}..."
rm -rf scenefx
git clone -b "${SFX_VER}" --depth=1 https://github.com/wlrfx/scenefx.git
build_meson_project "scenefx" "scenefx"

say "Installing colossus-wm from your repo working tree..."
cd "${REPO_DIR}"
meson setup build --wipe \
  --prefix="${PREFIX}" \
  --sysconfdir="${SYSCONFDIR}" \
  --libdir="${LIBDIR}"

ninja -C build
sudo ninja -C build install

say "Refreshing linker cache..."
sudo ldconfig >/dev/null 2>&1 || true

say "Ensuring user config exists..."
mkdir -p "${HOME}/.config/colossus"
if [[ ! -f "${HOME}/.config/colossus/config.conf" ]]; then
  if [[ -f "${SYSCONFDIR}/colossus/config.conf" ]]; then
    cp "${SYSCONFDIR}/colossus/config.conf" "${HOME}/.config/colossus/config.conf"
    say "Copied default config to ~/.config/colossus/config.conf"
  else
    say "No ${SYSCONFDIR}/colossus/config.conf found (skipping copy)."
  fi
fi

say "Optionally installing GTK3 css if present in repo..."
if [[ -f "${REPO_DIR}/assets/gtk-3.0/gtk.css" ]]; then
  mkdir -p "${HOME}/.config/gtk-3.0"
  cp "${REPO_DIR}/assets/gtk-3.0/gtk.css" "${HOME}/.config/gtk-3.0/gtk.css"
  say "Installed ~/.config/gtk-3.0/gtk.css"
fi

say "Installed binaries:"
command -v colossus-wm >/dev/null 2>&1 && say "  $(command -v colossus-wm)" || true
command -v colossus >/dev/null 2>&1 && say "  $(command -v colossus)" || true
command -v mmsg >/dev/null 2>&1 && say "  $(command -v mmsg)" || true

BIN=""
if command -v colossus-wm >/dev/null 2>&1; then
  BIN="$(command -v colossus-wm)"
elif command -v colossus >/dev/null 2>&1; then
  BIN="$(command -v colossus)"
fi

if [[ -n "${BIN}" ]]; then
  say "Checking runtime linkage for: ${BIN}"
  if ldd "${BIN}" | grep -q "not found"; then
    echo
    ldd "${BIN}" | grep "not found" || true
    echo
    die "Missing shared libraries detected. Fix deps/prefix mismatch before running."
  fi
  say "OK: no missing libs."
else
  die "No installed compositor binary found (colossus-wm/colossus). Check meson.build target name."
fi

say "Done."
say "Next:"
say "  - Edit: ~/.config/colossus/config.conf"
say "  - Set 1080p: add monitorrule=HDMI-A-1,0.55,1,tile,0,1,0,0,1920,1080,60 (use wlr-randr for name)"
say "  - Autostart waybar: exec-once=waybar  (or exec-once=~/.config/colossus/autostart.sh)"

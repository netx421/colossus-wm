#!/usr/bin/env bash
set -euo pipefail

WLR_VER="${WLR_VER:-0.19.2}"
SFX_VER="${SFX_VER:-0.4.1}"

PREFIX="${PREFIX:-/usr}"
SYSCONFDIR="${SYSCONFDIR:-/etc}"
LIBDIR="${LIBDIR:-lib}"

WORKDIR="${WORKDIR:-$HOME/src/colossus-stack}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf "\033[1;35m[COL]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[COL:ERR]\033[0m %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || return 1; }

is_arch() { command -v pacman >/dev/null 2>&1; }

require_arch() {
  is_arch || die "This installer currently supports Arch Linux (pacman) only."
}

install_deps_arch() {
  say "Arch detected — installing ALL dependencies…"
  sudo pacman -Syu --noconfirm

  # Full build toolchain + meson/ninja/pkg-config
  # wlroots build surface + runtime (Wayland/DRM/EGL/GBM/etc.)
  # Xwayland support + common libs used by wlroots-based compositors
  # waybar + wlr-randr + fonts/icons for a usable session
  sudo pacman -S --needed --noconfirm \
    base-devel git \
    meson ninja pkgconf cmake \
    python \
    seatd \
    wayland wayland-protocols \
    libinput libxkbcommon \
    libdrm mesa \
    egl-wayland \
    pixman \
    pcre2 \
    xorg-xwayland xcb-util-wm xcb-util-renderutil \
    libxcb xcb-util xcb-util-image xcb-util-keysyms xcb-util-xrm \
    freetype2 fontconfig \
    cairo pango gdk-pixbuf2 glib2 \
    polkit \
    pipewire pipewire-pulse wireplumber \
    waybar \
    wlr-randr \
    ttf-jetbrains-mono-nerd \
    papirus-icon-theme

  # Optional but often helpful on fresh minimal installs
  sudo pacman -S --needed --noconfirm \
    man-db man-pages \
    xdg-user-dirs xdg-utils \
    wl-clipboard \
    grim slurp \
    foot alacritty \
    openssh

  say "Dependencies installed."
}

enable_seatd() {
  say "Enabling seatd (required for wlroots compositors)…"
  sudo systemctl enable --now seatd || true
  sudo usermod -aG seat "$USER" || true
}

build_meson_project() {
  local name="$1"
  local dir="$2"

  say "Building ${name}…"
  pushd "$dir" >/dev/null

  meson setup build --wipe \
    --prefix="${PREFIX}" \
    --sysconfdir="${SYSCONFDIR}" \
    --libdir="${LIBDIR}"

  ninja -C build
  sudo ninja -C build install

  popd >/dev/null
}

clone_or_refresh() {
  local dir="$1"
  local url="$2"
  local branch="$3"

  rm -rf "$dir"
  if [[ -n "$branch" ]]; then
    git clone -b "$branch" --depth=1 "$url" "$dir"
  else
    git clone --depth=1 "$url" "$dir"
  fi
}

post_install_checks() {
  say "Refreshing linker cache…"
  sudo ldconfig || true

  say "Verifying pkg-config:"
  pkg-config --modversion wlroots-0.19 >/dev/null 2>&1 || true
  pkg-config --modversion scenefx-0.4 >/dev/null 2>&1 || true

  local bin=""
  if command -v colossus-wm >/dev/null 2>&1; then
    bin="$(command -v colossus-wm)"
  elif command -v colossus >/dev/null 2>&1; then
    bin="$(command -v colossus)"
  fi

  [[ -n "$bin" ]] || die "No compositor binary found in PATH (colossus-wm or colossus)."

  say "Checking runtime linkage for: $bin"
  if ldd "$bin" | grep -q "not found"; then
    echo
    ldd "$bin" | grep "not found" || true
    echo
    die "Missing shared libraries. Fix deps/version mismatch before running."
  fi
  say "OK: no missing libs."
}

install_user_config_and_theme() {
  say "Ensuring user config exists…"
  mkdir -p "$HOME/.config/colossus"
  if [[ ! -f "$HOME/.config/colossus/config.conf" ]]; then
    if [[ -f "${SYSCONFDIR}/colossus/config.conf" ]]; then
      cp "${SYSCONFDIR}/colossus/config.conf" "$HOME/.config/colossus/config.conf"
      say "Copied default config to ~/.config/colossus/config.conf"
    fi
  fi

  if [[ -f "${REPO_DIR}/assets/gtk-3.0/gtk.css" ]]; then
    mkdir -p "$HOME/.config/gtk-3.0"
    cp "${REPO_DIR}/assets/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
    say "Installed ~/.config/gtk-3.0/gtk.css"
  fi
}

main() {
  require_arch
  install_deps_arch

  # Re-check that core build tools now exist
  need_cmd meson || die "meson still missing after dependency install"
  need_cmd ninja || die "ninja still missing after dependency install"
  need_cmd pkg-config || die "pkg-config still missing after dependency install"
  need_cmd git || die "git still missing after dependency install"

  enable_seatd

  say "Workdir: ${WORKDIR}"
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"

  say "Cloning & installing wlroots ${WLR_VER}…"
  clone_or_refresh "wlroots" "https://gitlab.freedesktop.org/wlroots/wlroots.git" "${WLR_VER}"
  build_meson_project "wlroots" "wlroots"

  say "Cloning & installing scenefx ${SFX_VER}…"
  clone_or_refresh "scenefx" "https://github.com/wlrfx/scenefx.git" "${SFX_VER}"
  build_meson_project "scenefx" "scenefx"

  say "Installing colossus-wm from repo working tree…"
  cd "${REPO_DIR}"
  meson setup build --wipe \
    --prefix="${PREFIX}" \
    --sysconfdir="${SYSCONFDIR}" \
    --libdir="${LIBDIR}"
  ninja -C build
  sudo ninja -C build install

  install_user_config_and_theme
  post_install_checks

  say "Done."
  say "IMPORTANT: log out and back in (seat group change), then start:"
  say "  colossus-wm   (or colossus if you kept that name)"
}

main "$@"

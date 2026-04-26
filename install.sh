#!/usr/bin/env bash
# install.sh — Introduction installer one-liner.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/rsrs123/introduction/main/install.sh | bash
#
# Detecta tu OS + arquitectura, descarga el binario correcto del último
# GitHub Release, lo extrae a la ubicación correcta del sistema, y lanza
# Introduction la primera vez.

set -euo pipefail

REPO="rsrs123/introduction-binaries"
APP_NAME="Introduction"

# Colores
if [ -t 1 ]; then
  GREEN=$(printf '\033[32m')
  YELLOW=$(printf '\033[33m')
  CYAN=$(printf '\033[36m')
  BOLD=$(printf '\033[1m')
  RESET=$(printf '\033[0m')
else
  GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
fi

say() { printf "%s%s%s\n" "$1" "$2" "$RESET"; }
err() { say "$YELLOW" "❌ $1" >&2; exit 1; }
ok()  { say "$GREEN"  "✓ $1"; }

# ──────────────────────────────────────────────────────────────────────────────
# 1) Detectar OS + arch
# ──────────────────────────────────────────────────────────────────────────────
OS=""
ARCH=""

case "$(uname -s)" in
  Darwin)  OS="darwin" ;;
  Linux)   OS="linux"  ;;
  MINGW*|MSYS*|CYGWIN*) OS="win32" ;;
  *) err "OS no soportado: $(uname -s)" ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="x64"   ;;
  *) err "Arquitectura no soportada: $(uname -m)" ;;
esac

# Combo OS+ARCH soportado?
ASSET_NAME=""
case "$OS-$ARCH" in
  darwin-arm64) ASSET_NAME="Introduction-darwin-arm64.zip" ;;
  darwin-x64)   ASSET_NAME="Introduction-darwin-x64.zip"   ;;
  linux-x64)    ASSET_NAME="Introduction-linux-x64.tar.gz" ;;
  win32-x64)    ASSET_NAME="Introduction-win32-x64.zip"    ;;
  *) err "Combinación $OS/$ARCH no soportada todavía" ;;
esac

say "$CYAN$BOLD" "Introduction installer"
echo "  OS:    $OS"
echo "  Arch:  $ARCH"
echo "  Asset: $ASSET_NAME"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 2) Buscar último Release público
# ──────────────────────────────────────────────────────────────────────────────
say "$CYAN" "→ Buscando último release público de $REPO..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null) \
  || err "No se pudo obtener el último release. Verifica conexión."

TAG=$(echo "$RELEASE_JSON" | grep -E '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
[ -z "$TAG" ] && err "No hay releases publicados todavía"

ASSET_URL=$(echo "$RELEASE_JSON" | grep -E '"browser_download_url"' | grep -F "$ASSET_NAME" \
  | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
[ -z "$ASSET_URL" ] && err "Asset $ASSET_NAME no encontrado en release $TAG"

ok "Release: $TAG"
echo "  URL:   $ASSET_URL"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 3) Descargar
# ──────────────────────────────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

DOWNLOAD_PATH="$TMP/$ASSET_NAME"
say "$CYAN" "→ Descargando ~160 MB..."
if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar -o "$DOWNLOAD_PATH" "$ASSET_URL"
elif command -v wget >/dev/null 2>&1; then
  wget --show-progress -O "$DOWNLOAD_PATH" "$ASSET_URL"
else
  err "Necesitas curl o wget instalado"
fi
ok "Descargado a $DOWNLOAD_PATH"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 4) Extraer + instalar según OS
# ──────────────────────────────────────────────────────────────────────────────
case "$OS" in
  darwin)
    say "$CYAN" "→ Extrayendo..."
    unzip -q "$DOWNLOAD_PATH" -d "$TMP/extracted"
    APP_PATH=$(find "$TMP/extracted" -maxdepth 2 -name "*.app" -type d | head -1)
    [ -z "$APP_PATH" ] && err ".app no encontrado en el zip"

    INSTALL_DIR="/Applications"
    APP_BASENAME=$(basename "$APP_PATH")
    DEST="$INSTALL_DIR/$APP_BASENAME"

    if [ -d "$DEST" ]; then
      say "$YELLOW" "  → Versión anterior detectada — actualizando $DEST"
      # Cierra app si está corriendo (silencioso si no)
      osascript -e 'quit app "Introduction"' 2>/dev/null || true
      sleep 1
      rm -rf "$DEST"
    fi

    say "$CYAN" "→ Instalando en $INSTALL_DIR/"
    cp -R "$APP_PATH" "$DEST"

    # Quitar Gatekeeper quarantine (binario unsigned)
    say "$CYAN" "→ Quitando Gatekeeper quarantine (binario unsigned)..."
    xattr -cr "$DEST" 2>/dev/null || true

    ok "Instalado en $DEST"
    echo ""
    say "$GREEN$BOLD" "🎯 Introduction instalado correctamente."
    echo ""
    echo "  Lanzar:           open '$DEST'"
    echo "  Spotlight:        Cmd+Space → escribe 'Introduction'"
    echo "  CLI desde shell:  '$DEST/Contents/Resources/app/bin/codium' --help"
    echo ""

    # Lanza la app
    if [ -t 0 ]; then
      printf "${CYAN}¿Lanzar Introduction ahora? [Y/n] ${RESET}"
      read -r LAUNCH || LAUNCH="y"
    else
      LAUNCH="y"
    fi
    if [[ "$LAUNCH" =~ ^[Yy]?$ ]]; then
      open "$DEST"
    fi
    ;;

  linux)
    say "$CYAN" "→ Extrayendo..."
    INSTALL_DIR="$HOME/.local/share/introduction"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/Introduction-linux-x64"
    tar -xzf "$DOWNLOAD_PATH" -C "$INSTALL_DIR"

    BIN="$INSTALL_DIR/Introduction-linux-x64/bin/introduction"
    chmod +x "$BIN"

    # Symlink en ~/.local/bin/ si está en el PATH
    if [ -d "$HOME/.local/bin" ] && echo "$PATH" | grep -qF "$HOME/.local/bin"; then
      ln -sf "$BIN" "$HOME/.local/bin/introduction"
      ok "Symlink creado: ~/.local/bin/introduction"
    fi

    ok "Instalado en $INSTALL_DIR"
    echo ""
    say "$GREEN$BOLD" "🎯 Introduction instalado correctamente."
    echo ""
    echo "  Lanzar:  $BIN"
    if [ -L "$HOME/.local/bin/introduction" ]; then
      echo "  O:       introduction"
    fi
    echo ""

    if [ -t 0 ]; then
      printf "${CYAN}¿Lanzar Introduction ahora? [Y/n] ${RESET}"
      read -r LAUNCH || LAUNCH="y"
    else
      LAUNCH="n"
    fi
    if [[ "$LAUNCH" =~ ^[Yy]?$ ]]; then
      "$BIN" &
    fi
    ;;

  win32)
    err "Para Windows: descarga $ASSET_URL manualmente y descomprime, luego doble-click Introduction.exe."
    ;;
esac

echo ""
say "$GREEN" "Visita https://getintroduction.com/docs para empezar"

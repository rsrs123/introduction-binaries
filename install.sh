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

REPO="rsrs123/introduction"
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

    # Aplicar bundle de assets visuales Introduction.
    # VSCodium build sobrescribe nuestros assets durante prepare_vscode.sh.
    # Workaround: descargamos el bundle (introduction-assets.tar.gz) del Release
    # y lo aplicamos en las rutas correctas del .app post-install.
    say "$CYAN" "→ Aplicando bundle de assets Introduction (icns + letterpress + code-icon)..."
    ASSETS_URL="https://github.com/$REPO/releases/download/$TAG/introduction-assets.tar.gz"
    if curl -fsSL -o "$TMP/assets.tar.gz" "$ASSETS_URL" 2>/dev/null && [ -s "$TMP/assets.tar.gz" ]; then
      mkdir -p "$TMP/assets"
      tar -xzf "$TMP/assets.tar.gz" -C "$TMP/assets"

      RES_DIR="$DEST/Contents/Resources"
      MEDIA_DIR="$RES_DIR/app/out/media"
      AGENT_DIR="$RES_DIR/app/out/vs/sessions/contrib/chat/browser/media"

      # Icon principal del .app
      [ -f "$TMP/assets/introduction.icns" ] && \
        cp "$TMP/assets/introduction.icns" "$RES_DIR/Introduction.icns"

      # Letterpress (background gris cuando no hay folder)
      for variant in dark light hcDark hcLight; do
        SRC="$TMP/assets/letterpress-${variant}.svg"
        DEST_F="$MEDIA_DIR/letterpress-${variant}.svg"
        [ -f "$SRC" ] && [ -d "$MEDIA_DIR" ] && cp "$SRC" "$DEST_F"
      done

      # code-icon.svg (tab Welcome + título)
      [ -f "$TMP/assets/code-icon.svg" ] && [ -d "$MEDIA_DIR" ] && \
        cp "$TMP/assets/code-icon.svg" "$MEDIA_DIR/code-icon.svg"

      # code-icon-agent-sessions*.svg (chat panels)
      if [ -d "$AGENT_DIR" ]; then
        for v in "" "-exploration" "-insider" "-stable"; do
          SRC="$TMP/assets/code-icon-agent-sessions${v}.svg"
          [ -f "$SRC" ] && cp "$SRC" "$AGENT_DIR/code-icon-agent-sessions${v}.svg"
        done
      fi

      ok "Bundle de assets aplicado (icns + 4 letterpress + 5 code-icon)"

    # Instalar .vsix actualizado de int-ai-extension (con wizard Cursor migration)
    VSIX_URL="https://github.com/$REPO/releases/download/$TAG/int-ai-extension-0.2.2.vsix"
    INTRO_CLI="$DEST/Contents/Resources/app/bin/introduction"
    if curl -fsSL -o "$TMP/int-ext.vsix" "$VSIX_URL" 2>/dev/null && [ -x "$INTRO_CLI" ]; then
      say "$CYAN" "→ Instalando int-ai-extension v0.2.2..."
      if "$INTRO_CLI" --install-extension "$TMP/int-ext.vsix" --force; then
        ok "int-ai-extension v0.2.2 instalada (wizard refinado + Qdrant suppress persistente)"
      else
        warn "Fallo instalando .vsix — el wizard se ejecutará desde la versión built-in"
      fi
    else
      warn ".vsix download fallo o CLI no encontrado en $INTRO_CLI"
    fi

      # Limpiar cache iconos macOS (sudo opcional)
      if [ -t 0 ] && command -v sudo >/dev/null 2>&1; then
        say "$CYAN" "→ Limpiando icon cache de macOS (requiere sudo)..."
        if sudo -n true 2>/dev/null || sudo -v; then
          sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
          killall Dock Finder 2>/dev/null || true
          ok "Icon cache limpiado — Dock + Finder reiniciados"
        fi
      fi
    else
      say "$YELLOW" "  ⚠ No se pudo descargar bundle de assets (icons quedarán originales)"
    fi

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

    APP_ROOT="$INSTALL_DIR/Introduction-linux-x64"
    BIN="$APP_ROOT/bin/introduction"
    chmod +x "$BIN"

    # Aplicar bundle de assets visuales (mismo workaround que macOS).
    say "$CYAN" "→ Aplicando bundle de assets Introduction..."
    ASSETS_URL="https://github.com/$REPO/releases/download/$TAG/introduction-assets.tar.gz"
    if curl -fsSL -o "$TMP/assets.tar.gz" "$ASSETS_URL" 2>/dev/null && [ -s "$TMP/assets.tar.gz" ]; then
      mkdir -p "$TMP/assets"
      tar -xzf "$TMP/assets.tar.gz" -C "$TMP/assets"

      MEDIA_DIR="$APP_ROOT/resources/app/out/media"
      AGENT_DIR="$APP_ROOT/resources/app/out/vs/sessions/contrib/chat/browser/media"

      [ -d "$MEDIA_DIR" ] && {
        for variant in dark light hcDark hcLight; do
          cp "$TMP/assets/letterpress-${variant}.svg" "$MEDIA_DIR/letterpress-${variant}.svg" 2>/dev/null || true
        done
        cp "$TMP/assets/code-icon.svg" "$MEDIA_DIR/code-icon.svg" 2>/dev/null || true
      }
      [ -d "$AGENT_DIR" ] && {
        for v in "" "-exploration" "-insider" "-stable"; do
          cp "$TMP/assets/code-icon-agent-sessions${v}.svg" "$AGENT_DIR/code-icon-agent-sessions${v}.svg" 2>/dev/null || true
        done
      }
      # Icon Linux: code.png en .desktop entry + en resources
      LINUX_RES="$APP_ROOT/resources/linux"
      [ -d "$LINUX_RES" ] && cp "$TMP/assets/code.png" "$LINUX_RES/code.png" 2>/dev/null || true

      ok "Bundle de assets aplicado"
    fi

    # Instalar .vsix actualizado (Linux)
    VSIX_URL="https://github.com/$REPO/releases/download/$TAG/int-ai-extension-0.2.2.vsix"
    if curl -fsSL -o "$TMP/int-ext.vsix" "$VSIX_URL" 2>/dev/null && [ -x "$BIN" ]; then
      "$BIN" --install-extension "$TMP/int-ext.vsix" --force >/dev/null 2>&1 \
        && ok "int-ai-extension v0.2.2 instalada (wizard refinado + Qdrant suppress persistente)"
    fi

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

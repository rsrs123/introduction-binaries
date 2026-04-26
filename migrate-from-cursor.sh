#!/usr/bin/env bash
# migrate-from-cursor.sh — Migración Cursor → Introduction (macOS / Linux).
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/rsrs123/introduction-binaries/main/migrate-from-cursor.sh | bash
#
# Filosofía:
#   - NUNCA sobrescribe carpetas originales (Cursor + proyectos quedan intactos)
#   - Duplica proyectos con sufijo -introduction
#   - Selección interactiva (proyectos + extensions)
#   - Verifica cada extension instalada

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Colores
# ──────────────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  G=$(printf '\033[32m'); Y=$(printf '\033[33m'); C=$(printf '\033[36m')
  R=$(printf '\033[31m'); B=$(printf '\033[1m');   X=$(printf '\033[0m')
else
  G="" Y="" C="" R="" B="" X=""
fi
say()  { printf "%s%s%s\n" "$1" "$2" "$X"; }
ok()   { say "$G"  "✓ $1"; }
warn() { say "$Y"  "⚠ $1"; }
err()  { say "$R"  "✗ $1" >&2; exit 1; }
hr()   { say "$C"  "────────────────────────────────────────"; }

# ──────────────────────────────────────────────────────────────────────────────
# 1) Detectar Cursor + Introduction
# ──────────────────────────────────────────────────────────────────────────────
say "$C$B" "Cursor → Introduction migration"
hr
echo ""

case "$(uname -s)" in
  Darwin)
    CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
    CURSOR_EXTS="$HOME/.cursor/extensions"
    INTRO_USER="$HOME/Library/Application Support/Introduction/User"
    INTRO_BIN_CANDIDATES=(
      "/Applications/Introduction.app/Contents/Resources/app/bin/codium"
      "/Applications/Introduction.app/Contents/Resources/app/bin/code"
    )
    ;;
  Linux)
    CURSOR_USER="$HOME/.config/Cursor/User"
    CURSOR_EXTS="$HOME/.cursor/extensions"
    INTRO_USER="$HOME/.config/Introduction/User"
    INTRO_BIN_CANDIDATES=(
      "$HOME/.local/share/introduction/Introduction-linux-x64/bin/introduction"
      "$HOME/.local/bin/introduction"
    )
    ;;
  *)
    err "OS no soportado en este script. Usa migrate-from-cursor.ps1 en Windows."
    ;;
esac

# Verificar Cursor instalado
if [ ! -d "$CURSOR_USER" ]; then
  err "Cursor no encontrado en $CURSOR_USER. ¿Está instalado?"
fi
ok "Cursor encontrado: $CURSOR_USER"

# Detectar binario Introduction
INTRO_BIN=""
for candidate in "${INTRO_BIN_CANDIDATES[@]}"; do
  if [ -x "$candidate" ]; then INTRO_BIN="$candidate"; break; fi
done
if [ -z "$INTRO_BIN" ]; then
  warn "Introduction no encontrada. Las extensions no se podrán instalar."
  warn "Instálala primero: curl -fsSL https://raw.githubusercontent.com/rsrs123/introduction-binaries/main/install.sh | bash"
  printf "${Y}¿Continuar solo con copia de settings y proyectos? [y/N] ${X}"
  read -r CONT < /dev/tty
  if [[ ! "$CONT" =~ ^[Yy]$ ]]; then exit 0; fi
fi
[ -n "$INTRO_BIN" ] && ok "Introduction binary: $INTRO_BIN"

# Asegurar User dir de Introduction
mkdir -p "$INTRO_USER"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 2) STEP 1 — Migrar settings + keybindings + snippets globales
# ──────────────────────────────────────────────────────────────────────────────
say "$C$B" "[1/4] Settings globales (settings.json, keybindings.json, snippets)"
hr

printf "${C}¿Migrar settings.json + keybindings.json + snippets/ de Cursor? [Y/n] ${X}"
read -r DO_GLOBAL < /dev/tty
DO_GLOBAL=${DO_GLOBAL:-y}

if [[ "$DO_GLOBAL" =~ ^[Yy]$ ]]; then
  for f in settings.json keybindings.json; do
    if [ -f "$CURSOR_USER/$f" ]; then
      if [ -f "$INTRO_USER/$f" ]; then
        cp "$INTRO_USER/$f" "$INTRO_USER/${f}.backup-$(date +%s)"
        warn "Backup previo: $INTRO_USER/${f}.backup-*"
      fi
      cp "$CURSOR_USER/$f" "$INTRO_USER/$f"
      ok "$f migrado"
    fi
  done
  if [ -d "$CURSOR_USER/snippets" ]; then
    mkdir -p "$INTRO_USER/snippets"
    cp -R "$CURSOR_USER/snippets/." "$INTRO_USER/snippets/"
    ok "snippets/ migrados"
  fi
fi
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 3) STEP 2 — Detectar proyectos Cursor + multi-select
# ──────────────────────────────────────────────────────────────────────────────
say "$C$B" "[2/4] Proyectos Cursor"
hr

# Recent folders del workspace storage de Cursor (sqlite, leemos como texto)
# Más simple: scan ~/Projects/, ~/Code/, ~/repos/, ~/Documents/ buscando .cursor/
echo "→ Escaneando carpetas comunes por proyectos con .cursor/ ..."
SEARCH_DIRS=(
  "$HOME/Projects"
  "$HOME/projects"
  "$HOME/Code"
  "$HOME/code"
  "$HOME/repos"
  "$HOME/Repos"
  "$HOME/Documents/Projects"
  "$HOME/Documents/Code"
  "$HOME/Desktop"
  "$HOME/Developer"
  "$HOME/dev"
  "$HOME/workspace"
)

# Permitir al user añadir más
printf "${C}¿Buscar también en otra carpeta raíz? (vacío para skip): ${X}"
read -r EXTRA_DIR < /dev/tty
[ -n "$EXTRA_DIR" ] && SEARCH_DIRS+=("$EXTRA_DIR")

# Find proyectos (max-depth 3 para ser rápido)
PROJECTS=()
for sdir in "${SEARCH_DIRS[@]}"; do
  if [ -d "$sdir" ]; then
    while IFS= read -r -d '' cdir; do
      proj=$(dirname "$cdir")
      PROJECTS+=("$proj")
    done < <(find "$sdir" -maxdepth 3 -type d -name ".cursor" -print0 2>/dev/null)
  fi
done

if [ ${#PROJECTS[@]} -eq 0 ]; then
  warn "No se encontraron proyectos con .cursor/. Skip step 2."
else
  echo ""
  echo "Encontrados ${#PROJECTS[@]} proyectos:"
  for i in "${!PROJECTS[@]}"; do
    printf "  ${B}%2d)${X} %s\n" $((i+1)) "${PROJECTS[$i]}"
  done
  echo ""
  printf "${C}Selecciona qué proyectos migrar (ej: '1 3 5' / 'all' / 'none'): ${X}"
  read -r SELECTION < /dev/tty

  SELECTED=()
  if [ "$SELECTION" = "all" ]; then
    SELECTED=("${PROJECTS[@]}")
  elif [ "$SELECTION" = "none" ] || [ -z "$SELECTION" ]; then
    SELECTED=()
  else
    for n in $SELECTION; do
      if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#PROJECTS[@]} ]; then
        SELECTED+=("${PROJECTS[$((n-1))]}")
      fi
    done
  fi

  if [ ${#SELECTED[@]} -gt 0 ]; then
    echo ""
    printf "${C}Carpeta destino para las copias [default: ~/Introduction-Workspace]: ${X}"
    read -r DEST_ROOT < /dev/tty
    DEST_ROOT="${DEST_ROOT:-$HOME/Introduction-Workspace}"
    mkdir -p "$DEST_ROOT"

    for proj in "${SELECTED[@]}"; do
      name=$(basename "$proj")
      DEST="$DEST_ROOT/$name"

      if [ -e "$DEST" ]; then
        warn "$DEST ya existe — skip (no sobrescribimos)"
        continue
      fi

      echo "  → Copiando $name → $DEST..."
      # Copia respetando .gitignore patterns comunes (no node_modules, etc)
      if command -v rsync >/dev/null 2>&1; then
        rsync -a \
          --exclude='node_modules' --exclude='.git' \
          --exclude='dist' --exclude='build' --exclude='.next' \
          --exclude='.turbo' --exclude='.venv' --exclude='__pycache__' \
          "$proj/" "$DEST/"
      else
        cp -R "$proj/" "$DEST/"
      fi

      # Renombra .cursor/ → .introduction/ en la copia (mantiene .cursor/ original en source)
      if [ -d "$DEST/.cursor" ]; then
        mv "$DEST/.cursor" "$DEST/.introduction"
        ok "  $name: .cursor/ → .introduction/"
      fi
      ok "Copiado: $DEST"
    done
  fi
fi
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 4) STEP 3 — Extensions de Cursor
# ──────────────────────────────────────────────────────────────────────────────
say "$C$B" "[3/4] Extensions"
hr

if [ -z "$INTRO_BIN" ]; then
  warn "Introduction no encontrada — skip extensions."
elif [ ! -d "$CURSOR_EXTS" ]; then
  warn "$CURSOR_EXTS no existe — Cursor sin extensions instaladas?"
else
  # Lista extensions de Cursor: cada subcarpeta es publisher.name-version
  EXTS=()
  while IFS= read -r ext_dir; do
    name=$(basename "$ext_dir")
    # Extrae publisher.name (sin -version final)
    id=$(echo "$name" | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+.*$//')
    [ -n "$id" ] && [[ "$id" == *.* ]] && EXTS+=("$id")
  done < <(find "$CURSOR_EXTS" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

  # Dedup
  EXTS=($(printf "%s\n" "${EXTS[@]}" | sort -u))

  if [ ${#EXTS[@]} -eq 0 ]; then
    warn "No se detectaron extensions"
  else
    echo "Encontradas ${#EXTS[@]} extensions en Cursor:"
    for i in "${!EXTS[@]}"; do
      printf "  ${B}%2d)${X} %s\n" $((i+1)) "${EXTS[$i]}"
    done
    echo ""
    echo "Opciones:"
    echo "  ${B}all${X}     — instalar TODAS automáticamente"
    echo "  ${B}none${X}    — skip"
    echo "  ${B}1 3 5${X}   — instalar solo las seleccionadas"
    printf "${C}Tu elección: ${X}"
    read -r EXT_SEL < /dev/tty

    EXT_SELECTED=()
    if [ "$EXT_SEL" = "all" ]; then
      EXT_SELECTED=("${EXTS[@]}")
    elif [ "$EXT_SEL" = "none" ] || [ -z "$EXT_SEL" ]; then
      EXT_SELECTED=()
    else
      for n in $EXT_SEL; do
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#EXTS[@]} ]; then
          EXT_SELECTED+=("${EXTS[$((n-1))]}")
        fi
      done
    fi

    if [ ${#EXT_SELECTED[@]} -gt 0 ]; then
      echo ""
      echo "→ Instalando ${#EXT_SELECTED[@]} extensions en Introduction..."
      INSTALLED=0; FAILED=0; FAILED_LIST=()
      for ext in "${EXT_SELECTED[@]}"; do
        printf "  → %-50s " "$ext"
        if "$INTRO_BIN" --install-extension "$ext" --force >/dev/null 2>&1; then
          printf "${G}OK${X}\n"
          INSTALLED=$((INSTALLED+1))
        else
          printf "${R}FAIL${X}\n"
          FAILED=$((FAILED+1))
          FAILED_LIST+=("$ext")
        fi
      done
      echo ""
      ok "Instaladas: $INSTALLED / ${#EXT_SELECTED[@]}"
      if [ $FAILED -gt 0 ]; then
        warn "Fallaron $FAILED:"
        for f in "${FAILED_LIST[@]}"; do echo "    - $f"; done
        warn "(Probable: no disponibles en Open VSX. Instalar manualmente desde marketplace)"
      fi

      # Verificación: re-list y comparar
      echo ""
      echo "→ Verificando instalación..."
      INSTALLED_NOW=$("$INTRO_BIN" --list-extensions 2>/dev/null | wc -l | tr -d ' ')
      ok "Introduction tiene ahora $INSTALLED_NOW extensions instaladas"
    fi
  fi
fi
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 5) STEP 4 — Resumen final
# ──────────────────────────────────────────────────────────────────────────────
say "$C$B" "[4/4] Resumen"
hr
echo ""
say "$G$B" "🎯 Migración completada"
echo ""
echo "  Settings:    ${INTRO_USER}"
echo "  Proyectos:   ${DEST_ROOT:-(no migrados)}"
echo "  Extensions:  ${INSTALLED:-0} instaladas"
echo ""
echo "Próximos pasos:"
echo "  1) Abre Introduction"
echo "  2) File → Open Folder → ${DEST_ROOT:-tu-proyecto-migrado}"
echo "  3) Ctrl+Shift+P → 'Introduction: Choose Your Plan' → Community"
echo "  4) Ctrl+Shift+P → 'Introduction: Configure AI Providers' → tu Groq key"
echo ""
say "$C" "Tus proyectos originales en Cursor NO fueron tocados. Quedan intactos."

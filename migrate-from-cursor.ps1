#!/usr/bin/env pwsh
# migrate-from-cursor.ps1 — Migración Cursor → Introduction (Windows).
#
# Uso (PowerShell):
#   iwr -useb https://raw.githubusercontent.com/rsrs123/introduction-binaries/main/migrate-from-cursor.ps1 | iex
#
# Filosofía:
#   - NUNCA sobrescribe carpetas originales
#   - Duplica proyectos a la carpeta destino que elijas
#   - Selección interactiva (proyectos + extensions)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}
$ProgressPreference = 'Continue'

function Say   { param($Color, $Msg) Write-Host $Msg -ForegroundColor $Color }
function OK    { param($Msg) Say Green   "✓ $Msg" }
function Warn  { param($Msg) Say Yellow  "⚠ $Msg" }
function Step  { param($Msg) Say Cyan    "→ $Msg" }
function Hr    { Say Cyan "────────────────────────────────────────" }

# ──────────────────────────────────────────────────────────────────────────────
# 1) Detectar Cursor + Introduction
# ──────────────────────────────────────────────────────────────────────────────
Say Cyan "Cursor → Introduction migration (Windows)"
Hr
Write-Host ""

$CURSOR_USER = Join-Path $env:APPDATA "Cursor\User"
$CURSOR_EXTS = Join-Path $env:USERPROFILE ".cursor\extensions"
$INTRO_USER  = Join-Path $env:APPDATA "Introduction\User"

if (-not (Test-Path $CURSOR_USER)) {
  Say Red "✗ Cursor no encontrado en $CURSOR_USER"
  exit 1
}
OK "Cursor: $CURSOR_USER"

# Detectar binario Introduction
$INTRO_CANDIDATES = @(
  (Join-Path $env:LOCALAPPDATA "Programs\Introduction\Introduction.exe"),
  (Join-Path $env:LOCALAPPDATA "Programs\Introduction\bin\introduction.cmd")
)
$INTRO_BIN = $null
foreach ($c in $INTRO_CANDIDATES) {
  if (Test-Path $c) { $INTRO_BIN = $c; break }
}
if (-not $INTRO_BIN) {
  Warn "Introduction no encontrada — instálala primero:"
  Warn "  iwr -useb https://raw.githubusercontent.com/rsrs123/introduction-binaries/main/install.ps1 | iex"
  $cont = Read-Host "¿Continuar solo con settings + proyectos? [y/N]"
  if ($cont -notmatch '^[Yy]') { exit 0 }
}
if ($INTRO_BIN) { OK "Introduction: $INTRO_BIN" }

# Asegurar dir
New-Item -ItemType Directory -Path $INTRO_USER -Force | Out-Null
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 2) STEP 1 — Settings + keybindings + snippets
# ──────────────────────────────────────────────────────────────────────────────
Say Cyan "[1/4] Settings globales"
Hr

$do_global = Read-Host "¿Migrar settings.json + keybindings.json + snippets/ ? [Y/n]"
if (-not $do_global -or $do_global -match '^[Yy]') {
  foreach ($f in @('settings.json', 'keybindings.json')) {
    $src = Join-Path $CURSOR_USER $f
    $dst = Join-Path $INTRO_USER $f
    if (Test-Path $src) {
      if (Test-Path $dst) {
        $backup = "$dst.backup-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $dst $backup
        Warn "Backup previo: $backup"
      }
      Copy-Item $src $dst -Force
      OK "$f migrado"
    }
  }
  $snip_src = Join-Path $CURSOR_USER "snippets"
  if (Test-Path $snip_src) {
    $snip_dst = Join-Path $INTRO_USER "snippets"
    Copy-Item -Path "$snip_src\*" -Destination $snip_dst -Recurse -Force
    OK "snippets/ migrados"
  }
}
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 3) STEP 2 — Proyectos Cursor
# ──────────────────────────────────────────────────────────────────────────────
Say Cyan "[2/4] Proyectos Cursor"
Hr

Step "Escaneando carpetas comunes por proyectos con .cursor/..."
$searchDirs = @(
  (Join-Path $env:USERPROFILE "Projects"),
  (Join-Path $env:USERPROFILE "Code"),
  (Join-Path $env:USERPROFILE "Documents\Projects"),
  (Join-Path $env:USERPROFILE "Documents\Code"),
  (Join-Path $env:USERPROFILE "Desktop"),
  (Join-Path $env:USERPROFILE "source\repos"),
  (Join-Path $env:USERPROFILE "dev")
)
$extra = Read-Host "¿Otra carpeta raíz para escanear? (vacío para skip)"
if ($extra) { $searchDirs += $extra }

$projects = @()
foreach ($sd in $searchDirs) {
  if (Test-Path $sd) {
    Get-ChildItem -Path $sd -Directory -Force -Filter ".cursor" -Recurse -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object {
      $projects += $_.Parent.FullName
    }
  }
}
$projects = $projects | Sort-Object -Unique

if ($projects.Count -eq 0) {
  Warn "No se encontraron proyectos con .cursor/"
  $selected = @()
} else {
  Write-Host ""
  Write-Host "Encontrados $($projects.Count) proyectos:"
  for ($i = 0; $i -lt $projects.Count; $i++) {
    "{0,3}) {1}" -f ($i + 1), $projects[$i] | Write-Host
  }
  Write-Host ""
  $sel = Read-Host "Selecciona proyectos (ej: '1 3 5' / 'all' / 'none')"

  $selected = @()
  if ($sel -eq 'all') {
    $selected = $projects
  } elseif ($sel -ne 'none' -and $sel) {
    foreach ($n in ($sel -split '\s+')) {
      $idx = [int]$n - 1
      if ($idx -ge 0 -and $idx -lt $projects.Count) { $selected += $projects[$idx] }
    }
  }
}

$destRoot = $null
if ($selected.Count -gt 0) {
  Write-Host ""
  $destRoot = Read-Host "Carpeta destino [default: $env:USERPROFILE\Introduction-Workspace]"
  if (-not $destRoot) { $destRoot = Join-Path $env:USERPROFILE "Introduction-Workspace" }
  New-Item -ItemType Directory -Path $destRoot -Force | Out-Null

  foreach ($proj in $selected) {
    $name = Split-Path $proj -Leaf
    $dest = Join-Path $destRoot $name
    if (Test-Path $dest) {
      Warn "$dest ya existe — skip (no sobrescribimos)"
      continue
    }
    Step "Copiando $name → $dest..."
    # robocopy excluyendo node_modules, .git, dist, etc.
    $excludes = @('node_modules', '.git', 'dist', 'build', '.next', '.turbo', '.venv', '__pycache__')
    $rcArgs = @($proj, $dest, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP', '/XD') + $excludes
    & robocopy @rcArgs | Out-Null

    # Rename .cursor → .introduction en la copia
    $cursorDir = Join-Path $dest ".cursor"
    if (Test-Path $cursorDir) {
      Rename-Item -Path $cursorDir -NewName ".introduction"
      OK "$name`: .cursor/ → .introduction/"
    }
    OK "Copiado: $dest"
  }
}
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 4) STEP 3 — Extensions
# ──────────────────────────────────────────────────────────────────────────────
Say Cyan "[3/4] Extensions"
Hr

$installed_count = 0
if (-not $INTRO_BIN) {
  Warn "Introduction no encontrada — skip extensions"
} elseif (-not (Test-Path $CURSOR_EXTS)) {
  Warn "$CURSOR_EXTS no existe"
} else {
  $exts = @()
  Get-ChildItem -Path $CURSOR_EXTS -Directory | ForEach-Object {
    $name = $_.Name
    # Extrae publisher.name (sin -version final)
    if ($name -match '^(.+)-\d+\.\d+\.\d+') {
      $exts += $matches[1]
    }
  }
  $exts = $exts | Sort-Object -Unique

  if ($exts.Count -eq 0) {
    Warn "No se detectaron extensions"
  } else {
    Write-Host "Encontradas $($exts.Count) extensions en Cursor:"
    for ($i = 0; $i -lt $exts.Count; $i++) {
      "{0,3}) {1}" -f ($i + 1), $exts[$i] | Write-Host
    }
    Write-Host ""
    Write-Host "Opciones: 'all' (todas), 'none' (skip), '1 3 5' (selección)"
    $extSel = Read-Host "Tu elección"

    $selected_ext = @()
    if ($extSel -eq 'all') {
      $selected_ext = $exts
    } elseif ($extSel -ne 'none' -and $extSel) {
      foreach ($n in ($extSel -split '\s+')) {
        $idx = [int]$n - 1
        if ($idx -ge 0 -and $idx -lt $exts.Count) { $selected_ext += $exts[$idx] }
      }
    }

    if ($selected_ext.Count -gt 0) {
      Write-Host ""
      Step "Instalando $($selected_ext.Count) extensions..."
      $failed = @()
      foreach ($ext in $selected_ext) {
        $padded = $ext.PadRight(50)
        Write-Host -NoNewline "  → $padded "
        $result = & $INTRO_BIN --install-extension $ext --force 2>&1
        if ($LASTEXITCODE -eq 0) {
          Write-Host "OK" -ForegroundColor Green
          $installed_count++
        } else {
          Write-Host "FAIL" -ForegroundColor Red
          $failed += $ext
        }
      }
      Write-Host ""
      OK "Instaladas: $installed_count / $($selected_ext.Count)"
      if ($failed.Count -gt 0) {
        Warn "Fallaron $($failed.Count) (probable: no disponibles en Open VSX):"
        $failed | ForEach-Object { "    - $_" } | Write-Host
      }
    }
  }
}
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 5) Resumen final
# ──────────────────────────────────────────────────────────────────────────────
Say Cyan "[4/4] Resumen"
Hr
Write-Host ""
Say Green "🎯 Migración completada"
Write-Host ""
Write-Host "  Settings:    $INTRO_USER"
Write-Host "  Proyectos:   $($destRoot ?? '(no migrados)')"
Write-Host "  Extensions:  $installed_count instaladas"
Write-Host ""
Write-Host "Próximos pasos:"
Write-Host "  1) Abre Introduction (Start menu)"
Write-Host "  2) File → Open Folder → $($destRoot ?? 'proyecto')"
Write-Host "  3) Ctrl+Shift+P → 'Introduction: Choose Your Plan' → Community"
Write-Host "  4) Ctrl+Shift+P → 'Introduction: Configure AI Providers'"
Write-Host ""
Say Cyan "Tus proyectos originales en Cursor NO fueron tocados. Quedan intactos."

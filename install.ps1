#!/usr/bin/env pwsh
# install.ps1 — Introduction installer one-liner para Windows.
#
# Uso (PowerShell):
#   iwr -useb https://raw.githubusercontent.com/rsrs123/introduction-binaries/main/install.ps1 | iex
#
# Detecta arch (x64), descarga el zip del último GitHub Release público,
# extrae a %LOCALAPPDATA%\Programs\Introduction\, añade al PATH del usuario,
# crea acceso directo en Start Menu, lanza la app.

$ErrorActionPreference = 'Stop'

# UTF-8 en consola para que los caracteres ✓ ✗ → → → no salgan como ???
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

# Acelera Invoke-WebRequest (sin barra de progreso default = ~10x más rápido)
$ProgressPreference = 'Continue'

$REPO        = 'rsrs123/introduction-binaries'
$APP_NAME    = 'Introduction'
$INSTALL_DIR = Join-Path $env:LOCALAPPDATA "Programs\$APP_NAME"

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────
function Write-OK   { param($Msg) Write-Host "✓ $Msg" -ForegroundColor Green }
function Write-Step { param($Msg) Write-Host "→ $Msg" -ForegroundColor Cyan }
function Write-Err  { param($Msg) Write-Host "❌ $Msg" -ForegroundColor Red; exit 1 }

# ──────────────────────────────────────────────────────────────────────────────
# 1) Detectar arquitectura
# ──────────────────────────────────────────────────────────────────────────────
$arch = $env:PROCESSOR_ARCHITECTURE.ToLower()
$assetName = switch ($arch) {
  'amd64' { 'Introduction-win32-x64.zip' }
  'arm64' { Write-Err "Windows ARM64 no soportado todavía (siguiente release)" }
  default { Write-Err "Arquitectura no soportada: $arch" }
}

Write-Host ""
Write-Host "  Introduction installer (Windows)" -ForegroundColor Cyan
Write-Host "  Arch:  $arch"
Write-Host "  Asset: $assetName"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 2) Buscar último Release
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Buscando último release de $REPO..."
try {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/releases/latest" -UseBasicParsing
} catch {
  Write-Err "No se pudo obtener el release. Verifica conexión."
}

$tag = $release.tag_name
if (-not $tag) { Write-Err "No hay releases publicados todavía" }

$asset = $release.assets | Where-Object { $_.name -eq $assetName }
if (-not $asset) { Write-Err "Asset $assetName no encontrado en release $tag" }

Write-OK "Release: $tag"
Write-Host "  URL:   $($asset.browser_download_url)"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 3) Descargar
# ──────────────────────────────────────────────────────────────────────────────
$tmpDir = Join-Path $env:TEMP "introduction-installer-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$zipPath = Join-Path $tmpDir $assetName

Write-Step "Descargando ~180 MB..."
try {
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
} catch {
  Write-Err "Error al descargar: $_"
}
Write-OK "Descargado a $zipPath"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 4) Cerrar app si está corriendo (idempotente)
# ──────────────────────────────────────────────────────────────────────────────
# Cierra TODAS las instancias de Introduction.exe (incluso de carpetas viejas)
$procs = Get-Process -Name 'Introduction' -ErrorAction SilentlyContinue
if ($procs) {
  Write-Step "Cerrando $(($procs).Count) proceso(s) Introduction.exe..."
  $procs | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

# ──────────────────────────────────────────────────────────────────────────────
# 5) Extraer en INSTALL_DIR (idempotente — sobrescribe versión anterior)
# ──────────────────────────────────────────────────────────────────────────────
if (Test-Path $INSTALL_DIR) {
  Write-Step "Versión anterior detectada — actualizando $INSTALL_DIR"
  Remove-Item -Path $INSTALL_DIR -Recurse -Force
}

Write-Step "Extrayendo en $INSTALL_DIR..."
$extractTmp = Join-Path $tmpDir 'extracted'
Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force

# El zip contiene Introduction-win32-x64/ — renombrar a Introduction
$inner = Get-ChildItem -Path $extractTmp -Directory | Select-Object -First 1
Move-Item -Path $inner.FullName -Destination $INSTALL_DIR
Write-OK "Instalado en $INSTALL_DIR"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 5.5) Aplicar bundle de assets visuales (workaround VSCodium override)
#       VSCodium prepare_vscode.sh sobrescribe code-icon.svg + letterpress-*.svg
#       durante build. Aquí los re-aplicamos post-install.
# ──────────────────────────────────────────────────────────────────────────────
Write-Step "Aplicando bundle de assets Introduction..."
$assetsUrl = "https://github.com/$REPO/releases/download/$tag/introduction-assets.tar.gz"
$assetsTar = Join-Path $tmpDir "assets.tar.gz"
$assetsDir = Join-Path $tmpDir "assets"
try {
  Invoke-WebRequest -Uri $assetsUrl -OutFile $assetsTar -UseBasicParsing -ErrorAction Stop
  New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
  # tar.exe existe nativamente en Windows 10+ (build 17063+)
  & tar -xzf $assetsTar -C $assetsDir 2>&1 | Out-Null

  $mediaDir = Join-Path $INSTALL_DIR "resources\app\out\media"
  $agentDir = Join-Path $INSTALL_DIR "resources\app\out\vs\sessions\contrib\chat\browser\media"

  if (Test-Path $mediaDir) {
    foreach ($variant in 'dark','light','hcDark','hcLight') {
      $src = Join-Path $assetsDir "letterpress-$variant.svg"
      if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $mediaDir "letterpress-$variant.svg") -Force }
    }
    $src = Join-Path $assetsDir "code-icon.svg"
    if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $mediaDir "code-icon.svg") -Force }
  }
  if (Test-Path $agentDir) {
    foreach ($v in '','-exploration','-insider','-stable') {
      $src = Join-Path $assetsDir "code-icon-agent-sessions$v.svg"
      if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $agentDir "code-icon-agent-sessions$v.svg") -Force }
    }
  }
  Write-OK "Bundle de assets aplicado"
} catch {
  Write-Host "  ⚠ No se pudo descargar bundle de assets (no crítico): $_" -ForegroundColor Yellow
}
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 6) Añadir al PATH del usuario (introduction CLI)
# ──────────────────────────────────────────────────────────────────────────────
$binDir = Join-Path $INSTALL_DIR 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
  Write-Step "Añadiendo $binDir al PATH del usuario..."
  $newPath = if ($userPath) { "$userPath;$binDir" } else { $binDir }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  Write-OK "PATH actualizado (re-abre PowerShell para refrescar)"
}

# ──────────────────────────────────────────────────────────────────────────────
# 7) Acceso directo en Start Menu
# ──────────────────────────────────────────────────────────────────────────────
$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$shortcutPath = Join-Path $startMenu "Introduction.lnk"
$exePath = Join-Path $INSTALL_DIR "Introduction.exe"

Write-Step "Creando acceso directo en Start Menu..."
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $INSTALL_DIR
$shortcut.IconLocation = $exePath
$shortcut.Description = "Introduction — Sovereign IDE"
$shortcut.Save()
Write-OK "Acceso directo: $shortcutPath"
Write-Host ""

# ──────────────────────────────────────────────────────────────────────────────
# 8) Cleanup + lanzar
# ──────────────────────────────────────────────────────────────────────────────
Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "🎯 Introduction instalado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "  Lanzar:    Start menu → 'Introduction'  o  $exePath"
Write-Host "  CLI:       introduction --help  (re-abre PowerShell para que el PATH refresque)"
Write-Host ""

$launch = Read-Host "¿Lanzar Introduction ahora? [Y/n]"
if ($launch -eq '' -or $launch -match '^[Yy]') {
  Start-Process -FilePath $exePath
}

Write-Host ""
Write-Host "Visita https://getintroduction.com/docs para empezar" -ForegroundColor Green

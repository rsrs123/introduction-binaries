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
Get-Process -Name 'Introduction' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Step "Cerrando proceso Introduction.exe (PID $($_.Id))..."
  $_ | Stop-Process -Force
  Start-Sleep -Seconds 1
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

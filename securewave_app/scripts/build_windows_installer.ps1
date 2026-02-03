Param(
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Guard against packaging without WireGuard installed, which breaks VPN setup on Windows.
$wireguardPath = $null
if ($env:SECUREWAVE_WIREGUARD_PATH -and (Test-Path $env:SECUREWAVE_WIREGUARD_PATH)) {
  $wireguardPath = $env:SECUREWAVE_WIREGUARD_PATH
}
if (-not $wireguardPath) {
  $candidatePaths = @(
    "$env:ProgramFiles\WireGuard\wireguard.exe",
    "$env:ProgramFiles(x86)\WireGuard\wireguard.exe"
  )
  foreach ($path in $candidatePaths) {
    if (Test-Path $path) {
      $wireguardPath = $path
      break
    }
  }
}
if (-not $wireguardPath) {
  $cmd = Get-Command wireguard.exe -ErrorAction SilentlyContinue
  if ($cmd) {
    $wireguardPath = $cmd.Source
  }
}
if (-not $wireguardPath) {
  Write-Error "WireGuard for Windows not found. Install from https://www.wireguard.com/install/ or set SECUREWAVE_WIREGUARD_PATH."
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Error "flutter is not installed or not on PATH."
}

if (-not (Get-Command makensis -ErrorAction SilentlyContinue)) {
  Write-Error "NSIS (makensis) is required. Install via: choco install nsis"
}

flutter pub get
flutter build windows --release

if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspec = Get-Content "$root\pubspec.yaml"
  $match = $pubspec | Select-String -Pattern "^version:\s*(.+)$"
  if ($match) {
    $Version = $match.Matches[0].Groups[1].Value.Trim()
  }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = "0.0.0"
}

$installerDir = Join-Path $root "build\installer"
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

$nsisScript = Join-Path $root "windows\installer\securewave_installer.nsi"
$outFile = Join-Path $installerDir "SecureWaveVPN-$Version-setup.exe"

& makensis "/DVERSION=$Version" "/DOUTPUT_FILE=$outFile" $nsisScript

Write-Host "OK: Built $outFile"

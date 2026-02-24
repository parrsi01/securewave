Param(
  [string]$Version = "",
  [string]$WireGuardVersion = "0.5.3",
  [string]$ApiBaseUrl = "",
  [string]$PortalUrl = "",
  [string]$UpgradeUrl = "",
  [ValidateSet("x64")]
  [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$Title) {
  Write-Host ""
  Write-Host "== $Title =="
}

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Parse-Version([string]$RawVersion) {
  # pubspec.yaml uses: MAJOR.MINOR.PATCH+BUILD
  $display = $RawVersion.Trim()
  $app = $display
  $build = "0"
  if ($display -match "^([0-9]+\\.[0-9]+\\.[0-9]+)\\+([0-9]+)$") {
    $app = $matches[1]
    $build = $matches[2]
  } elseif ($display -match "^([0-9]+\\.[0-9]+\\.[0-9]+)$") {
    $app = $matches[1]
    $build = "0"
  }
  $info = "$app.$build"
  return [pscustomobject]@{
    Display = $display
    App     = $app
    Build   = $build
    Info    = $info
  }
}

$repoRoot = Resolve-RepoRoot
$appRoot = Join-Path $repoRoot "securewave_app"
$installerRoot = Join-Path $repoRoot "windows_installer"
$depsDir = Join-Path $installerRoot "deps"
$artifactsDir = Join-Path $repoRoot "artifacts" "windows_release"
$downloadsDir = Join-Path $repoRoot "static" "downloads"

New-Item -ItemType Directory -Force -Path $depsDir | Out-Null
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

$logPath = Join-Path $artifactsDir "INSTALLER_BUILD_LOG.txt"
if (Test-Path $logPath) {
  Remove-Item -Force $logPath
}

Start-Transcript -Path $logPath -Force | Out-Null

try {
  Write-Section "Environment"
  Write-Host "Repo: $repoRoot"
  Write-Host "App:  $appRoot"
  Write-Host "Arch: $Architecture"

  Write-Section "Backend Configuration"
  if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) { $ApiBaseUrl = $env:SECUREWAVE_API_BASE_URL }
  if ([string]::IsNullOrWhiteSpace($PortalUrl)) { $PortalUrl = $env:SECUREWAVE_PORTAL_URL }
  if ([string]::IsNullOrWhiteSpace($UpgradeUrl)) { $UpgradeUrl = $env:SECUREWAVE_UPGRADE_URL }

  if ([string]::IsNullOrWhiteSpace($PortalUrl) -and -not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $PortalUrl = ($ApiBaseUrl.TrimEnd('/') -replace '/api$', '')
  }
  if ([string]::IsNullOrWhiteSpace($UpgradeUrl) -and -not [string]::IsNullOrWhiteSpace($PortalUrl)) {
    $UpgradeUrl = ($PortalUrl.TrimEnd('/') + "/subscription")
  }

  if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    throw "SECUREWAVE_API_BASE_URL is required. Pass -ApiBaseUrl or set the environment variable."
  }

  Write-Host "SECUREWAVE_API_BASE_URL: $ApiBaseUrl"
  Write-Host "SECUREWAVE_PORTAL_URL:   $PortalUrl"
  Write-Host "SECUREWAVE_UPGRADE_URL:  $UpgradeUrl"

  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter is not installed or not on PATH."
  }

  $isccCandidates = @(
    "$env:ProgramFiles(x86)\\Inno Setup 6\\ISCC.exe",
    "$env:ProgramFiles\\Inno Setup 6\\ISCC.exe"
  )
  $iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $iscc) {
    throw "Inno Setup 6 compiler (ISCC.exe) not found. Install Inno Setup 6, then re-run."
  }

  Write-Host "ISCC: $iscc"

  Write-Section "Resolve Version"
  if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionFile = Join-Path $repoRoot "VERSION"
    if (Test-Path $versionFile) {
      $Version = (Get-Content $versionFile | Select-Object -First 1).Trim()
    }
  }
  if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "VERSION file is missing or empty. Set -Version or populate VERSION."
  }
  $ver = Parse-Version $Version
  Write-Host "Version display: $($ver.Display)"
  Write-Host "Version app:     $($ver.App)"
  Write-Host "Version info:    $($ver.Info)"

  $versionInclude = Join-Path $installerRoot "version.iss"
  if (-not (Test-Path $versionInclude)) {
    throw "Expected version include missing: $versionInclude (run scripts/sync_versions.py)."
  }

  Write-Section "Download WireGuard MSI"
  $wgUrl = "https://download.wireguard.com/windows-client/wireguard-amd64-$WireGuardVersion.msi"
  $wgOut = Join-Path $depsDir "wireguard-amd64.msi"
  Write-Host "URL:  $wgUrl"
  Write-Host "Dest: $wgOut"
  if ($PSVersionTable.PSVersion.Major -lt 6) {
    Invoke-WebRequest -Uri $wgUrl -OutFile $wgOut -UseBasicParsing
  } else {
    Invoke-WebRequest -Uri $wgUrl -OutFile $wgOut
  }
  if (-not (Test-Path $wgOut)) {
    throw "WireGuard MSI download failed: $wgOut"
  }

  Write-Section "Flutter Build (Windows Release)"
  Push-Location $appRoot
  try {
    flutter pub get
    $flutterArgs = @(
      "build", "windows", "--release",
      "--dart-define=SECUREWAVE_API_BASE_URL=$ApiBaseUrl"
    )
    if (-not [string]::IsNullOrWhiteSpace($PortalUrl)) {
      $flutterArgs += "--dart-define=SECUREWAVE_PORTAL_URL=$PortalUrl"
    }
    if (-not [string]::IsNullOrWhiteSpace($UpgradeUrl)) {
      $flutterArgs += "--dart-define=SECUREWAVE_UPGRADE_URL=$UpgradeUrl"
    }
    flutter @flutterArgs
  } finally {
    Pop-Location
  }

  $bundleRoot = Join-Path $appRoot "build\\windows\\x64\\runner\\Release"
  if (-not (Test-Path $bundleRoot)) {
    throw "Flutter Windows release bundle not found at: $bundleRoot"
  }

  Write-Section "Compile Inno Setup Installer"
  Push-Location $installerRoot
  try {
    & $iscc "securewave_installer.iss"
  } finally {
    Pop-Location
  }

  $installerExe = Join-Path $artifactsDir "securewave-windows-x64-setup.exe"
  if (-not (Test-Path $installerExe)) {
    throw "Installer was not generated at: $installerExe"
  }

  Write-Host "OK: Built $installerExe"

  Write-Section "Publish To Backend Downloads Folder"
  if (-not (Test-Path $downloadsDir)) {
    New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
  }
  Copy-Item -Force $installerExe (Join-Path $downloadsDir "securewave-windows-x64-setup.exe")
  $publishedPath = Join-Path $downloadsDir "securewave-windows-x64-setup.exe"
  Write-Host "OK: Copied to $publishedPath"

  Write-Section "Generate Reports"
  $installReport = Join-Path $artifactsDir "INSTALL_REPORT.md"
  $driverReport = Join-Path $artifactsDir "DRIVER_INTEGRATION_REPORT.md"

  @"
# SecureWave Windows Installer Build Report

Build time (UTC): $(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

## Inputs

- SecureWave app version: $($ver.Display)
- SECUREWAVE_API_BASE_URL: $ApiBaseUrl
- SECUREWAVE_PORTAL_URL: $PortalUrl
- SECUREWAVE_UPGRADE_URL: $UpgradeUrl
- WireGuard MSI: $wgUrl
- Architecture: $Architecture

## Outputs

- Installer: artifacts/windows_release/securewave-windows-x64-setup.exe
- Published to: static/downloads/securewave-windows-x64-setup.exe
- Build log: artifacts/windows_release/INSTALLER_BUILD_LOG.txt

## Silent Install

- SecureWave installer: `securewave-windows-x64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
- WireGuard MSI (embedded): installed via `msiexec.exe /i wireguard-amd64.msi /quiet /norestart DO_NOT_LAUNCH=1`
"@ | Set-Content -Encoding UTF8 $installReport

  @"
# WireGuard Driver/Service Integration Report (Windows)

## Strategy

- SecureWave uses the official WireGuard for Windows tooling (`wireguard.exe`) to install/uninstall the tunnel service.
- The SecureWave installer bundles the WireGuard MSI and installs it silently if WireGuard is not present.
- Tunnel operations (connect/disconnect) request UAC elevation at runtime when needed.

## Verification Checklist (Manual)

1. Install SecureWave:
   - `securewave-windows-x64-setup.exe`
2. Confirm WireGuard installed:
   - `Test-Path "$env:ProgramFiles\\WireGuard\\wireguard.exe"`
3. Confirm manager service exists:
   - `Get-Service WireGuardManager`
4. Launch SecureWave and connect:
   - Expect a UAC prompt on first connect/disconnect (tunnel service operations).
5. Confirm tunnel service:
   - `Get-Service "WireGuardTunnel`$SecureWave"`
6. Uninstall SecureWave and confirm tunnel cleanup:
   - `Get-Service "WireGuardTunnel`$SecureWave"` should not exist (if it was installed)
"@ | Set-Content -Encoding UTF8 $driverReport

} finally {
  Stop-Transcript | Out-Null
}

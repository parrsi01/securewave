$ErrorActionPreference = "Stop"

$possiblePaths = @(
  "$env:ProgramFiles\WireGuard\wireguard.exe",
  "$env:ProgramFiles(x86)\WireGuard\wireguard.exe"
)

$wireguardPath = $null
foreach ($path in $possiblePaths) {
  if (Test-Path $path) {
    $wireguardPath = $path
    break
  }
}

if (-not $wireguardPath) {
  $cmd = Get-Command wireguard.exe -ErrorAction SilentlyContinue
  if ($cmd) {
    $wireguardPath = $cmd.Source
  }
}

if (-not $wireguardPath) {
  Write-Error "WireGuard is not installed. Install from https://www.wireguard.com/install/ and re-run this check."
  exit 1
}

Write-Output "WireGuard binary found: $wireguardPath"

$service = Get-Service -Name "WireGuardManager" -ErrorAction SilentlyContinue
if (-not $service) {
  Write-Warning "WireGuardManager service not found. Ensure WireGuard is installed with the official installer."
} else {
  Write-Output "WireGuardManager service: $($service.Status)"
}

$tunnelServices = Get-Service -Name "WireGuardTunnel$*" -ErrorAction SilentlyContinue
if ($tunnelServices) {
  $tunnelServices | ForEach-Object { Write-Output "Tunnel service: $($_.Name) ($($_.Status))" }
} else {
  Write-Warning "No WireGuard tunnel services detected."
}

Write-Output "WireGuard validation complete."

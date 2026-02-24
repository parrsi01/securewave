Param(
  [string]$ApiBaseUrl = $env:LIVE_API_BASE_URL,
  [string]$HetznerIp  = $env:HETZNER_IP,
  [int]$Users = 3,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  return (Resolve-Path (Join-Path $here "..\\..")).Path
}

$RepoRoot = Resolve-RepoRoot
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$RunDir = Join-Path $RepoRoot ("artifacts\\live_hetzner\\$RunId")
$LiveValidationOut = Join-Path $RunDir "live_validation"

New-Item -ItemType Directory -Force -Path $LiveValidationOut | Out-Null

if (-not $ApiBaseUrl) {
  throw "LIVE_API_BASE_URL is required (example: https://<hetzner-ip> or https://api.example.com)"
}

Write-Host "run_id=$RunId"
Write-Host "run_dir=$RunDir"

# Use system python on Windows.
$Py = "python"

Write-Host "1) Live WireGuard E2E validation (Windows commands via wireguard.exe/wg.exe)..."
$Args = @(
  (Join-Path $RepoRoot "dev_tools\\sandbox\\live_validation\\live_e2e_validate.py"),
  "--output-dir", $LiveValidationOut,
  "--api-base-url", $ApiBaseUrl,
  "--users", $Users,
  "--platform", "windows"
)
if ($Strict) { $Args += "--strict" }

try {
  & $Py @Args 1> (Join-Path $LiveValidationOut "stdout.json") 2> (Join-Path $LiveValidationOut "stderr.log")
} catch {
  $_ | Out-String | Set-Content -Encoding utf8 (Join-Path $LiveValidationOut "exception.txt")
}

Write-Host "2) Generate readiness summary..."
try {
  & $Py (Join-Path $RepoRoot "dev_tools\\sandbox\\live_validation\\reporting.py") `
    "--output-dir" $LiveValidationOut `
    1> (Join-Path $LiveValidationOut "readiness_stdout.json") 2> (Join-Path $LiveValidationOut "readiness_stderr.log")
} catch {
  $_ | Out-String | Set-Content -Encoding utf8 (Join-Path $LiveValidationOut "readiness_exception.txt")
}

Write-Host "3) Basic smoke checks..."
try {
  & bash (Join-Path $RepoRoot "sandbox\\live_hetzner\\smoke_http_https.sh") `
    "--api-base-url" $ApiBaseUrl `
    $(if ($HetznerIp) { "--ip" } else { "" }) `
    $(if ($HetznerIp) { $HetznerIp } else { "" }) `
    "--out" (Join-Path $RunDir "smoke_http_https.json") `
    1> (Join-Path $RunDir "smoke_http_https.log") 2>&1
} catch { }

try {
  & bash (Join-Path $RepoRoot "sandbox\\live_hetzner\\ssl_probe.sh") `
    $(if ($HetznerIp) { "--ip" } else { "" }) `
    $(if ($HetznerIp) { $HetznerIp } else { "" }) `
    "--api-base-url" $ApiBaseUrl `
    "--out" (Join-Path $RunDir "ssl_probe.json") `
    1> (Join-Path $RunDir "ssl_probe.log") 2>&1
} catch { }

try {
  & bash (Join-Path $RepoRoot "sandbox\\live_hetzner\\metrics_probe.sh") `
    "--api-base-url" $ApiBaseUrl `
    "--out" (Join-Path $RunDir "metrics_probe.json") `
    1> (Join-Path $RunDir "metrics_probe.log") 2>&1
} catch { }

Write-Host "4) Stripe smoke (safe by default)..."
try {
  & bash (Join-Path $RepoRoot "sandbox\\live_hetzner\\stripe_live_smoke_check.sh") `
    "--api-base-url" $ApiBaseUrl `
    "--out" (Join-Path $RunDir "stripe_smoke.json") `
    1> (Join-Path $RunDir "stripe_smoke.log") 2>&1
} catch { }

Write-Host "5) Domain preview helper..."
try {
  & bash (Join-Path $RepoRoot "sandbox\\live_hetzner\\domain_preview_setup.sh") `
    $(if ($HetznerIp) { "--ip" } else { "" }) `
    $(if ($HetznerIp) { $HetznerIp } else { "" }) `
    "--out" (Join-Path $RunDir "domain_preview.json") `
    1> (Join-Path $RunDir "domain_preview.log") 2>&1
} catch { }

Write-Host "6) Generate consolidated report..."
try {
  & $Py (Join-Path $RepoRoot "sandbox\\live_hetzner\\generate_live_hetzner_smoke_report.py") `
    "--run-dir" $RunDir `
    "--out" (Join-Path $RepoRoot "artifacts\\live_hetzner_smoke_report.md") `
    1> (Join-Path $RunDir "report_generation.log") 2>&1
} catch { }

Write-Host ""
Write-Host "Outputs:"
Write-Host ("- " + (Join-Path $RepoRoot "artifacts\\live_hetzner_smoke_report.md"))
Write-Host ("- " + $RunDir)


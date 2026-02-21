<#
.SYNOPSIS
    Ratchet verification hook - Windows PowerShell version.
.DESCRIPTION
    PowerShell port of verify.sh. Runs HTTP health checks, Docker Compose service
    checks, JWT endpoint test, and custom shell commands from .ratchet/verify.json.
    Exit 0 = all pass, Exit 1 = one or more failures.
.EXAMPLE
    .\verify.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$VerifyJson = '.ratchet\verify.json'
$Failures   = [System.Collections.Generic.List[string]]::new()

function Write-Pass([string]$msg) { Write-Host "[verify] PASS: $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) {
    Write-Host "[verify] FAIL: $msg" -ForegroundColor Red
    $Failures.Add($msg)
}
function Write-Info([string]$msg) { Write-Host "[verify] $msg" }

# Detect python
$Python = $null
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    $Python = "python3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $Python = "python"
} else {
    Write-Error "ERROR: python3 or python not found in PATH"
    exit 1
}

if (-not (Test-Path $VerifyJson)) {
    Write-Info "WARNING: $VerifyJson not found - skipping all checks"
    exit 0
}

$config = Get-Content -Raw $VerifyJson | ConvertFrom-Json

# --- HTTP health checks ---
Write-Info "Running HTTP health checks..."
foreach ($check in $config.http_checks) {
    $url      = $check.url
    $expected = if ($check.PSObject.Properties["expected_status"]) { [string]$check.expected_status } else { "200" }
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $actual   = [string]$response.StatusCode
    } catch [System.Net.WebException] {
        $actual = if ($_.Exception.Response) { [string][int]$_.Exception.Response.StatusCode } else { "000" }
    } catch {
        $actual = "000"
    }
    if ($actual -eq $expected) {
        Write-Pass "HTTP $url ->$actual"
    } else {
        Write-Fail "HTTP $url returned $actual (expected $expected)"
    }
}

# --- Docker Compose service health ---
Write-Info "Running Docker Compose service checks..."
if ($config.docker_services -and $config.docker_services.Count -gt 0) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Info 'WARNING: docker not found - skipping Docker checks'
    } else {
        foreach ($service in $config.docker_services) {
            $rawJson = docker compose ps --format json 2>$null
            $state   = "not-found"
            foreach ($line in $rawJson -split "`n") {
                $line = $line.Trim()
                if (-not $line) { continue }
                try {
                    $s    = $line | ConvertFrom-Json
                    $name = if ($s.PSObject.Properties["Service"]) { $s.Service } else { $s.Name }
                    if ($name -eq $service -or $name -match "[_-]$([regex]::Escape($service))$") {
                        $state = if ($s.PSObject.Properties["Health"] -and $s.Health) { $s.Health } else { $s.State }
                        break
                    }
                } catch { continue }
            }
            if ($state -eq "healthy" -or $state -eq "running") {
                Write-Pass "Docker service '$service' ->$state"
            } else {
                Write-Fail "Docker service '$service' is '$state' (expected healthy or running)"
            }
        }
    }
}

# --- JWT endpoint test ---
$jwtEndpoint = $config.jwt_endpoint
if ($jwtEndpoint) {
    Write-Info "Testing JWT endpoint: $jwtEndpoint"
    try {
        $response = Invoke-WebRequest -Uri $jwtEndpoint -Method Get -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $status   = [string]$response.StatusCode
    } catch [System.Net.WebException] {
        $status = if ($_.Exception.Response) { [string][int]$_.Exception.Response.StatusCode } else { "000" }
    } catch {
        $status = "000"
    }
    if ($status -eq "000") {
        Write-Fail "JWT endpoint $jwtEndpoint is unreachable"
    } elseif ($status -in @("200", "400", "401")) {
        Write-Pass "JWT endpoint $jwtEndpoint ->$status"
    } else {
        Write-Fail "JWT endpoint $jwtEndpoint returned unexpected status $status"
    }
}

# --- Custom checks ---
Write-Info "Running custom checks..."
foreach ($check in $config.custom_checks) {
    $name = $check.name
    $cmd  = $check.command
    Write-Info "Custom: $name"

    # Try bash first (Git Bash / WSL), then fall back to cmd, then direct Python
    $ok = $false
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        $result = bash -c $cmd 2>$null
        $ok     = $LASTEXITCODE -eq 0
    } elseif ($cmd -match "^python") {
        # Direct Python command on Windows
        $parts  = $cmd -split " ", 2
        $result = & $parts[0] ($parts[1..($parts.Length - 1)]) 2>$null
        $ok     = $LASTEXITCODE -eq 0
    } elseif ($cmd -match "^test -[fs] (.+)") {
        # Translate bash test builtins
        $path = $Matches[1]
        if ($cmd -match "^test -f") {
            $ok = Test-Path $path
        } elseif ($cmd -match "^test -s") {
            $ok = (Test-Path $path) -and (Get-Item $path).Length -gt 0
        }
    } else {
        $result = cmd /c $cmd 2>$null
        $ok     = $LASTEXITCODE -eq 0
    }

    if ($ok) {
        Write-Pass $name
    } else {
        Write-Fail "$name (command: $cmd)"
    }
}

# --- Summary ---
if ($Failures.Count -eq 0) {
    Write-Info "All checks passed."
    exit 0
} else {
    Write-Host ""
    Write-Host "[verify] FAILURES:" -ForegroundColor Red
    foreach ($f in $Failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

<#
.SYNOPSIS
    Ratchet autonomous AI agent loop - Windows PowerShell version.
.DESCRIPTION
    PowerShell port of ratchet.sh for native Windows use (no Git Bash or WSL required).
    Spawns repeated Claude Code iterations until all PRD stories pass or MaxIter is reached.
    NOTE: PowerShell uses single-dash parameters: -Tool, -MaxIter, -ProjectDir
.PARAMETER Tool
    AI tool to use: claude (default) or codex.
.PARAMETER MaxIter
    Maximum iterations before giving up (default: 20).
.PARAMETER ProjectDir
    Project directory containing CLAUDE.md and .ratchet/ (default: current directory).
.EXAMPLE
    .\ratchet.ps1 -ProjectDir C:\Projects\myapp -MaxIter 15
.EXAMPLE
    .\ratchet.ps1 -Tool codex -ProjectDir . -MaxIter 10
#>
[CmdletBinding()]
param(
    [string]$Tool       = 'claude',
    [int]   $MaxIter    = 20,
    [string]$ProjectDir = '.'
)

$ErrorActionPreference = 'Stop'

# Resolve to absolute path
$ProjectDir  = (Resolve-Path $ProjectDir).Path
$RatchetDir  = Join-Path $ProjectDir '.ratchet'
$Prd         = Join-Path $RatchetDir 'prd.json'
$Progress    = Join-Path $RatchetDir 'progress.md'
$LogsDir     = Join-Path $ProjectDir 'logs'

# --- Validation ---
if (-not (Test-Path $Prd)) {
    Write-Error "ERROR: $Prd not found. Run: python ratchet_state.py init --name <name>"
    exit 1
}

if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: '$Tool' not found in PATH"
    exit 1
}

# Detect python
$Python = $null
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    $Python = 'python3'
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $Python = 'python'
} else {
    Write-Error 'ERROR: python3 or python not found in PATH'
    exit 1
}

New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

function Count-Incomplete {
    $prdData = Get-Content -Raw $Prd | ConvertFrom-Json
    return ($prdData.stories | Where-Object { -not $_.passes }).Count
}

# Build trigger prompt - prepend Authorization lines from company.md so the
# agent sees them immediately, before applying any independent security judgment.
$CompanyMd  = Join-Path $RatchetDir 'company.md'
$AuthPrefix = ''
if (Test-Path $CompanyMd) {
    $authLines = Select-String -Path $CompanyMd -Pattern '^-\s*Authorization:' |
                 ForEach-Object { $_.Line -replace '^-\s*', '' }
    if ($authLines) {
        $AuthPrefix = ($authLines -join ' ') + ' '
    }
}
$TriggerPrompt = $AuthPrefix + 'You are running inside the Ratchet agent loop. Read CLAUDE.md for your full operating protocol, then work through the next incomplete story in .ratchet/prd.json.'

$iter = 0
while ($iter -lt $MaxIter) {
    $iter++
    $ts  = Get-Date -Format 'yyyyMMddTHHmmss'
    $Log = Join-Path $LogsDir "ratchet-$ts.log"

    $incomplete = Count-Incomplete
    if ($incomplete -eq 0) {
        Write-Host "=== All stories complete after $($iter - 1) iteration(s). ==="
        exit 0
    }

    Write-Host "=== Iteration $iter/$MaxIter | Incomplete stories: $incomplete ==="
    Write-Host "Log: $Log"

    # Run the AI tool from within the project directory, stream and log output
    Push-Location $ProjectDir
    try {
        & $Tool --dangerously-skip-permissions -p $TriggerPrompt 2>&1 |
            Tee-Object -FilePath $Log -Append
    } catch {
        Write-Host "WARNING: Tool exited with error: $_"
    } finally {
        Pop-Location
    }

    # Inspect log for completion signals
    $logContent = if (Test-Path $Log) { Get-Content -Raw $Log } else { '' }

    if ($logContent -match '(?m)^COMPLETE') {
        Write-Host '--- COMPLETE signal received ---'
        Add-Content -Path $Log -Value '--- COMPLETE signal received ---'
    } elseif ($logContent -match '(?m)^(BLOCKED:.+)') {
        $blocker = $Matches[1]
        $ts2     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $nl      = [System.Environment]::NewLine
        Write-Host "--- $blocker ---"
        Add-Content -Path $Log      -Value "--- $blocker ---"
        Add-Content -Path $Progress -Value ($nl + '## Blocker - ' + $ts2 + $nl + $nl + $blocker + $nl)
        Write-Host "Blocker recorded to $Progress"
    } else {
        Write-Host 'WARNING: No COMPLETE or BLOCKED signal found. Continuing loop...'
        Add-Content -Path $Log -Value 'WARNING: No COMPLETE or BLOCKED signal found.'
    }
}

Write-Host "=== Max iterations ($MaxIter) reached without full completion ==="
exit 1

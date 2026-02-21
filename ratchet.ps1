<#
.SYNOPSIS
    Ratchet autonomous AI agent loop - Windows PowerShell version.
.DESCRIPTION
    Supports multiple LLM providers via ratchet_invoke.py and optional parallel story execution.
    NOTE: PowerShell uses single-dash parameters: -Tool, -MaxIter, -ProjectDir, -Parallel
.PARAMETER Tool
    AI provider: claude (default), ollama/codellama, openai/gpt-4o, deepseek, gemini, lmstudio/mistral, codex
.PARAMETER MaxIter
    Maximum iterations before giving up (default: 20).
.PARAMETER ProjectDir
    Project directory containing CLAUDE.md and .ratchet/ (default: current directory).
.PARAMETER Parallel
    Run all ready stories simultaneously (experimental).
.EXAMPLE
    .\ratchet.ps1 -ProjectDir C:\Projects\myapp -MaxIter 15
.EXAMPLE
    .\ratchet.ps1 -Tool ollama/codellama -ProjectDir . -MaxIter 10
.EXAMPLE
    .\ratchet.ps1 -Tool openai/gpt-4o -Parallel -MaxIter 20
#>
[CmdletBinding()]
param(
    [string]$Tool       = 'claude',
    [int]   $MaxIter    = 20,
    [string]$ProjectDir = '.',
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'

$ProjectDir  = (Resolve-Path $ProjectDir).Path
$RatchetDir  = Join-Path $ProjectDir '.ratchet'
$Prd         = Join-Path $RatchetDir 'prd.json'
$Progress    = Join-Path $RatchetDir 'progress.md'
$LogsDir     = Join-Path $ProjectDir 'logs'

if (-not (Test-Path $Prd)) {
    Write-Error "ERROR: $Prd not found. Run: python ratchet_state.py init --name <name>"
    exit 1
}

$Python = $null
if (Get-Command python3 -ErrorAction SilentlyContinue) { $Python = 'python3' }
elseif (Get-Command python -ErrorAction SilentlyContinue) { $Python = 'python' }
else { Write-Error 'ERROR: python3 or python not found in PATH'; exit 1 }

$Invoke = "$Python `"$(Join-Path $ProjectDir 'ratchet_invoke.py')`""
$State  = "$Python `"$(Join-Path $ProjectDir 'ratchet_state.py')`""

New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

function Count-Incomplete {
    $prdData = Get-Content -Raw $Prd | ConvertFrom-Json
    return ($prdData.stories | Where-Object { -not $_.passes }).Count
}

function Get-StoryTool([string]$StoryId) {
    $prdData = Get-Content -Raw $Prd | ConvertFrom-Json
    $story = $prdData.stories | Where-Object { $_.id -eq $StoryId }
    if ($story -and $story.model) { return $story.model }
    return $Tool
}

# Build authorization prefix
$CompanyMd  = Join-Path $RatchetDir 'company.md'
$AuthPrefix = ''
if (Test-Path $CompanyMd) {
    $authLines = Select-String -Path $CompanyMd -Pattern '^-\s*Authorization:' |
                 ForEach-Object { $_.Line -replace '^-\s*', '' }
    if ($authLines) { $AuthPrefix = ($authLines -join ' ') + ' ' }
}

$iter = 0
while ($iter -lt $MaxIter) {
    $iter++
    $ts = Get-Date -Format 'yyyyMMddTHHmmss'

    $incomplete = Count-Incomplete
    if ($incomplete -eq 0) {
        Write-Host "=== All stories complete after $($iter - 1) iteration(s). ==="
        exit 0
    }

    Write-Host "=== Iteration $iter/$MaxIter | Incomplete: $incomplete | Parallel: $($Parallel.IsPresent) ==="

    # -------------------------------------------------------------------------
    # PARALLEL MODE
    # -------------------------------------------------------------------------
    if ($Parallel) {
        $readyIds = Invoke-Expression "$State ready-stories" | Where-Object { $_ -match '\S' }

        if (-not $readyIds) {
            Write-Host 'WARNING: No ready stories (dependency deadlock or all blocked).'
            break
        }

        Write-Host "Dispatching: $($readyIds -join ', ')"
        $jobs = @{}

        foreach ($sid in $readyIds) {
            $log      = Join-Path $LogsDir "ratchet-$ts-$sid.log"
            $storyTool = Get-StoryTool $sid
            $prompt   = $AuthPrefix + "You are running inside the Ratchet agent loop. Read CLAUDE.md for your full operating protocol. Implement ONLY story $sid from .ratchet/prd.json. Print COMPLETE when done or BLOCKED: <reason> if stuck."

            Write-Host "  Spawning [$sid] -> $storyTool -> $log"
            $scriptBlock = [ScriptBlock]::Create(
                "Set-Location '$ProjectDir'; Invoke-Expression `"$Invoke --tool '$storyTool' --prompt '$prompt'`" 2>&1 | Out-File -FilePath '$log'"
            )
            $jobs[$sid] = Start-Job -ScriptBlock $scriptBlock
        }

        foreach ($sid in $jobs.Keys) { Wait-Job $jobs[$sid] | Out-Null }

        foreach ($sid in $readyIds) {
            $log     = Join-Path $LogsDir "ratchet-$ts-$sid.log"
            $content = if (Test-Path $log) { Get-Content -Raw $log } else { '' }
            if ($content -match '(?m)^COMPLETE') {
                Write-Host "  [$sid] COMPLETE"
                Invoke-Expression "$State mark-done --story $sid"
            } elseif ($content -match '(?m)^(BLOCKED:.+)') {
                $blocker = $Matches[1]
                $ts2     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $nl      = [System.Environment]::NewLine
                Write-Host "  [$sid] $blocker"
                Add-Content -Path $Progress -Value ($nl + "## Blocker [$sid] - $ts2" + $nl + $nl + $blocker + $nl)
            } else {
                Write-Host "  [$sid] WARNING: No signal found."
            }
        }

        foreach ($sid in $jobs.Keys) { Remove-Job $jobs[$sid] -Force }

    # -------------------------------------------------------------------------
    # SERIAL MODE
    # -------------------------------------------------------------------------
    } else {
        $Log    = Join-Path $LogsDir "ratchet-$ts.log"
        Write-Host "Log: $Log"
        $Trigger = $AuthPrefix + 'You are running inside the Ratchet agent loop. Read CLAUDE.md for your full operating protocol, then work through the next incomplete story in .ratchet/prd.json.'

        Push-Location $ProjectDir
        try {
            Invoke-Expression "$Invoke --tool '$Tool' --prompt '$Trigger'" 2>&1 |
                Tee-Object -FilePath $Log -Append
        } catch {
            Write-Host "WARNING: Invoke exited with error: $_"
        } finally {
            Pop-Location
        }

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
            Write-Host 'WARNING: No COMPLETE or BLOCKED signal found. Continuing...'
            Add-Content -Path $Log -Value 'WARNING: No COMPLETE or BLOCKED signal found.'
        }
    }
}

Write-Host "=== Max iterations ($MaxIter) reached without full completion ==="
exit 1

@echo off
REM ratchet_state.bat -- Windows wrapper for ratchet_state.py
REM Usage: ratchet_state <subcommand> [options]
REM        ratchet_state init --name "feature-name"
REM        ratchet_state status
REM        ratchet_state add-story
REM        ratchet_state reset --story S1

setlocal

REM Try python, then python3
where python >nul 2>&1 && (
    python "%~dp0ratchet_state.py" %*
    exit /b %ERRORLEVEL%
)
where python3 >nul 2>&1 && (
    python3 "%~dp0ratchet_state.py" %*
    exit /b %ERRORLEVEL%
)

echo ERROR: python or python3 not found in PATH >&2
exit /b 1

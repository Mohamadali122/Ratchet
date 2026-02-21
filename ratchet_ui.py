#!/usr/bin/env python3
"""ratchet_ui.py -- Ratchet Web UI Dashboard.

Real-time browser dashboard for monitoring and controlling the Ratchet loop.

Usage:
  python ratchet_ui.py                         # serve on http://localhost:7433
  python ratchet_ui.py --port 8080             # custom port
  python ratchet_ui.py --project-dir /srv/app  # point at a project

Install dependencies:
  pip install fastapi uvicorn
  pip install openai   # only needed for openai/deepseek/lmstudio providers

The UI auto-detects the .ratchet/ directory from --project-dir (default: cwd).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, AsyncGenerator, Optional

try:
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, StreamingResponse
    import uvicorn
except ImportError:
    print("ERROR: Missing dependencies. Run: pip install fastapi uvicorn", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

PROJECT_DIR: Path = Path(".")
RATCHET_DIR: Path = Path(".ratchet")
LOGS_DIR: Path = Path("logs")

app = FastAPI(title="Ratchet Dashboard", version="1.0.0")

TEMPLATES_DIR = Path(__file__).parent / "templates"

# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

def _prd_path() -> Path:
    return PROJECT_DIR / ".ratchet" / "prd.json"


def _load_prd() -> dict[str, Any]:
    p = _prd_path()
    if not p.exists():
        return {"name": "No project", "branchName": "-", "stories": []}
    with p.open() as f:
        return json.load(f)


def _story_ready(story: dict[str, Any], idx: dict[str, dict[str, Any]]) -> bool:
    if story.get("passes"):
        return False
    deps = story.get("depends_on", [])
    return all(idx.get(dep, {}).get("passes") for dep in deps)


def _enrich_stories(stories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    idx = {s["id"]: s for s in stories}
    out = []
    for s in stories:
        s = dict(s)
        if s.get("passes"):
            s["_status"] = "done"
        elif _story_ready(s, idx):
            s["_status"] = "ready"
        else:
            s["_status"] = "waiting"
        out.append(s)
    return out


def _latest_log() -> Optional[Path]:
    logs = sorted(LOGS_DIR.glob("ratchet-*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return logs[0] if logs else None


# ---------------------------------------------------------------------------
# Loop process management
# ---------------------------------------------------------------------------

_loop_proc: Optional[subprocess.Popen] = None  # type: ignore[type-arg]


def _loop_running() -> bool:
    global _loop_proc
    if _loop_proc is None:
        return False
    return _loop_proc.poll() is None


# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
async def dashboard() -> FileResponse:
    return FileResponse(TEMPLATES_DIR / "index.html")


@app.get("/api/status")
async def api_status() -> JSONResponse:
    prd = _load_prd()
    stories = _enrich_stories(prd.get("stories", []))
    done    = sum(1 for s in stories if s.get("passes"))
    total   = len(stories)
    ready   = sum(1 for s in stories if s.get("_status") == "ready")
    return JSONResponse({
        "name":         prd.get("name", "-"),
        "branch":       prd.get("branchName", "-"),
        "done":         done,
        "total":        total,
        "ready":        ready,
        "loop_running": _loop_running(),
        "stories":      stories,
    })


@app.post("/api/stories/{story_id}/reset")
async def reset_story(story_id: str) -> JSONResponse:
    python = "python3" if Path("/usr/bin/python3").exists() else "python"
    state  = str(PROJECT_DIR / "ratchet_state.py")
    result = subprocess.run(
        [python, state, "reset", "--story", story_id],
        cwd=str(PROJECT_DIR), capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise HTTPException(status_code=400, detail=result.stderr)
    return JSONResponse({"ok": True, "message": result.stdout.strip()})


@app.post("/api/run")
async def run_loop(request: Request) -> JSONResponse:
    global _loop_proc
    if _loop_running():
        return JSONResponse({"ok": False, "message": "Loop already running"})

    body    = await request.json()
    tool    = body.get("tool", "claude")
    max_iter = int(body.get("max_iter", 20))
    parallel = body.get("parallel", False)

    ratchet_sh = PROJECT_DIR / "ratchet.sh"
    cmd = ["bash", str(ratchet_sh), "--tool", tool, "--max-iter", str(max_iter), "--project-dir", str(PROJECT_DIR)]
    if parallel:
        cmd.append("--parallel")

    log_path = LOGS_DIR / f"ratchet-ui-{datetime.now().strftime('%Y%m%dT%H%M%S')}.log"
    log_path.parent.mkdir(exist_ok=True)
    log_file = open(log_path, "w")  # noqa: WPS515

    _loop_proc = subprocess.Popen(cmd, stdout=log_file, stderr=log_file, cwd=str(PROJECT_DIR))
    return JSONResponse({"ok": True, "message": f"Loop started (PID {_loop_proc.pid})", "log": str(log_path)})


@app.post("/api/stop")
async def stop_loop() -> JSONResponse:
    global _loop_proc
    if not _loop_running():
        return JSONResponse({"ok": False, "message": "No loop running"})
    _loop_proc.terminate()  # type: ignore[union-attr]
    return JSONResponse({"ok": True, "message": "Loop stopped"})


@app.get("/api/logs/stream")
async def stream_logs() -> StreamingResponse:
    async def _generator() -> AsyncGenerator[str, None]:
        log = _latest_log()
        if log is None:
            yield "data: No log files found yet.\n\n"
            return

        with log.open("r", errors="replace") as f:
            f.seek(0, 2)  # seek to end
            while True:
                line = f.readline()
                if line:
                    yield f"data: {line.rstrip()}\n\n"
                else:
                    await asyncio.sleep(0.4)

    return StreamingResponse(_generator(), media_type="text/event-stream")


@app.get("/api/logs/tail")
async def tail_log(n: int = 60) -> JSONResponse:
    log = _latest_log()
    if log is None:
        return JSONResponse({"lines": [], "file": None})
    lines = log.read_text(errors="replace").splitlines()
    return JSONResponse({"lines": lines[-n:], "file": str(log)})


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    global PROJECT_DIR, RATCHET_DIR, LOGS_DIR

    parser = argparse.ArgumentParser(prog="ratchet_ui.py", description="Ratchet Web UI Dashboard")
    parser.add_argument("--port",        type=int, default=7433,  help="Port to listen on (default: 7433)")
    parser.add_argument("--host",        default="127.0.0.1",     help="Host to bind (default: 127.0.0.1)")
    parser.add_argument("--project-dir", default=".",             help="Project directory (default: cwd)")
    args = parser.parse_args()

    PROJECT_DIR  = Path(args.project_dir).resolve()
    RATCHET_DIR  = PROJECT_DIR / ".ratchet"
    LOGS_DIR     = PROJECT_DIR / "logs"

    print(f"Ratchet Dashboard -> http://{args.host}:{args.port}")
    print(f"Project dir: {PROJECT_DIR}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()

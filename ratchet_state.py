#!/usr/bin/env python3
"""ratchet_state.py -- Ratchet state management CLI.

Manages .ratchet/ directory: prd.json (task list) and progress.md (cross-iteration memory).
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

RATCHET_DIR = Path(".ratchet")
PRD_FILE = RATCHET_DIR / "prd.json"
PROGRESS_FILE = RATCHET_DIR / "progress.md"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_prd() -> dict[str, Any]:
    if not PRD_FILE.exists():
        print(f"ERROR: {PRD_FILE} not found. Run `ratchet_state.py init --name <name>` first.", file=sys.stderr)
        sys.exit(1)
    with PRD_FILE.open() as f:
        return json.load(f)  # type: ignore[no-any-return]


def _save_prd(prd: dict[str, Any]) -> None:
    PRD_FILE.write_text(json.dumps(prd, indent=2) + "\n")


def _story_index(stories: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {s["id"]: s for s in stories}


def _ready_stories(stories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return stories that are not done and whose dependencies are all satisfied."""
    idx = _story_index(stories)
    ready = []
    for story in stories:
        if story.get("passes"):
            continue
        deps = story.get("depends_on", [])
        if all(idx.get(dep, {}).get("passes") for dep in deps):
            ready.append(story)
    return ready


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def init_cmd(args: argparse.Namespace) -> None:
    """Scaffold .ratchet/ with prd.json and progress.md."""
    RATCHET_DIR.mkdir(exist_ok=True)

    if PRD_FILE.exists():
        print(f"WARNING: {PRD_FILE} already exists -- skipping overwrite.")
    else:
        prd: dict[str, Any] = {
            "name": args.name,
            "branchName": f"feat/{args.name}",
            "stories": [],
        }
        _save_prd(prd)
        print(f"Created {PRD_FILE}")

    if not PROGRESS_FILE.exists():
        PROGRESS_FILE.write_text(
            f"# Progress: {args.name}\n\nInitialized: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        )
        print(f"Created {PROGRESS_FILE}")

    print("\nNext steps:")
    print("  ./ratchet_state.py add-story   # add stories with acceptance criteria")
    print("  ./ratchet_state.py status      # review before running")
    print("  ./ratchet.sh --project-dir .   # start the agent loop")


def status_cmd(_args: argparse.Namespace) -> None:
    """Pretty-print story completion table."""
    prd = _load_prd()
    stories: list[dict[str, Any]] = prd.get("stories", [])

    print(f"\nProject : {prd.get('name', 'unknown')}")
    print(f"Branch  : {prd.get('branchName', '-')}")
    print()

    if not stories:
        print("No stories yet. Run `ratchet_state.py add-story` to add one.")
        return

    ready = {s["id"] for s in _ready_stories(stories)}

    col_id    = max(len("ID"),    *(len(s.get("id",    "")) for s in stories))
    col_title = max(len("Title"), *(len(s.get("title", "")) for s in stories), 40)
    col_model = max(len("Model"), *(len(s.get("model", "-")) for s in stories), 8)

    header = f"{'ID':<{col_id}}  {'Status':<7}  {'Title':<{col_title}}  {'Model':<{col_model}}  Deps"
    print(header)
    print("-" * (len(header) + 10))

    for story in stories:
        sid   = story.get("id", "-")
        title = story.get("title", "-")
        model = story.get("model", "-")
        deps  = ", ".join(story.get("depends_on", [])) or "-"

        if story.get("passes"):
            mark = "DONE   "
        elif sid in ready:
            mark = "READY  "
        else:
            mark = "WAITING"

        print(f"{sid:<{col_id}}  {mark:<7}  {title:<{col_title}}  {model:<{col_model}}  {deps}")

    done  = sum(1 for s in stories if s.get("passes"))
    total = len(stories)
    rdy   = len(ready)
    print(f"\n{done}/{total} complete -- {rdy} ready to run")


def add_story_cmd(_args: argparse.Namespace) -> None:
    """Interactively add a story with acceptance criteria."""
    prd = _load_prd()
    stories: list[dict[str, Any]] = prd.get("stories", [])

    existing_ids = {s.get("id") for s in stories}
    default_id = f"S{len(stories) + 1}"
    while default_id in existing_ids:
        default_id = f"S{int(default_id[1:]) + 1}"

    print("\n--- Add Story ---")
    story_id = input(f"ID [{default_id}]: ").strip() or default_id
    title = input("Title: ").strip()
    if not title:
        print("ERROR: Title is required.", file=sys.stderr)
        sys.exit(1)

    print("Acceptance criteria (one per line, blank line to finish):")
    criteria: list[str] = []
    while True:
        line = input(f"  {len(criteria) + 1}. ").strip()
        if not line:
            break
        criteria.append(line)

    # Dependencies
    if stories:
        dep_input = input("Depends on (comma-separated IDs e.g. S1,S2 -- blank for none): ").strip()
        depends_on = [d.strip() for d in dep_input.split(",") if d.strip()] if dep_input else []
    else:
        depends_on = []

    # Model override
    model_input = input("Model override (e.g. ollama/codellama, blank = loop default): ").strip()

    story: dict[str, Any] = {
        "id": story_id,
        "title": title,
        "acceptance_criteria": criteria,
        "passes": False,
    }
    if depends_on:
        story["depends_on"] = depends_on
    if model_input:
        story["model"] = model_input

    stories.append(story)
    prd["stories"] = stories
    _save_prd(prd)
    print(f"\nAdded {story_id}: {title}")


def reset_cmd(args: argparse.Namespace) -> None:
    """Reset a story to passes: false."""
    prd = _load_prd()
    stories: list[dict[str, Any]] = prd.get("stories", [])

    for story in stories:
        if story.get("id") == args.story:
            story["passes"] = False
            prd["stories"] = stories
            _save_prd(prd)
            print(f"Reset {args.story} -> passes: false")
            return

    print(f"ERROR: Story '{args.story}' not found.", file=sys.stderr)
    sys.exit(1)


def ready_cmd(_args: argparse.Namespace) -> None:
    """Print IDs of stories ready to run (deps satisfied, not yet done)."""
    prd = _load_prd()
    stories: list[dict[str, Any]] = prd.get("stories", [])
    for s in _ready_stories(stories):
        print(s["id"])


def mark_done_cmd(args: argparse.Namespace) -> None:
    """Mark a story as passes: true (used by orchestrator in parallel mode)."""
    prd = _load_prd()
    stories: list[dict[str, Any]] = prd.get("stories", [])
    for story in stories:
        if story.get("id") == args.story:
            story["passes"] = True
            prd["stories"] = stories
            _save_prd(prd)
            print(f"Marked {args.story} -> passes: true")
            return
    print(f"ERROR: Story '{args.story}' not found.", file=sys.stderr)
    sys.exit(1)


def doctor_cmd(_args: argparse.Namespace) -> None:
    """Preflight environment check."""
    print("\n--- Ratchet Doctor ---\n")
    ok = True

    def check(label: str, passed: bool, hint: str = "") -> None:
        nonlocal ok
        status = "OK  " if passed else "FAIL"
        print(f"  [{status}] {label}")
        if not passed:
            ok = False
            if hint:
                print(f"         -> {hint}")

    # claude CLI
    check(
        "claude CLI installed",
        shutil.which("claude") is not None,
        "Install: npm install -g @anthropic-ai/claude-code",
    )

    try:
        result = subprocess.run(["claude", "--version"], capture_output=True, timeout=5)
        check("claude CLI responsive", result.returncode == 0, "Run: claude auth")
    except Exception:
        check("claude CLI responsive", False, "Run: claude auth")

    check("python available", shutil.which("python3") is not None or shutil.which("python") is not None)
    check("git installed", shutil.which("git") is not None)

    try:
        name  = subprocess.run(["git", "config", "user.name"],  capture_output=True, text=True).stdout.strip()
        email = subprocess.run(["git", "config", "user.email"], capture_output=True, text=True).stdout.strip()
        check("git user.name set",  bool(name),  "Run: git config user.name 'Your Name'")
        check("git user.email set", bool(email), "Run: git config user.email 'you@example.com'")
    except Exception:
        check("git identity", False, "git not found or not configured")

    check(".ratchet/prd.json exists", PRD_FILE.exists(), "Run: ratchet_state.py init --name <name>")

    if PRD_FILE.exists():
        try:
            prd = _load_prd()
            check(".ratchet/prd.json valid JSON", isinstance(prd.get("stories"), list))
        except Exception:
            check(".ratchet/prd.json valid JSON", False, "Fix JSON syntax in .ratchet/prd.json")

    check(".ratchet/verify.json exists", (RATCHET_DIR / "verify.json").exists())
    check("CLAUDE.md present in cwd", Path("CLAUDE.md").exists(), "Copy from Ratchet install directory")

    print("\n  Optional tools:")
    for tool, hint in [
        ("docker",     "https://docs.docker.com/get-docker/"),
        ("nginx",      "sudo apt install nginx"),
        ("curl",       "sudo apt install curl"),
        ("shellcheck", "sudo apt install shellcheck"),
        ("mypy",       "pip install mypy"),
        ("ollama",     "https://ollama.com/download"),
        ("gemini",     "npm install -g @google/gemini-cli"),
        ("codex",      "npm install -g @openai/codex"),
    ]:
        flag = "OK  " if shutil.which(tool) else "n/a "
        print(f"  [{flag}] {tool}")

    print()
    if ok:
        print("  All required checks passed. Ready to run Ratchet.\n")
    else:
        print("  Some checks failed. Fix the issues above before running.\n")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        prog="ratchet_state.py",
        description="Ratchet state management CLI -- manages .ratchet/prd.json and progress.md",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init", help="Scaffold .ratchet/ directory")
    p_init.add_argument("--name", required=True, help="Feature/project name (e.g. auth-service)")
    p_init.set_defaults(func=init_cmd)

    p_status = sub.add_parser("status", help="Show story completion table")
    p_status.set_defaults(func=status_cmd)

    p_add = sub.add_parser("add-story", help="Interactively add a story")
    p_add.set_defaults(func=add_story_cmd)

    p_reset = sub.add_parser("reset", help="Reset a story to passes: false")
    p_reset.add_argument("--story", required=True, metavar="ID")
    p_reset.set_defaults(func=reset_cmd)

    p_ready = sub.add_parser("ready-stories", help="Print IDs of stories ready to run")
    p_ready.set_defaults(func=ready_cmd)

    p_done = sub.add_parser("mark-done", help="Mark a story passes: true (parallel orchestrator)")
    p_done.add_argument("--story", required=True, metavar="ID")
    p_done.set_defaults(func=mark_done_cmd)

    p_doc = sub.add_parser("doctor", help="Preflight environment check")
    p_doc.set_defaults(func=doctor_cmd)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

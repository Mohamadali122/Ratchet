#!/usr/bin/env python3
"""ratchet_state.py — Ratchet state management CLI.

Manages .ratchet/ directory: prd.json (task list) and progress.md (cross-iteration memory).
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

RATCHET_DIR = Path(".ratchet")
PRD_FILE = RATCHET_DIR / "prd.json"
PROGRESS_FILE = RATCHET_DIR / "progress.md"


def _load_prd() -> dict[str, Any]:
    if not PRD_FILE.exists():
        print(f"ERROR: {PRD_FILE} not found. Run `ratchet_state.py init --name <name>` first.", file=sys.stderr)
        sys.exit(1)
    with PRD_FILE.open() as f:
        return json.load(f)  # type: ignore[no-any-return]


def _save_prd(prd: dict[str, Any]) -> None:
    PRD_FILE.write_text(json.dumps(prd, indent=2) + "\n")


def init_cmd(args: argparse.Namespace) -> None:
    """Scaffold .ratchet/ with prd.json and progress.md."""
    RATCHET_DIR.mkdir(exist_ok=True)

    if PRD_FILE.exists():
        print(f"WARNING: {PRD_FILE} already exists — skipping overwrite.")
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

    print(f"\nNext steps:")
    print(f"  ./ratchet_state.py add-story   # add stories with acceptance criteria")
    print(f"  ./ratchet_state.py status      # review before running")
    print(f"  ./ratchet.sh --project-dir .   # start the agent loop")


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

    col_id = max(len("ID"), *(len(s.get("id", "")) for s in stories))
    col_title = max(len("Title"), *(len(s.get("title", "")) for s in stories), 40)

    header = f"{'ID':<{col_id}}  {'Pass':<5}  {'Title':<{col_title}}"
    print(header)
    print("-" * len(header))

    for story in stories:
        mark = "✓" if story.get("passes") else "✗"
        sid = story.get("id", "-")
        title = story.get("title", "-")
        print(f"{sid:<{col_id}}  {mark:<5}  {title:<{col_title}}")

    done = sum(1 for s in stories if s.get("passes"))
    total = len(stories)
    print(f"\n{done}/{total} complete")


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

    story: dict[str, Any] = {
        "id": story_id,
        "title": title,
        "acceptance_criteria": criteria,
        "passes": False,
    }
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
    p_reset.add_argument("--story", required=True, metavar="ID", help="Story ID (e.g. S2)")
    p_reset.set_defaults(func=reset_cmd)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

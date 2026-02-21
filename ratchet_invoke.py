#!/usr/bin/env python3
"""ratchet_invoke.py -- Multi-LLM adapter for Ratchet.

Normalises invocation across Claude, Codex, Gemini, Ollama,
OpenAI, DeepSeek, and LM Studio so ratchet.sh / ratchet.ps1
never need to know the calling convention of each provider.

Tool format
-----------
  claude              Claude Code CLI
  codex               OpenAI Codex CLI
  gemini              Google Gemini CLI
  gemini/gemini-2.0   Gemini CLI with a specific model flag
  ollama/codellama    Ollama with a local model name
  openai/gpt-4o       OpenAI API (requires OPENAI_API_KEY)
  deepseek            DeepSeek API (requires DEEPSEEK_API_KEY)
  deepseek/deepseek-coder  DeepSeek API with model override
  lmstudio            LM Studio local server (localhost:1234)
  lmstudio/mistral    LM Studio with specific loaded model

Usage
-----
  python ratchet_invoke.py --tool claude          --prompt "..."
  python ratchet_invoke.py --tool ollama/codellama --prompt "..."
  python ratchet_invoke.py --tool openai/gpt-4o   --prompt "..."
  python ratchet_invoke.py --list-tools
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Provider registry
# ---------------------------------------------------------------------------

PROVIDERS: dict[str, str] = {
    "claude":    "Claude Code CLI  (claude --dangerously-skip-permissions -p)",
    "codex":     "OpenAI Codex CLI (codex -p)",
    "gemini":    "Google Gemini CLI (gemini -p)",
    "ollama":    "Ollama local models (ollama run <model>)",
    "openai":    "OpenAI API -- requires OPENAI_API_KEY",
    "deepseek":  "DeepSeek API -- requires DEEPSEEK_API_KEY",
    "lmstudio":  "LM Studio local server at localhost:1234",
}


def _parse_tool(tool: str) -> tuple[str, str]:
    """Split 'provider/model' into (provider, model). Model may be empty."""
    parts = tool.split("/", 1)
    provider = parts[0].lower()
    model = parts[1] if len(parts) > 1 else ""
    return provider, model


# ---------------------------------------------------------------------------
# CLI-based providers (subprocess)
# ---------------------------------------------------------------------------

def _run(cmd: list[str]) -> int:
    return subprocess.call(cmd)


def invoke_claude(model: str, prompt: str) -> int:
    """Claude Code CLI."""
    cmd = ["claude", "--dangerously-skip-permissions", "-p", prompt]
    return _run(cmd)


def invoke_codex(model: str, prompt: str) -> int:
    """OpenAI Codex CLI."""
    cmd = ["codex", "-p", prompt]
    return _run(cmd)


def invoke_gemini(model: str, prompt: str) -> int:
    """Google Gemini CLI."""
    cmd = ["gemini"]
    if model:
        cmd += ["--model", model]
    cmd += ["-p", prompt]
    return _run(cmd)


def invoke_ollama(model: str, prompt: str) -> int:
    """Ollama local model runner."""
    model = model or "codellama"
    return _run(["ollama", "run", model, prompt])


# ---------------------------------------------------------------------------
# API-based providers (openai SDK, OpenAI-compatible)
# ---------------------------------------------------------------------------

def _openai_client(base_url: Optional[str], api_key: str) -> "openai.OpenAI":  # type: ignore[name-defined]
    try:
        import openai  # type: ignore[import]
    except ImportError:
        print("ERROR: openai package not installed. Run: pip install openai", file=sys.stderr)
        sys.exit(1)

    kwargs: dict = {"api_key": api_key}
    if base_url:
        kwargs["base_url"] = base_url
    return openai.OpenAI(**kwargs)


def _api_invoke(client: "openai.OpenAI", model: str, prompt: str, context: str = "") -> int:  # type: ignore[name-defined]
    """Send prompt + optional system context to an OpenAI-compatible endpoint."""
    messages = []
    if context:
        messages.append({"role": "system", "content": context})
    messages.append({"role": "user", "content": prompt})

    try:
        response = client.chat.completions.create(model=model, messages=messages)
        print(response.choices[0].message.content)
        return 0
    except Exception as exc:
        print(f"ERROR: API call failed: {exc}", file=sys.stderr)
        return 1


def _load_claude_md() -> str:
    """Read CLAUDE.md from cwd to give API-based models the operating protocol."""
    path = Path("CLAUDE.md")
    if path.exists():
        return path.read_text(encoding="utf-8")
    return ""


def invoke_openai(model: str, prompt: str) -> int:
    """OpenAI API (gpt-4o, gpt-4-turbo, gpt-3.5-turbo, ...)."""
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        print("ERROR: OPENAI_API_KEY environment variable not set.", file=sys.stderr)
        return 1
    model = model or "gpt-4o"
    client = _openai_client(None, api_key)
    return _api_invoke(client, model, prompt, _load_claude_md())


def invoke_deepseek(model: str, prompt: str) -> int:
    """DeepSeek API (deepseek-coder, deepseek-chat, ...)."""
    api_key = os.environ.get("DEEPSEEK_API_KEY", "")
    if not api_key:
        print("ERROR: DEEPSEEK_API_KEY environment variable not set.", file=sys.stderr)
        return 1
    model = model or "deepseek-coder"
    client = _openai_client("https://api.deepseek.com", api_key)
    return _api_invoke(client, model, prompt, _load_claude_md())


def invoke_lmstudio(model: str, prompt: str) -> int:
    """LM Studio local server (OpenAI-compatible at localhost:1234)."""
    model = model or "local-model"
    client = _openai_client("http://localhost:1234/v1", "lm-studio")
    return _api_invoke(client, model, prompt, _load_claude_md())


# ---------------------------------------------------------------------------
# Dispatch table
# ---------------------------------------------------------------------------

_DISPATCH = {
    "claude":   invoke_claude,
    "codex":    invoke_codex,
    "gemini":   invoke_gemini,
    "ollama":   invoke_ollama,
    "openai":   invoke_openai,
    "deepseek": invoke_deepseek,
    "lmstudio": invoke_lmstudio,
}


def invoke(tool: str, prompt: str) -> int:
    provider, model = _parse_tool(tool)
    fn = _DISPATCH.get(provider)
    if fn is None:
        print(f"ERROR: Unknown provider '{provider}'.", file=sys.stderr)
        print(f"Supported: {', '.join(PROVIDERS)}", file=sys.stderr)
        return 1
    return fn(model, prompt)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        prog="ratchet_invoke.py",
        description="Multi-LLM adapter -- invoke any supported AI tool with a unified interface.",
    )
    parser.add_argument(
        "--tool", "-t",
        default="claude",
        help="Provider (and optional model) e.g. claude, ollama/codellama, openai/gpt-4o",
    )
    parser.add_argument(
        "--prompt", "-p",
        default="",
        help="Prompt text to send to the model",
    )
    parser.add_argument(
        "--list-tools",
        action="store_true",
        help="Print supported providers and exit",
    )

    args = parser.parse_args()

    if args.list_tools:
        print("\nSupported Ratchet providers:\n")
        for key, desc in PROVIDERS.items():
            print(f"  {key:<12} {desc}")
        print()
        return

    if not args.prompt:
        parser.error("--prompt is required")

    sys.exit(invoke(args.tool, args.prompt))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compatibility wrapper for older replay configs that used a claim-specific context validator name."""

import runpy
from pathlib import Path


if __name__ == "__main__":
    target = Path(__file__).with_name("validate_replay_context_index.py")
    runpy.run_path(str(target), run_name="__main__")

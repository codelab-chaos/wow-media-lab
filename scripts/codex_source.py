"""Where the Codex of Azeroth is: the sibling project that reads the game's
data (github.com/codelab-chaos/codex-of-azeroth). MediaLab's build scripts use
its database and its CASC reader; the addon itself never needs it.

CODEX_DIR, or ../codex-of-azeroth next to this repo.
"""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def folder():
    path = Path(os.environ.get("CODEX_DIR") or ROOT.parent / "codex-of-azeroth")
    if not (path / "codex" / "__init__.py").is_file():
        sys.exit(f"Codex of Azeroth not found at {path}; clone it there or set CODEX_DIR.")
    return path


def database():
    path = folder() / "data" / "codex.sqlite"
    if not path.is_file():
        sys.exit(f"{path} missing; run `python3 -m codex` in the Codex of Azeroth first.")
    return path


def store():
    """The game's local storage, through the codex's CASC reader."""
    sys.path.insert(0, str(folder()))
    from codex.casc import Casc
    from codex.config import game_root
    return Casc(game_root(ROOT))

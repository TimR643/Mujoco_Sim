from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def load_config(path: str | Path) -> dict[str, Any]:
    path = Path(path).expanduser()
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def package_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_config_path() -> Path:
    return package_root() / "configs" / "perfect_pick.yaml"

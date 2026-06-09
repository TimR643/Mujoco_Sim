from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np


@dataclass(frozen=True)
class DatasetMetadata:
    repo_id: str
    task: str
    fps: int
    camera_names: tuple[str, ...]
    joint_names: tuple[str, ...]


class LocalLeRobotEpisodeWriter:
    """Local LeRobot boundary writer for deterministic verification episodes.

    The recorder deliberately keeps the data boundary simple and explicit:
    numerical streams are stored in compressed NumPy files and the metadata uses
    LeRobot-style names (`observation.state`, `observation.images.*`, `action`).
    If your installed LeRobot version requires Parquet/MP4 Hub storage, convert
    this directory after verification without changing the Polymetis control path.
    """

    def __init__(self, root: Path, metadata: DatasetMetadata) -> None:
        self.root = Path(root).expanduser()
        self.metadata = metadata
        self.meta_dir = self.root / "meta"
        self.episodes_dir = self.root / "episodes"
        self.meta_dir.mkdir(parents=True, exist_ok=True)
        self.episodes_dir.mkdir(parents=True, exist_ok=True)
        self._write_static_metadata()

    def write_episode(self, episode_index: int, frames: list[dict[str, Any]]) -> Path:
        if not frames:
            raise ValueError("Cannot write an empty episode.")
        episode_path = self.episodes_dir / f"episode_{episode_index:06d}.npz"
        arrays: dict[str, np.ndarray] = {
            "timestamp": np.asarray([frame["timestamp"] for frame in frames], dtype=np.float64),
            "observation.state": np.asarray([frame["observation.state"] for frame in frames], dtype=np.float32),
            "action": np.asarray([frame["action"] for frame in frames], dtype=np.float32),
        }
        for camera_name in self.metadata.camera_names:
            key = f"observation.images.{camera_name}"
            images = [frame.get(key) for frame in frames]
            valid_images = [image for image in images if image is not None]
            if valid_images:
                arrays[key] = np.stack(valid_images).astype(np.uint8)
        np.savez_compressed(episode_path, **arrays)
        self._append_episode_metadata(episode_index, len(frames), episode_path)
        self._write_stats(frames)
        return episode_path

    def _write_static_metadata(self) -> None:
        features: dict[str, Any] = {
            "observation.state": {
                "dtype": "float32",
                "shape": [len(self.metadata.joint_names)],
                "names": list(self.metadata.joint_names),
            },
            "action": {
                "dtype": "float32",
                "shape": [len(self.metadata.joint_names)],
                "names": list(self.metadata.joint_names),
            },
        }
        for camera_name in self.metadata.camera_names:
            features[f"observation.images.{camera_name}"] = {
                "dtype": "uint8",
                "shape": ["time", "height", "width", "channels"],
            }
        info = {
            "codebase_version": "local-polymetis-gello-compatible-perfect-pick",
            "repo_id": self.metadata.repo_id,
            "fps": self.metadata.fps,
            "video": False,
            "encoding": "npz",
            "features": features,
            "created_at_unix_s": time.time(),
        }
        (self.meta_dir / "info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
        (self.meta_dir / "tasks.jsonl").write_text(
            json.dumps({"task_index": 0, "task": self.metadata.task}) + "\n", encoding="utf-8"
        )

    def _append_episode_metadata(self, episode_index: int, length: int, episode_path: Path) -> None:
        with (self.meta_dir / "episodes.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(
                json.dumps(
                    {
                        "episode_index": episode_index,
                        "tasks": [0],
                        "length": length,
                        "file": str(episode_path.relative_to(self.root)),
                    }
                )
                + "\n"
            )

    def _write_stats(self, frames: list[dict[str, Any]]) -> None:
        states = np.asarray([frame["observation.state"] for frame in frames], dtype=np.float32)
        actions = np.asarray([frame["action"] for frame in frames], dtype=np.float32)
        stats = {
            "observation.state": _stats(states),
            "action": _stats(actions),
        }
        (self.meta_dir / "stats.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")


def _stats(array: np.ndarray) -> dict[str, list[float]]:
    return {
        "mean": array.mean(axis=0).tolist(),
        "std": array.std(axis=0).tolist(),
        "min": array.min(axis=0).tolist(),
        "max": array.max(axis=0).tolist(),
    }

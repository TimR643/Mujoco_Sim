from __future__ import annotations

import time
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class TimedWaypoint:
    name: str
    duration_s: float
    joints: np.ndarray


class HardcodedPickAgent:
    """Deterministic GELLO replacement returning absolute Panda joint targets."""

    def __init__(self, waypoints: list[TimedWaypoint]) -> None:
        if not waypoints:
            raise ValueError("At least one waypoint is required.")
        self.waypoints = waypoints
        self.started_at: float | None = None

    @classmethod
    def from_config(cls, config: dict) -> "HardcodedPickAgent":
        waypoints = [
            TimedWaypoint(
                name=str(item["name"]),
                duration_s=float(item["duration_s"]),
                joints=np.asarray(item["joints"], dtype=np.float32),
            )
            for item in config["trajectory"]["waypoints"]
        ]
        return cls(waypoints)

    @property
    def total_duration_s(self) -> float:
        return float(sum(waypoint.duration_s for waypoint in self.waypoints))

    def reset(self) -> None:
        self.started_at = time.monotonic()

    def act(self, _obs: dict) -> np.ndarray:
        if self.started_at is None:
            self.reset()
        assert self.started_at is not None
        elapsed = time.monotonic() - self.started_at
        previous = self.waypoints[0].joints
        cursor = 0.0
        for waypoint in self.waypoints:
            segment_end = cursor + waypoint.duration_s
            if elapsed <= segment_end:
                alpha = 1.0 if waypoint.duration_s <= 0 else np.clip((elapsed - cursor) / waypoint.duration_s, 0.0, 1.0)
                return previous + alpha * (waypoint.joints - previous)
            previous = waypoint.joints
            cursor = segment_end
        return self.waypoints[-1].joints.copy()

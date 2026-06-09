from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np


@dataclass(frozen=True)
class MockPandaConfig:
    home: tuple[float, ...]


class MockPandaRobot:
    """In-process Panda stand-in for pipeline smoke tests.

    This backend does not talk to MuJoCo or Polymetis. It lets users verify that
    config loading, hardcoded trajectory generation, dataset writing, and LeRobot
    observation/action naming work before a real Polymetis installation is
    available.
    """

    def __init__(self, config: MockPandaConfig) -> None:
        if len(config.home) != 8:
            raise ValueError(f"Mock Panda expects an 8-D home state, got {len(config.home)} values.")
        self._joint_state = np.asarray(config.home, dtype=np.float32)

    def num_dofs(self) -> int:
        return 8

    def get_joint_state(self) -> np.ndarray:
        return self._joint_state.copy()

    def command_joint_state(self, joint_state: np.ndarray) -> None:
        joint_state = np.asarray(joint_state, dtype=np.float32)
        if joint_state.shape != (8,):
            raise ValueError(f"Expected 8-D Panda+gripper command, got shape {joint_state.shape}.")
        self._joint_state = joint_state.copy()

    def get_observations(self) -> dict[str, Any]:
        joints = self.get_joint_state()
        return {
            "joint_positions": joints,
            "joint_velocities": np.zeros_like(joints),
            "ee_pos_quat": np.zeros(7, dtype=np.float32),
            "gripper_position": np.asarray([joints[-1]], dtype=np.float32),
        }

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

import numpy as np
import torch

MAX_OPEN_WIDTH_M = 0.09


@dataclass(frozen=True)
class PolymetisPandaConfig:
    robot_ip: str = "127.0.0.1"
    gripper_ip: str = "127.0.0.1"
    max_open_width_m: float = MAX_OPEN_WIDTH_M
    go_home_on_connect: bool = True
    start_joint_impedance: bool = True


class PolymetisPandaRobot:
    """GELLO-compatible Panda robot wrapper backed by Polymetis.

    This mirrors the `gello_software` Panda control path: observations and
    commands are 8-D vectors, with seven Franka joints followed by a normalized
    gripper command where 0.0 is open and 1.0 is closed.
    """

    def __init__(self, config: PolymetisPandaConfig) -> None:
        try:
            from polymetis import GripperInterface, RobotInterface
        except ModuleNotFoundError as exc:
            raise ModuleNotFoundError(
                "The 'polymetis' Python module is not installed in this environment. "
                "Polymetis is distributed through the FAIR robotics conda/source workflow, "
                "not as a normal dependency of this package. Install/activate your "
                "gello_software Polymetis environment before using ROBOT_BACKEND=polymetis. "
                "For a no-robot smoke test, run the recorder with ROBOT_BACKEND=mock "
                "and CAMERA_FLAG=--no-camera."
            ) from exc

        self.config = config
        self.robot = RobotInterface(ip_address=config.robot_ip)
        self.gripper = GripperInterface(ip_address=config.gripper_ip)
        if config.go_home_on_connect:
            self.robot.go_home()
        if config.start_joint_impedance:
            self.robot.start_joint_impedance()
        self.open_gripper(speed=255, force=255)
        time.sleep(1.0)

    def num_dofs(self) -> int:
        return 8

    def get_joint_state(self) -> np.ndarray:
        arm_joints = np.asarray(self.robot.get_joint_positions(), dtype=np.float32)
        width = float(self.gripper.get_state().width)
        normalized_closed = 1.0 - np.clip(width / self.config.max_open_width_m, 0.0, 1.0)
        return np.concatenate([arm_joints, np.asarray([normalized_closed], dtype=np.float32)])

    def command_joint_state(self, joint_state: np.ndarray) -> None:
        joint_state = np.asarray(joint_state, dtype=np.float32)
        if joint_state.shape != (8,):
            raise ValueError(f"Expected 8-D Panda+gripper command, got shape {joint_state.shape}.")
        self.robot.update_desired_joint_positions(torch.as_tensor(joint_state[:7], dtype=torch.float32))
        width = self.config.max_open_width_m * (1.0 - float(np.clip(joint_state[7], 0.0, 1.0)))
        self.gripper.goto(width=width, speed=1, force=1)

    def open_gripper(self, speed: float = 255, force: float = 255) -> None:
        self.gripper.goto(width=self.config.max_open_width_m, speed=speed, force=force)

    def get_observations(self) -> dict[str, Any]:
        joints = self.get_joint_state()
        return {
            "joint_positions": joints,
            "joint_velocities": np.zeros_like(joints),
            "ee_pos_quat": np.zeros(7, dtype=np.float32),
            "gripper_position": np.asarray([joints[-1]], dtype=np.float32),
        }

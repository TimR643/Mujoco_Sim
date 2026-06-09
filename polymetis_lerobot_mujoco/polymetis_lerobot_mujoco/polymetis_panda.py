from __future__ import annotations

import importlib
import importlib.util
import time
from dataclasses import dataclass
from typing import Any, TypeVar

import numpy as np
import torch

MAX_OPEN_WIDTH_M = 0.09
InterfaceT = TypeVar("InterfaceT")


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
        if importlib.util.find_spec("polymetis") is None:
            raise ModuleNotFoundError(
                "The 'polymetis' Python module is not installed in this environment. "
                "Polymetis is distributed through the FAIR robotics conda/source workflow, "
                "not as a normal dependency of this package. Install/activate your "
                "gello_software Polymetis environment before using ROBOT_BACKEND=polymetis. "
                "For a no-robot smoke test, run the recorder with ROBOT_BACKEND=mock "
                "and CAMERA_FLAG=--no-camera."
            )
        polymetis = importlib.import_module("polymetis")
        GripperInterface = polymetis.GripperInterface
        RobotInterface = polymetis.RobotInterface

        self.config = config
        print(
            "Connecting to Polymetis robot "
            f"at robot_ip={config.robot_ip!r}, gripper_ip={config.gripper_ip!r}."
        )
        self.robot = _connect_interface(RobotInterface, interface_name="robot", ip_address=config.robot_ip)
        self.gripper = _connect_interface(GripperInterface, interface_name="gripper", ip_address=config.gripper_ip)
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


def _connect_interface(interface_cls: type[InterfaceT], *, interface_name: str, ip_address: str) -> InterfaceT:
    try:
        return interface_cls(ip_address=ip_address)
    except Exception as exc:
        if _looks_like_grpc_unavailable(exc):
            raise ConnectionError(
                "Polymetis Python is installed, but the "
                f"{interface_name} endpoint at {ip_address!r} is not reachable. "
                "Start the MuJoCo/Polymetis server in another terminal first, or set "
                "polymetis.robot_ip / polymetis.gripper_ip in configs/perfect_pick.yaml "
                "to the host/IP where your gello_software Polymetis endpoint is listening. "
                "For a no-server smoke test, run with ROBOT_BACKEND=mock CAMERA_FLAG=--no-camera."
            ) from exc
        raise


def _looks_like_grpc_unavailable(exc: Exception) -> bool:
    details = f"{exc.__class__.__module__}.{exc.__class__.__name__}: {exc}"
    return "StatusCode.UNAVAILABLE" in details or "failed to connect to all addresses" in details

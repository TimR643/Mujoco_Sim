from __future__ import annotations

import argparse
import importlib
import time
from pathlib import Path
from typing import Any

import numpy as np
import torch

from polymetis_lerobot_mujoco.camera import OpenCVCamera, OpenCVCameraConfig
from polymetis_lerobot_mujoco.config import default_config_path, load_config
from polymetis_lerobot_mujoco.mock_panda import MockPandaConfig, MockPandaRobot
from polymetis_lerobot_mujoco.polymetis_panda import PolymetisPandaConfig, PolymetisPandaRobot


def main() -> None:
    parser = argparse.ArgumentParser(description="Roll out a LeRobot policy through Polymetis, not ROS 2.")
    parser.add_argument("--config", type=Path, default=default_config_path())
    parser.add_argument("--policy-path", required=True)
    parser.add_argument("--seconds", type=float, default=20.0)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--no-camera", action="store_true")
    parser.add_argument(
        "--robot-backend",
        choices=("polymetis", "mock"),
        default=None,
        help="Robot backend to use. Defaults to config robot_backend, then polymetis.",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    robot = _make_robot(config, args.robot_backend)
    camera = None if args.no_camera else _make_camera(config)
    policy = _load_policy(args.policy_path, args.device)
    fps = int(config["lerobot"]["fps"])
    period_s = 1.0 / fps
    max_delta = float(config["polymetis"]["max_joint_delta_per_step"])
    last_command = robot.get_joint_state()
    deadline = time.monotonic() + args.seconds

    while time.monotonic() < deadline:
        started = time.monotonic()
        obs = robot.get_observations()
        observation = _to_policy_observation(obs, camera, args.device)
        with torch.no_grad():
            selected = policy.select_action(observation)
        desired = _as_numpy_action(selected)
        command = _limit_delta(last_command, desired, max_delta)
        robot.command_joint_state(command)
        last_command = command
        elapsed = time.monotonic() - started
        time.sleep(max(0.0, period_s - elapsed))

    if camera is not None:
        camera.close()


def _make_robot(config: dict, backend_override: str | None):
    backend = backend_override or str(config.get("robot_backend", "polymetis"))
    if backend == "mock":
        print("Using mock Panda backend. This verifies the policy loop but does not control MuJoCo.")
        return MockPandaRobot(MockPandaConfig(home=tuple(float(value) for value in config["robot"]["home"])))
    if backend == "polymetis":
        return PolymetisPandaRobot(
            PolymetisPandaConfig(
                robot_ip=str(config["polymetis"]["robot_ip"]),
                gripper_ip=str(config["polymetis"]["gripper_ip"]),
                max_open_width_m=float(config["robot"]["max_open_width_m"]),
                go_home_on_connect=bool(config["polymetis"]["go_home_on_connect"]),
                start_joint_impedance=bool(config["polymetis"]["start_joint_impedance"]),
            )
        )
    raise ValueError(f"Unsupported robot backend: {backend!r}")


def _make_camera(config: dict) -> OpenCVCamera:
    camera_cfg = config["camera"]["wrist"]
    return OpenCVCamera(
        OpenCVCameraConfig(
            device=camera_cfg["device"],
            width=int(camera_cfg["width"]),
            height=int(camera_cfg["height"]),
            fps=int(camera_cfg["fps"]),
        )
    )


def _to_policy_observation(obs: dict[str, Any], camera: OpenCVCamera | None, device: str) -> dict[str, torch.Tensor]:
    observation = {
        "observation.state": torch.as_tensor(obs["joint_positions"], dtype=torch.float32, device=device).unsqueeze(0),
    }
    if camera is not None:
        image = camera.read_rgb()
        observation["observation.images.wrist"] = (
            torch.as_tensor(image, dtype=torch.float32, device=device).permute(2, 0, 1).unsqueeze(0) / 255.0
        )
    return observation


def _load_policy(policy_path: str, device: str):
    factory = importlib.import_module("lerobot.policies.factory")
    policy = factory.make_policy(policy_path)
    policy.to(device)
    policy.eval()
    return policy


def _as_numpy_action(action: Any) -> np.ndarray:
    if isinstance(action, torch.Tensor):
        action = action.detach().cpu().numpy()
    action = np.asarray(action, dtype=np.float32).reshape(-1)
    if action.shape[0] < 8:
        raise ValueError(f"Policy produced {action.shape[0]} values; expected at least 8.")
    return action[:8]


def _limit_delta(current: np.ndarray, desired: np.ndarray, max_delta: float) -> np.ndarray:
    delta = desired - current
    largest = float(np.abs(delta).max())
    if largest > max_delta:
        delta = delta / largest * max_delta
    return current + delta


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np

from polymetis_lerobot_mujoco.camera import OpenCVCamera, OpenCVCameraConfig
from polymetis_lerobot_mujoco.config import default_config_path, load_config
from polymetis_lerobot_mujoco.dataset_writer import DatasetMetadata, LocalLeRobotEpisodeWriter
from polymetis_lerobot_mujoco.polymetis_panda import PolymetisPandaConfig, PolymetisPandaRobot
from polymetis_lerobot_mujoco.trajectory import HardcodedPickAgent


def main() -> None:
    parser = argparse.ArgumentParser(description="Record a hardcoded Panda pick with the GELLO/Polymetis control path.")
    parser.add_argument("--config", type=Path, default=default_config_path())
    parser.add_argument("--episode-index", type=int, default=None)
    parser.add_argument("--no-camera", action="store_true", help="Record only state/action if the MuJoCo wrist stream is not exposed yet.")
    args = parser.parse_args()

    config = load_config(args.config)
    robot = _make_robot(config)
    camera = None if args.no_camera else _make_camera(config)
    agent = HardcodedPickAgent.from_config(config)
    lerobot_cfg = config["lerobot"]
    fps = int(lerobot_cfg["fps"])
    period_s = 1.0 / fps
    max_delta = float(config["polymetis"]["max_joint_delta_per_step"])

    print(f"Warmup for {lerobot_cfg['warmup_seconds']}s with Polymetis robot interface.")
    _sleep_with_rate(float(lerobot_cfg["warmup_seconds"]))
    agent.reset()
    frames: list[dict] = []
    deadline = time.monotonic() + agent.total_duration_s + float(lerobot_cfg["settle_seconds"])
    next_tick = time.monotonic()
    last_command = robot.get_joint_state()

    while time.monotonic() < deadline:
        now = time.monotonic()
        if now < next_tick:
            time.sleep(min(0.001, next_tick - now))
            continue
        obs = robot.get_observations()
        desired = agent.act(obs)
        command = _limit_delta(last_command, desired, max_delta)
        robot.command_joint_state(command)
        last_command = command
        frame = {
            "timestamp": time.time(),
            "observation.state": np.asarray(obs["joint_positions"], dtype=np.float32),
            "action": np.asarray(command, dtype=np.float32),
        }
        if camera is not None:
            frame["observation.images.wrist"] = camera.read_rgb()
        frames.append(frame)
        next_tick += period_s

    if camera is not None:
        camera.close()

    metadata = DatasetMetadata(
        repo_id=str(lerobot_cfg["repo_id"]),
        task=str(lerobot_cfg["task"]),
        fps=fps,
        camera_names=() if args.no_camera else ("wrist",),
        joint_names=tuple(config["robot"]["joint_names"]),
    )
    writer = LocalLeRobotEpisodeWriter(Path(lerobot_cfg["root"]), metadata)
    episode_index = int(lerobot_cfg["episode_index"] if args.episode_index is None else args.episode_index)
    episode_path = writer.write_episode(episode_index, frames)
    manifest = {
        "control_backend": "polymetis",
        "gello_equivalent_agent": "hardcoded_pick",
        "config": config,
        "episode": str(episode_path),
        "frames": len(frames),
    }
    (Path(lerobot_cfg["root"]).expanduser() / "record_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote Polymetis/GELLO-compatible episode to {episode_path}")


def _make_robot(config: dict) -> PolymetisPandaRobot:
    return PolymetisPandaRobot(
        PolymetisPandaConfig(
            robot_ip=str(config["polymetis"]["robot_ip"]),
            gripper_ip=str(config["polymetis"]["gripper_ip"]),
            max_open_width_m=float(config["robot"]["max_open_width_m"]),
            go_home_on_connect=bool(config["polymetis"]["go_home_on_connect"]),
            start_joint_impedance=bool(config["polymetis"]["start_joint_impedance"]),
        )
    )


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


def _limit_delta(current: np.ndarray, desired: np.ndarray, max_delta: float) -> np.ndarray:
    delta = desired - current
    largest = float(np.abs(delta).max())
    if largest > max_delta:
        delta = delta / largest * max_delta
    return current + delta


def _sleep_with_rate(seconds: float) -> None:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        time.sleep(0.01)


if __name__ == "__main__":
    main()

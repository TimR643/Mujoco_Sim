"""Wait until Polymetis robot and gripper endpoints are reachable."""

from __future__ import annotations

import argparse
import importlib
import importlib.util
import time


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--robot-ip", default="127.0.0.1", help="Polymetis robot server host/IP.")
    parser.add_argument("--gripper-ip", default="127.0.0.1", help="Polymetis gripper server host/IP.")
    parser.add_argument("--timeout-s", type=float, default=120.0, help="Maximum wait time in seconds.")
    parser.add_argument("--interval-s", type=float, default=2.0, help="Retry interval in seconds.")
    parser.add_argument("--skip-gripper", action="store_true", help="Only wait for RobotInterface.")
    args = parser.parse_args()

    if importlib.util.find_spec("polymetis") is None:
        raise SystemExit(
            "The 'polymetis' Python module is not available. Activate polymetis_py38 first."
        )

    polymetis = importlib.import_module("polymetis")
    deadline = time.monotonic() + args.timeout_s
    last_error = None

    print(
        f"Waiting for Polymetis robot={args.robot_ip} "
        f"gripper={args.gripper_ip if not args.skip_gripper else '<skipped>'} "
        f"for up to {args.timeout_s:.1f}s ...",
        flush=True,
    )

    while time.monotonic() < deadline:
        try:
            robot = polymetis.RobotInterface(ip_address=args.robot_ip)
            joint_positions = robot.get_joint_positions()
            print(f"robot connected: {joint_positions}", flush=True)
            if not args.skip_gripper:
                polymetis.GripperInterface(ip_address=args.gripper_ip)
                print("gripper connected", flush=True)
            print("Polymetis endpoints are ready.", flush=True)
            return
        except Exception as exc:  # noqa: BLE001 - surface final connection error below.
            last_error = exc
            print(f"Polymetis not ready yet: {exc}", flush=True)
            time.sleep(args.interval_s)

    raise SystemExit(
        "Timed out waiting for Polymetis endpoints. Start the MuJoCo-backed "
        "Polymetis robot/gripper server first, or update polymetis.robot_ip / "
        f"gripper_ip. Last error: {last_error}"
    )


if __name__ == "__main__":
    main()

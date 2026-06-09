"""Keep MuJoCo's generated robot description available during launch.

Some MuJoCo/ros2_control launch files generate ``/mujoco_robot_description`` in a
short-lived helper process before ``mujoco_ros2_control_node`` has finished
creating its subscription.  If that single publication is missed, the controller
manager later times out even though the converter itself succeeded.  This helper
subscribes early, caches the generated description, and republishes it with a
transient-local publisher until the controller-manager service exists.
"""

from __future__ import annotations

import argparse
import time
from typing import Optional

import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class MujocoDescriptionRepublisher(Node):
    """Cache and republish a generated MuJoCo robot description."""

    def __init__(self, topic: str, ready_service: str, period_s: float) -> None:
        super().__init__("mujoco_description_republisher")
        self.topic = topic
        self.ready_service = ready_service
        self.last_message: Optional[String] = None
        self.last_publish_time = self.get_clock().now() - Duration(seconds=period_s)
        self.received_count = 0
        self.published_count = 0

        subscriber_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.VOLATILE,
        )
        publisher_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )

        self.publisher = self.create_publisher(String, topic, publisher_qos)
        self.subscription = self.create_subscription(
            String,
            topic,
            self._on_description,
            subscriber_qos,
        )
        self.timer = self.create_timer(period_s, self._publish_cached_description)

    def _on_description(self, message: String) -> None:
        self.last_message = message
        self.received_count += 1
        if self.received_count == 1:
            self.get_logger().info(
                f"Captured first {self.topic} message ({len(message.data)} bytes)."
            )

    def _publish_cached_description(self) -> None:
        if self.last_message is None:
            return
        self.publisher.publish(self.last_message)
        self.published_count += 1
        self.last_publish_time = self.get_clock().now()
        self.get_logger().info(
            f"Republished {self.topic} ({len(self.last_message.data)} bytes, "
            f"count={self.published_count})."
        )

    def is_ready(self) -> bool:
        return any(
            name == self.ready_service for name, _types in self.get_service_names_and_types()
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Republish /mujoco_robot_description until the controller manager "
            "service is available."
        )
    )
    parser.add_argument("--topic", default="/mujoco_robot_description")
    parser.add_argument(
        "--ready-service", default="/controller_manager/list_controllers"
    )
    parser.add_argument("--period", type=float, default=2.0)
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--spin-sleep", type=float, default=0.1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rclpy.init()
    node = MujocoDescriptionRepublisher(args.topic, args.ready_service, args.period)
    start_time = time.monotonic()

    node.get_logger().info(
        f"Waiting for {args.topic}; will republish until {args.ready_service} exists."
    )
    try:
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=args.spin_sleep)
            if node.is_ready():
                node.get_logger().info(
                    f"{args.ready_service} is available; republisher exiting."
                )
                return 0
            if time.monotonic() - start_time > args.timeout:
                if node.last_message is None:
                    node.get_logger().error(
                        f"Timed out after {args.timeout:.1f}s without receiving {args.topic}."
                    )
                else:
                    node.get_logger().error(
                        f"Timed out after {args.timeout:.1f}s waiting for "
                        f"{args.ready_service}; republished {node.published_count} times."
                    )
                return 1
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

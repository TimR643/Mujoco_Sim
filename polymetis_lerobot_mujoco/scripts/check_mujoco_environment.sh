#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_S=${TIMEOUT_S:-5}

source_ros() {
  # ROS/ament setup files legitimately reference optional variables that may be
  # unset. Temporarily disable nounset while sourcing them, then restore strict mode.
  set +u
  if [ -f /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash ]; then
    source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash
  fi
  if [ -f "$HOME/ros2_ws/install/setup.bash" ]; then
    source "$HOME/ros2_ws/install/setup.bash"
  fi
  set -u
}

has_topic() {
  ros2 topic list 2>/dev/null | grep -qx "$1"
}

has_service() {
  ros2 service list 2>/dev/null | grep -qx "$1"
}

source_ros

echo "MuJoCo/ROS readiness check"
echo "  timeout: ${TIMEOUT_S}s"
echo "  RMW:     ${RMW_IMPLEMENTATION:-<unset>}"
echo "  DDS:     ${CYCLONEDDS_URI:-<unset>}"
echo

echo "ROS nodes:"
ros2 node list 2>/dev/null || true
echo

status=0
if has_topic /mujoco_robot_description; then
  echo "OK: /mujoco_robot_description topic exists."
  ros2 topic info /mujoco_robot_description 2>/dev/null || true
else
  echo "WARN: /mujoco_robot_description topic is not visible from this shell." >&2
  echo "      Some launch variants publish it only transiently; controller-manager readiness is the decisive check." >&2
fi

echo
if has_service /controller_manager/list_controllers; then
  echo "OK: /controller_manager/list_controllers service exists."
  if command -v ros2 >/dev/null 2>&1; then
    timeout "${TIMEOUT_S}s" ros2 control list_controllers 2>/dev/null || true
  fi
else
  echo "ERROR: /controller_manager/list_controllers service is missing." >&2
  echo "       ros2_control_node is not ready; controller spawners will keep retrying." >&2
  status=1
fi

echo
if has_topic /joint_states; then
  echo "OK: /joint_states topic exists."
  ros2 topic info /joint_states 2>/dev/null || true
else
  echo "ERROR: /joint_states topic is missing." >&2
  echo "       Do not start Polymetis/recording until joint states are available." >&2
  status=1
fi

exit "$status"

#!/usr/bin/env bash
set -euo pipefail

LAUNCH_FILE=${LAUNCH_FILE:-fer_mujoco_ros2_control.launch.py}
PACKAGE=${PACKAGE:-franka_mujoco_sim_bringup}
MUJOCO_DDS_PROFILE=${MUJOCO_DDS_PROFILE:-default}
MUJOCO_DESCRIPTION_WATCHDOG=${MUJOCO_DESCRIPTION_WATCHDOG:-0}
ROS_SAFE_PATH=${ROS_SAFE_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}
export PATH="$ROS_SAFE_PATH"

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

case "$MUJOCO_DDS_PROFILE" in
  default)
    ;;
  large|large_data)
    export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
    export CYCLONEDDS_URI="file://$HOME/env/cyclone_dds_large_data.xml"
    ;;
  *)
    echo "ERROR: MUJOCO_DDS_PROFILE must be 'default' or 'large'. Got: $MUJOCO_DDS_PROFILE" >&2
    exit 2
    ;;
esac

WATCHDOG_PID=""
if [ "$MUJOCO_DESCRIPTION_WATCHDOG" = "1" ]; then
  /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/publish_mujoco_description_until_ready.sh &
  WATCHDOG_PID=$!
  trap 'if [ -n "${WATCHDOG_PID:-}" ]; then kill "$WATCHDOG_PID" 2>/dev/null || true; fi' EXIT INT TERM
  sleep "${MUJOCO_DESCRIPTION_WATCHDOG_STARTUP_S:-1}"
fi

cat <<MESSAGE_EOF
Starting MuJoCo simulation environment.
  package: ${PACKAGE}
  launch:  ${LAUNCH_FILE}
  RMW:     ${RMW_IMPLEMENTATION:-<unset>}
  DDS:     ${CYCLONEDDS_URI:-<unset>}
  profile: ${MUJOCO_DDS_PROFILE}
  description watchdog: ${MUJOCO_DESCRIPTION_WATCHDOG}

Keep this terminal open. After MuJoCo is visible and controllers are ready, open a
second container terminal and run check_mujoco_environment.sh. Then start
start_polymetis_after_mujoco.sh.

Note: a few 1000 Hz controller-manager overrun warnings are not the root cause
of launch failure. The fatal symptom is missing /controller_manager readiness.
By default this wrapper does not run extra publishers or DDS overrides; it should
behave like the repository's normal ros2 launch path. Only enable the optional
/mujoco_robot_description watchdog with MUJOCO_DESCRIPTION_WATCHDOG=1 if you have
verified that the plain launch works except for a missed one-shot description.
MESSAGE_EOF

status=0
ros2 launch "$PACKAGE" "$LAUNCH_FILE" || status=$?
if [ -n "${WATCHDOG_PID:-}" ]; then
  kill "$WATCHDOG_PID" 2>/dev/null || true
fi
exit "$status"

#!/usr/bin/env bash
set -euo pipefail

LAUNCH_FILE=${LAUNCH_FILE:-fer_mujoco_ros2_control.launch.py}
PACKAGE=${PACKAGE:-franka_mujoco_sim_bringup}

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

DDS_PROFILE=${CYCLONEDDS_URI#file://}
if [ -n "${CYCLONEDDS_URI:-}" ] && [ -f "$DDS_PROFILE" ]; then
  if grep -q '<MaxMessageSize>65535B</MaxMessageSize>' "$DDS_PROFILE"; then
    cat >&2 <<EOF
ERROR: CycloneDDS profile $DDS_PROFILE still limits MaxMessageSize to 65535B.
       That drops the large /mujoco_robot_description message, so ros2_control
       never becomes ready and controller spawners time out.
       Pull the latest repo and restart the container through ./.docker/run_container.sh.
EOF
    exit 1
  fi
else
  echo "Warning: CYCLONEDDS_URI does not point to a readable file: ${CYCLONEDDS_URI:-<unset>}" >&2
fi

cat <<EOF
Starting MuJoCo simulation environment.
  package: ${PACKAGE}
  launch:  ${LAUNCH_FILE}
  RMW:     ${RMW_IMPLEMENTATION:-<unset>}
  DDS:     ${CYCLONEDDS_URI:-<unset>}

Keep this terminal open. After MuJoCo is visible and controllers are ready, open a
second container terminal and run check_mujoco_environment.sh. Then start
start_polymetis_after_mujoco.sh.

Note: a few 1000 Hz controller-manager overrun warnings are not the root cause
of launch failure. The fatal symptom is missing /mujoco_robot_description or
/controller_manager/list_controllers readiness.
EOF

exec ros2 launch "$PACKAGE" "$LAUNCH_FILE"

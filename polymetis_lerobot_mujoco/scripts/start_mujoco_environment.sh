#!/usr/bin/env bash
set -euo pipefail

LAUNCH_FILE=${LAUNCH_FILE:-fer_mujoco_moveit.launch.py}
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

cat <<EOF
Starting MuJoCo simulation environment.
  package: ${PACKAGE}
  launch:  ${LAUNCH_FILE}

Keep this terminal open. After MuJoCo/RViz is visible, open a second container
terminal and run start_polymetis_after_mujoco.sh.
EOF

exec ros2 launch "$PACKAGE" "$LAUNCH_FILE"

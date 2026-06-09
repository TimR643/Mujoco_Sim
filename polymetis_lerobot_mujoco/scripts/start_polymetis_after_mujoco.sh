#!/usr/bin/env bash
set -euo pipefail

WAIT_FOR_ROS=${WAIT_FOR_ROS:-1}
WAIT_TIMEOUT_S=${WAIT_TIMEOUT_S:-120}
WAIT_FOR_CONTROLLER_MANAGER=${WAIT_FOR_CONTROLLER_MANAGER:-1}

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

if [ "$WAIT_FOR_ROS" = "1" ]; then
  echo "Waiting for the MuJoCo/ROS simulation to become controller-ready ..."
  deadline=$((SECONDS + WAIT_TIMEOUT_S))
  while [ "$SECONDS" -lt "$deadline" ]; do
    have_joint_states=0
    have_controller_manager=0
    if ros2 topic list 2>/dev/null | grep -qx "/joint_states"; then
      have_joint_states=1
    fi
    if [ "$WAIT_FOR_CONTROLLER_MANAGER" != "1" ] || \
       ros2 service list 2>/dev/null | grep -qx "/controller_manager/list_controllers"; then
      have_controller_manager=1
    fi
    if [ "$have_joint_states" = "1" ] && [ "$have_controller_manager" = "1" ]; then
      echo "ROS simulation detected (/joint_states and controller manager are available)."
      break
    fi
    sleep 2
  done
  if ! ros2 topic list 2>/dev/null | grep -qx "/joint_states"; then
    echo "ERROR: /joint_states did not appear within ${WAIT_TIMEOUT_S}s." >&2
    echo "Start/fix the MuJoCo simulation first with start_mujoco_environment.sh." >&2
    echo "Run check_mujoco_environment.sh in another container terminal for diagnostics." >&2
    exit 1
  fi
  if [ "$WAIT_FOR_CONTROLLER_MANAGER" = "1" ] && \
     ! ros2 service list 2>/dev/null | grep -qx "/controller_manager/list_controllers"; then
    echo "ERROR: /controller_manager/list_controllers did not appear within ${WAIT_TIMEOUT_S}s." >&2
    echo "The MuJoCo ros2_control node is not ready; do not attach Polymetis yet." >&2
    echo "Run check_mujoco_environment.sh in another container terminal for diagnostics." >&2
    exit 1
  fi
fi

cat <<EOF
Starting the GELLO/Polymetis server layer after the MuJoCo environment is up.
This calls start_gello_panda_compat.sh. Keep this terminal/tmux session open.
EOF

exec "$HOME/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh"

#!/usr/bin/env bash
set -euo pipefail

WAIT_FOR_ROS=${WAIT_FOR_ROS:-1}
WAIT_TIMEOUT_S=${WAIT_TIMEOUT_S:-120}

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
  echo "Waiting for the MuJoCo/ROS simulation to expose /joint_states ..."
  deadline=$((SECONDS + WAIT_TIMEOUT_S))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ros2 topic list 2>/dev/null | grep -qx "/joint_states"; then
      echo "ROS simulation detected (/joint_states is available)."
      break
    fi
    sleep 2
  done
  if ! ros2 topic list 2>/dev/null | grep -qx "/joint_states"; then
    echo "ERROR: /joint_states did not appear within ${WAIT_TIMEOUT_S}s." >&2
    echo "Start the MuJoCo simulation first with start_mujoco_environment.sh." >&2
    exit 1
  fi
fi

cat <<EOF
Starting the GELLO/Polymetis server layer after the MuJoCo environment is up.
This calls start_gello_panda_compat.sh. Keep this terminal/tmux session open.
EOF

exec "$HOME/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh"

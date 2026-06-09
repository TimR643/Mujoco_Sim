#!/usr/bin/env bash
set -euo pipefail

PUBLISH_TOPIC=${PUBLISH_TOPIC:-/mujoco_robot_description}
READY_SERVICE=${READY_SERVICE:-/controller_manager/list_controllers}
REPUBLISH_INTERVAL_S=${REPUBLISH_INTERVAL_S:-2}
WAIT_FOR_READY_S=${WAIT_FOR_READY_S:-180}
LOG_FILE=${LOG_FILE:-/tmp/mujoco_robot_description_republisher.log}
PACKAGE_ROOT=${PACKAGE_ROOT:-/home/fer_ros2_sim/polymetis_lerobot_mujoco}

set +u
if [ -f /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash ]; then
  source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash
fi
if [ -f "$HOME/ros2_ws/install/setup.bash" ]; then
  source "$HOME/ros2_ws/install/setup.bash"
fi
set -u

export PYTHONPATH="$PACKAGE_ROOT:${PYTHONPATH:-}"

cat <<MESSAGE_EOF
MuJoCo description republisher watchdog
  topic:          $PUBLISH_TOPIC
  ready service:  $READY_SERVICE
  period:         ${REPUBLISH_INTERVAL_S}s
  timeout:        ${WAIT_FOR_READY_S}s
  log:            $LOG_FILE
MESSAGE_EOF

python3 -m polymetis_lerobot_mujoco.mujoco_description_republisher \
  --topic "$PUBLISH_TOPIC" \
  --ready-service "$READY_SERVICE" \
  --period "$REPUBLISH_INTERVAL_S" \
  --timeout "$WAIT_FOR_READY_S" \
  2>&1 | tee -a "$LOG_FILE"

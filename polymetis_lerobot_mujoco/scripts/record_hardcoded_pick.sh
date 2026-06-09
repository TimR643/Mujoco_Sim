#!/usr/bin/env bash
set -euo pipefail

CONFIG=${CONFIG:-$(fer-polymetis-print-config)}
EPISODE_INDEX=${EPISODE_INDEX:-0}
CAMERA_FLAG=${CAMERA_FLAG:-}
ROBOT_BACKEND=${ROBOT_BACKEND:-}
ROBOT_BACKEND_FLAG=()
if [ -n "${ROBOT_BACKEND}" ]; then
  ROBOT_BACKEND_FLAG=(--robot-backend "${ROBOT_BACKEND}")
fi

fer-polymetis-record-hardcoded-pick \
  --config "${CONFIG}" \
  --episode-index "${EPISODE_INDEX}" \
  "${ROBOT_BACKEND_FLAG[@]}" \
  ${CAMERA_FLAG}

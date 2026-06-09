#!/usr/bin/env bash
set -euo pipefail

CONFIG=${CONFIG:-$(fer-polymetis-print-config)}
POLICY_PATH=${POLICY_PATH:?Set POLICY_PATH to a LeRobot checkpoint or Hub ID.}
SECONDS=${SECONDS:-20}
DEVICE=${POLICY_DEVICE:-cuda}
CAMERA_FLAG=${CAMERA_FLAG:-}
ROBOT_BACKEND=${ROBOT_BACKEND:-}
ROBOT_BACKEND_FLAG=()
if [ -n "${ROBOT_BACKEND}" ]; then
  ROBOT_BACKEND_FLAG=(--robot-backend "${ROBOT_BACKEND}")
fi

fer-polymetis-policy-rollout \
  --config "${CONFIG}" \
  --policy-path "${POLICY_PATH}" \
  --device "${DEVICE}" \
  --seconds "${SECONDS}" \
  "${ROBOT_BACKEND_FLAG[@]}" \
  ${CAMERA_FLAG}

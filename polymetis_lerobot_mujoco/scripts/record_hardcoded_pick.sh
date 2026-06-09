#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export PYTHONPATH="${PACKAGE_ROOT}:${PYTHONPATH:-}"
PYTHON_BIN=${PYTHON_BIN:-python}

CONFIG=${CONFIG:-$(${PYTHON_BIN} -m polymetis_lerobot_mujoco.print_config)}
EPISODE_INDEX=${EPISODE_INDEX:-0}
CAMERA_FLAG=${CAMERA_FLAG:-}
ROBOT_BACKEND=${ROBOT_BACKEND:-}
ROBOT_BACKEND_FLAG=()
if [ -n "${ROBOT_BACKEND}" ]; then
  ROBOT_BACKEND_FLAG=(--robot-backend "${ROBOT_BACKEND}")
fi

${PYTHON_BIN} -m polymetis_lerobot_mujoco.record_hardcoded_pick \
  --config "${CONFIG}" \
  --episode-index "${EPISODE_INDEX}" \
  "${ROBOT_BACKEND_FLAG[@]}" \
  ${CAMERA_FLAG}

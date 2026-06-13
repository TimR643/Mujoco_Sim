#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export PYTHONPATH="${PACKAGE_ROOT}:${PYTHONPATH:-}"
PYTHON_BIN=${PYTHON_BIN:-python}

DEFAULT_CONFIG="${PACKAGE_ROOT}/configs/perfect_pick.yaml"
CONFIG=${CONFIG:-${DEFAULT_CONFIG}}
if [ -d "${CONFIG}" ]; then
  echo "Warning: CONFIG='${CONFIG}' is a directory; using default '${DEFAULT_CONFIG}' instead." >&2
  CONFIG="${DEFAULT_CONFIG}"
fi
if [ ! -f "${CONFIG}" ]; then
  echo "Error: CONFIG='${CONFIG}' is not a file. Set CONFIG to a YAML file such as '${DEFAULT_CONFIG}'." >&2
  exit 2
fi

POLICY_PATH=${POLICY_PATH:?Set POLICY_PATH to a LeRobot checkpoint or Hub ID.}
SECONDS=${SECONDS:-20}
DEVICE=${POLICY_DEVICE:-cuda}
CAMERA_FLAG=${CAMERA_FLAG:-}
ROBOT_BACKEND=${ROBOT_BACKEND:-}
ROBOT_BACKEND_FLAG=()
if [ -n "${ROBOT_BACKEND}" ]; then
  ROBOT_BACKEND_FLAG=(--robot-backend "${ROBOT_BACKEND}")
fi

${PYTHON_BIN} -m polymetis_lerobot_mujoco.policy_rollout \
  --config "${CONFIG}" \
  --policy-path "${POLICY_PATH}" \
  --device "${DEVICE}" \
  --seconds "${SECONDS}" \
  "${ROBOT_BACKEND_FLAG[@]}" \
  ${CAMERA_FLAG}

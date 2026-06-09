#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG=${CONFIG:-${PACKAGE_ROOT}/configs/perfect_pick.yaml}
ROBOT_IP=${ROBOT_IP:-127.0.0.1}
GRIPPER_IP=${GRIPPER_IP:-127.0.0.1}
WAIT_TIMEOUT_S=${WAIT_TIMEOUT_S:-120}
CAMERA_FLAG=${CAMERA_FLAG:---no-camera}

export MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX:-$HOME/micromamba}
export PATH="$HOME/.local/bin:$PATH"
set +u
eval "$($HOME/.local/bin/micromamba shell hook --shell bash)"
micromamba activate polymetis_py38
set -u
export PATH="$HOME/.local/bin:$PATH"
export PYTHONPATH="${PACKAGE_ROOT}:${PYTHONPATH:-}"

python -m polymetis_lerobot_mujoco.wait_for_polymetis \
  --robot-ip "$ROBOT_IP" \
  --gripper-ip "$GRIPPER_IP" \
  --timeout-s "$WAIT_TIMEOUT_S"

unset CONFIG_DIRECTORY_GUARD
CONFIG="$CONFIG" CAMERA_FLAG="$CAMERA_FLAG" \
  "$PACKAGE_ROOT/scripts/record_hardcoded_pick.sh"

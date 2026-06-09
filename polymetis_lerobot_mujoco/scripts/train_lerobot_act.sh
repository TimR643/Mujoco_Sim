#!/usr/bin/env bash
set -euo pipefail

DATASET_REPO_ID=${DATASET_REPO_ID:-local/fer_mujoco_cube_pick}
OUTPUT_DIR=${OUTPUT_DIR:-/home/fer_ros2_sim/data/lerobot_outputs/act_fer_mujoco_cube_pick}
POLICY_TYPE=${POLICY_TYPE:-act}
FER_LEROBOT_VENV=${FER_LEROBOT_VENV:-/opt/fer_lerobot_venv}
LEROBOT_TRAIN_BIN=${LEROBOT_TRAIN_BIN:-${FER_LEROBOT_VENV}/bin/lerobot-train}

"${LEROBOT_TRAIN_BIN}" \
  --dataset.repo_id="${DATASET_REPO_ID}" \
  --policy.type="${POLICY_TYPE}" \
  --output_dir="${OUTPUT_DIR}" \
  --job_name="act_fer_mujoco_cube_pick" \
  --policy.device="${POLICY_DEVICE:-cuda}" \
  --wandb.enable=false

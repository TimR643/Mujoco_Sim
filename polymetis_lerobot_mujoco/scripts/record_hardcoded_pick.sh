#!/usr/bin/env bash
set -euo pipefail

CONFIG=${CONFIG:-$(fer-polymetis-print-config)}
EPISODE_INDEX=${EPISODE_INDEX:-0}
CAMERA_FLAG=${CAMERA_FLAG:-}

fer-polymetis-record-hardcoded-pick \
  --config "${CONFIG}" \
  --episode-index "${EPISODE_INDEX}" \
  ${CAMERA_FLAG}

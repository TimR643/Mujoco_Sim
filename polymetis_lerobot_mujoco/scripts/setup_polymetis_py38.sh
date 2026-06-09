#!/usr/bin/env bash
set -euo pipefail

ENV_NAME=${ENV_NAME:-polymetis_py38}
MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX:-$HOME/micromamba}
export MAMBA_ROOT_PREFIX
MICROMAMBA_BIN=${MICROMAMBA_BIN:-$HOME/.local/bin/micromamba}

if ! command -v micromamba >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin" "$MAMBA_ROOT_PREFIX"
  echo "Installing micromamba to ${MICROMAMBA_BIN} ..."
  curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
    | tar -xj -C "$HOME/.local/bin" --strip-components=1 bin/micromamba
fi

MICROMAMBA=$(command -v micromamba || printf '%s' "$MICROMAMBA_BIN")

"$MICROMAMBA" create -y -n "$ENV_NAME" -c conda-forge python=3.8 pip || true
"$MICROMAMBA" install -y -n "$ENV_NAME" \
  -c pytorch -c fair-robotics -c aihabitat -c conda-forge \
  polymetis \
  "mkl<2024" \
  "pytorch=1.13.1" \
  cpuonly

"$MICROMAMBA" run -n "$ENV_NAME" python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
"$MICROMAMBA" run -n "$ENV_NAME" python -m pip install --no-deps --no-build-isolation -e "$HOME/polymetis_lerobot_mujoco"

cat <<EOF2

Polymetis environment is ready.
Activate it in an interactive shell with:

  export MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX}
  eval "\$(${MICROMAMBA} shell hook --shell bash)"
  micromamba activate ${ENV_NAME}
  which python
  python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"

Then run:

  CAMERA_FLAG=--no-camera ${HOME}/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
EOF2

#!/usr/bin/env bash
set -euo pipefail

ENV_NAME=${ENV_NAME:-polymetis_py38}
GELLO_ROOT=${GELLO_ROOT:-$HOME/gello_software}
START_SCRIPT=${START_SCRIPT:-$GELLO_ROOT/start_gello_panda.sh}
MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX:-$HOME/micromamba}
export MAMBA_ROOT_PREFIX

SETUP_SCRIPT=${SETUP_SCRIPT:-$HOME/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh}
MICROMAMBA_BIN=${MICROMAMBA_BIN:-$HOME/.local/bin/micromamba}

if [ ! -x "$MICROMAMBA_BIN" ] || [ ! -f "$HOME/miniconda3/etc/profile.d/conda.sh" ] || ! command -v tmux >/dev/null 2>&1; then
  echo "Preparing Polymetis/micromamba/tmux compatibility environment ..."
  "$SETUP_SCRIPT"
fi

export PATH="$HOME/.local/bin:$PATH"
eval "$($MICROMAMBA_BIN shell hook --shell bash)"
micromamba activate "$ENV_NAME"
export PATH="$HOME/.local/bin:$PATH"

python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
command -v tmux >/dev/null

if [ ! -d "$GELLO_ROOT" ]; then
  echo "ERROR: GELLO_ROOT does not exist: $GELLO_ROOT" >&2
  echo "Mount or clone gello_software to $GELLO_ROOT, or set GELLO_ROOT=/path/to/gello_software." >&2
  exit 1
fi
if [ ! -f "$START_SCRIPT" ]; then
  echo "ERROR: GELLO start script not found: $START_SCRIPT" >&2
  echo "Set START_SCRIPT=/path/to/your/start_gello_panda.sh if it has a different name." >&2
  exit 1
fi

# A running tmux server keeps the environment from the first tmux invocation.
# Push the activated Python/conda environment into the server before the legacy
# launcher creates panes or sends commands.
if tmux start-server >/dev/null 2>&1; then
  tmux set-environment -g PATH "$PATH"
  tmux set-environment -g MAMBA_ROOT_PREFIX "$MAMBA_ROOT_PREFIX"
  tmux set-environment -g CONDA_PREFIX "${CONDA_PREFIX:-$MAMBA_ROOT_PREFIX/envs/$ENV_NAME}"
  tmux set-environment -g PYTHONPATH "${PYTHONPATH:-}"
  tmux set-option -g default-shell /bin/bash >/dev/null 2>&1 || true
fi

cd "$GELLO_ROOT"
echo "Starting GELLO Panda launcher from $GELLO_ROOT with Python $(command -v python)"
exec bash "$START_SCRIPT"

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
# Conda/micromamba activation hooks can read unset variables in package
# deactivate.d scripts (for example libxml2). Temporarily disable nounset while
# activating so this wrapper can also be called from an already-active env.
set +u
eval "$($MICROMAMBA_BIN shell hook --shell bash)"
micromamba activate "$ENV_NAME"
set -u
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

# If a tmux server is already running, update its global environment. If no
# server is running yet, do not call `tmux start-server`: a server without any
# sessions exits immediately and later `set-environment` calls fail with
# "no server running ...". In that normal no-server case, the first tmux command
# in the legacy GELLO launcher starts the server and inherits this process
# environment directly.
if tmux list-sessions >/dev/null 2>&1; then
  tmux set-environment -g PATH "$PATH" || true
  tmux set-environment -g MAMBA_ROOT_PREFIX "$MAMBA_ROOT_PREFIX" || true
  tmux set-environment -g CONDA_PREFIX "${CONDA_PREFIX:-$MAMBA_ROOT_PREFIX/envs/$ENV_NAME}" || true
  tmux set-environment -g PYTHONPATH "${PYTHONPATH:-}" || true
  tmux set-option -g default-shell /bin/bash >/dev/null 2>&1 || true
else
  echo "No existing tmux server found; the GELLO launcher will start one with the current environment."
fi

cd "$GELLO_ROOT"
echo "Starting GELLO Panda launcher from $GELLO_ROOT with Python $(command -v python)"
exec bash "$START_SCRIPT"

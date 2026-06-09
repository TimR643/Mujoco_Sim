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
CONDA_SHIM=${CONDA_SHIM:-$HOME/.local/bin/conda}
cat > "$CONDA_SHIM" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
MICROMAMBA_BIN="${MICROMAMBA_BIN:-$HOME/.local/bin/micromamba}"
if [ "${1:-}" = "activate" ]; then
  # Executable shims cannot modify the parent shell. Legacy tmux commands often
  # run `conda activate polymetis` after a failed `source .../conda.sh`; return
  # success here so they can continue with the environment inherited from the
  # launcher shell. The sourced profile below provides real activation when the
  # shell supports it.
  exit 0
fi
if [ "${1:-}" = "deactivate" ]; then
  exit 0
fi
exec "$MICROMAMBA_BIN" "$@"
SHIM
chmod +x "$CONDA_SHIM"

# Some gello_software launch scripts source a hardcoded Miniconda profile file.
# Provide a compatibility profile that delegates activation to micromamba so
# those scripts can run in this container without installing Miniconda.
MINICONDA_PROFILE=${MINICONDA_PROFILE:-$HOME/miniconda3/etc/profile.d/conda.sh}
mkdir -p "$(dirname "$MINICONDA_PROFILE")" "$HOME/miniconda3/bin"
cat > "$MINICONDA_PROFILE" <<PROFILE
#!/usr/bin/env sh
export MAMBA_ROOT_PREFIX="\${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
if [ -x "$MICROMAMBA" ]; then
  if [ -n "\${BASH_VERSION:-}" ]; then
    eval "\$("$MICROMAMBA" shell hook --shell bash)"
  else
    eval "\$("$MICROMAMBA" shell hook --shell sh)"
  fi
fi
conda() {
  if [ "\${1:-}" = "activate" ]; then
    shift
    env_name="\${1:-$ENV_NAME}"
    if [ "\$env_name" = "polymetis" ]; then
      env_name="$ENV_NAME"
    fi
    micromamba activate "\$env_name"
  elif [ "\${1:-}" = "deactivate" ]; then
    micromamba deactivate
  else
    micromamba "\$@"
  fi
}
PROFILE
ln -sf "$CONDA_SHIM" "$HOME/miniconda3/bin/conda"

# `/bin/sh` does not provide the non-POSIX `source` builtin. Some legacy tmux
# commands still use `source path/to/conda.sh`; this no-op avoids an immediate
# command-not-found failure in those shells. The launcher shell should already be
# activated before starting tmux, so child panes inherit the correct PATH.
SOURCE_SHIM=${SOURCE_SHIM:-$HOME/.local/bin/source}
cat > "$SOURCE_SHIM" <<'SOURCE'
#!/usr/bin/env sh
exit 0
SOURCE
chmod +x "$SOURCE_SHIM"

"$MICROMAMBA" create -y -n "$ENV_NAME" -c conda-forge python=3.8 pip || true
"$MICROMAMBA" install -y -n "$ENV_NAME" \
  -c pytorch -c fair-robotics -c aihabitat -c conda-forge \
  polymetis \
  "mkl<2024" \
  "pytorch=1.13.1" \
  cpuonly

"$MICROMAMBA" run -n "$ENV_NAME" env PATH="$HOME/.local/bin:$PATH" bash -c 'command -v conda && conda list polymetis'
"$MICROMAMBA" run -n "$ENV_NAME" env PATH="$HOME/.local/bin:$PATH" python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
"$MICROMAMBA" run -n "$ENV_NAME" env PATH="$HOME/.local/bin:$PATH" python -m pip install --no-deps --no-build-isolation -e "$HOME/polymetis_lerobot_mujoco"

cat <<EOF2

Polymetis environment is ready.
Activate it in an interactive shell with:

  export MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX}
  eval "\$(${MICROMAMBA} shell hook --shell bash)"
  micromamba activate ${ENV_NAME}
  export PATH=${HOME}/.local/bin:\$PATH
  which python
  command -v conda
  python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"

Then run:

  CAMERA_FLAG=--no-camera ${HOME}/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
EOF2

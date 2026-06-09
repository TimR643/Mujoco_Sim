#!/usr/bin/env bash
set -euo pipefail

ENV_NAME=${ENV_NAME:-polymetis_py38}
MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX:-$HOME/micromamba}
export MAMBA_ROOT_PREFIX
MICROMAMBA_BIN=${MICROMAMBA_BIN:-$HOME/.local/bin/micromamba}
ensure_apt_package() {
  local package=$1
  local binary=${2:-$package}
  if command -v "$binary" >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: '$binary' is missing and sudo is unavailable to install package '$package'." >&2
    return 1
  fi
  echo "Installing missing system package '${package}' for legacy gello_software launchers ..."
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package"
}

mkdir -p "$HOME/.local/bin" "$MAMBA_ROOT_PREFIX"

ensure_apt_package tmux tmux
ensure_apt_package bzip2 bzip2

if ! command -v micromamba >/dev/null 2>&1; then
  echo "Installing micromamba to ${MICROMAMBA_BIN} ..."
  curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
    | tar -xj -C "$HOME/.local/bin" --strip-components=1 bin/micromamba
fi

MICROMAMBA=$(command -v micromamba || printf '%s' "$MICROMAMBA_BIN")

# Make `source` work in /bin/sh tmux panes used by some legacy GELLO launchers.
# /bin/sh treats `source` as an external command, so this shim prevents an early
# command-not-found failure. The parent shell should be activated before the tmux
# panes are spawned; those panes then inherit PATH/CONDA_PREFIX.
SOURCE_SHIM=${SOURCE_SHIM:-$HOME/.local/bin/source}
cat > "$SOURCE_SHIM" <<'SOURCE'
#!/usr/bin/env sh
if [ "$#" -gt 0 ] && [ -r "$1" ]; then
  # External commands cannot modify the parent shell, but returning success lets
  # legacy `source file && conda activate ... && python ...` command chains keep
  # running when the environment was already inherited from the launcher shell.
  exit 0
fi
exit 0
SOURCE
chmod +x "$SOURCE_SHIM"

# Executable `conda` compatibility shim. Polymetis imports shell out to
# `conda list polymetis`; legacy launch panes may also call `conda activate
# polymetis`. Executables cannot activate their parent shell, so activation is a
# no-op here; real activation is handled by the sourced profile below or by the
# wrapper/interactive shell before launching tmux.
CONDA_SHIM=${CONDA_SHIM:-$HOME/.local/bin/conda}
cat > "$CONDA_SHIM" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
MICROMAMBA_BIN="${MICROMAMBA_BIN:-$HOME/.local/bin/micromamba}"
if [ "${1:-}" = "activate" ] || [ "${1:-}" = "deactivate" ]; then
  exit 0
fi
exec "$MICROMAMBA_BIN" "$@"
SHIM
chmod +x "$CONDA_SHIM"

# Some gello_software launch scripts source this hardcoded Miniconda path.
# Provide a profile that delegates to micromamba and maps the old env name
# `polymetis` to our persistent `polymetis_py38` environment.
MINICONDA_PROFILE=${MINICONDA_PROFILE:-$HOME/miniconda3/etc/profile.d/conda.sh}
mkdir -p "$(dirname "$MINICONDA_PROFILE")" "$HOME/miniconda3/bin"
cat > "$MINICONDA_PROFILE" <<PROFILE
#!/usr/bin/env sh
export MAMBA_ROOT_PREFIX="\${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
export PATH="$HOME/.local/bin:\$PATH"
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

"$MICROMAMBA" create -y -n "$ENV_NAME" -c conda-forge python=3.8 pip || true
"$MICROMAMBA" install -y -n "$ENV_NAME" \
  -c pytorch -c fair-robotics -c aihabitat -c conda-forge \
  polymetis \
  "mkl<2024" \
  "pytorch=1.13.1" \
  cpuonly

# Use micromamba's activated PATH, then prepend the local shim directory inside
# the activated shell. Do not pass `env PATH=...` directly to micromamba run: it
# overwrites the environment PATH and can accidentally call the system Python.
"$MICROMAMBA" run -n "$ENV_NAME" bash -lc 'export PATH="$HOME/.local/bin:$PATH"; command -v python; command -v conda; conda list polymetis'
"$MICROMAMBA" run -n "$ENV_NAME" bash -lc 'export PATH="$HOME/.local/bin:$PATH"; python -c "from polymetis import RobotInterface, GripperInterface; print(\"real polymetis ok\")"'
"$MICROMAMBA" run -n "$ENV_NAME" bash -lc 'export PATH="$HOME/.local/bin:$PATH"; python -m pip install --no-deps --no-build-isolation -e "$HOME/polymetis_lerobot_mujoco"'

cat <<EOF2

Polymetis environment is ready.
Activate it in an interactive shell with:

  export MAMBA_ROOT_PREFIX=${MAMBA_ROOT_PREFIX}
  eval "\$(${MICROMAMBA} shell hook --shell bash)"
  micromamba activate ${ENV_NAME}
  export PATH=${HOME}/.local/bin:\$PATH
  which python
  command -v conda
  command -v tmux
  python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"

For legacy gello_software tmux launchers, prefer:

  ${HOME}/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh

Then run the recorder from a second container terminal:

  CAMERA_FLAG=--no-camera ${HOME}/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
EOF2

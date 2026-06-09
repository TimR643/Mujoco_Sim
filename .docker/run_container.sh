#!/bin/bash
#    Copyright 2025 Proximity Robotics & Automation GmbH

#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at

#        http://www.apache.org/licenses/LICENSE-2.0

#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

set -euo pipefail

# ANSI escape codes
YELLOW_BOLD="\033[1;33m"
GREEN_BOLD="\033[1;32m"
RESET="\033[0m"

PACKAGE_NAME="fer_ros2_mujoco_docker"
CONTAINER_USER="fer_ros2_sim"

# Resolve the repository root from this script location instead of assuming a
# fixed checkout directory name. Docker scripts must be executed from the host
# checkout, not from inside the already-running container's ~/ros2_ws.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PACKAGE_ROOT"
echo -e "${GREEN_BOLD}Using repository root: ${PACKAGE_ROOT}${RESET}"

GELLO_COMPAT_WRAPPER="$PACKAGE_ROOT/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh"
if [ -f "$GELLO_COMPAT_WRAPPER" ]; then
    if ! grep -q "tmux list-sessions" "$GELLO_COMPAT_WRAPPER"; then
        echo -e "${YELLOW_BOLD}Warning: ${GELLO_COMPAT_WRAPPER} does not contain the tmux list-sessions fix.${RESET}"
        echo -e "${YELLOW_BOLD}Run 'git pull' on the host checkout, or do not expect the GELLO compatibility launcher to work.${RESET}"
    fi
    echo -e "${GREEN_BOLD}GELLO compatibility wrapper: $(grep -m1 'tmux list-sessions' "$GELLO_COMPAT_WRAPPER" || true)${RESET}"
fi

# Check if DISPLAY is set
if [ "${DISPLAY:-}" ]; then
    xhost + local:root
fi

# Check and create necessary folders
for FOLDER in ros2_ws/src env log data; do
    HOST_PATH="$PACKAGE_ROOT/$FOLDER"
    if [ ! -d "$HOST_PATH" ]; then
        echo -e "${YELLOW_BOLD}Warning: $HOST_PATH does not exist. Creating it...${RESET}"
        mkdir -p "$HOST_PATH"
    fi
done

# Create the .claude_container, so sessions with claude inside docker persist
for FOLDER in .claude_container .micromamba_container .local_container .miniconda3_container gello_software; do
    HOST_PATH="$PACKAGE_ROOT/$FOLDER"
    if [ ! -d "$HOST_PATH" ]; then
        echo -e "${YELLOW_BOLD}Warning: $HOST_PATH does not exist. Creating it...${RESET}"
        mkdir -p "$HOST_PATH"
    fi
done

docker run \
    --name $PACKAGE_NAME \
    -it \
    --privileged \
    --net host \
    --ipc host \
    -e DISPLAY=${DISPLAY:-} \
    -e MAMBA_ROOT_PREFIX=/home/${CONTAINER_USER}/micromamba \
    -e PATH=/home/${CONTAINER_USER}/.local/bin:/opt/fer_lerobot_venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v ~/.Xauthority:/home/${CONTAINER_USER}/.Xauthority \
    -v $PACKAGE_ROOT/ros2_ws:/home/${CONTAINER_USER}/ros2_ws \
    -v $PACKAGE_ROOT/env:/home/${CONTAINER_USER}/env \
    -v $PACKAGE_ROOT/data:/home/${CONTAINER_USER}/data \
    -v $PACKAGE_ROOT/polymetis_lerobot_mujoco:/home/${CONTAINER_USER}/polymetis_lerobot_mujoco \
    -v $PACKAGE_ROOT/gello_software:/home/${CONTAINER_USER}/gello_software \
    -v $PACKAGE_ROOT/.micromamba_container:/home/${CONTAINER_USER}/micromamba \
    -v $PACKAGE_ROOT/.local_container:/home/${CONTAINER_USER}/.local \
    -v $PACKAGE_ROOT/.miniconda3_container:/home/${CONTAINER_USER}/miniconda3 \
    -v $PACKAGE_ROOT/.claude_container:/home/${CONTAINER_USER}/.claude \
    --entrypoint /bin/bash \
    --rm \
    $PACKAGE_NAME/ros:jazzy_moveit

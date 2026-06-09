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

uid=$(eval "id -u")
gid=$(eval "id -g")

# ANSI escape codes
YELLOW_BOLD="\033[1;33m"
GREEN_BOLD="\033[1;32m"
RESET="\033[0m"

PACKAGE_NAME="fer_ros2_mujoco_docker"
CONTAINER_USER="fer_ros2_sim"

# Resolve the repository root from this script location instead of assuming a
# fixed checkout directory name. This allows clones such as
# ~/fer_ros2_mujoco_docker, ~/Mujoco_Sim, or any custom path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PACKAGE_ROOT"
echo -e "${GREEN_BOLD}Using repository root: ${PACKAGE_ROOT}${RESET}"

for FOLDER in ros2_ws/src env log data; do
    HOST_PATH="$PACKAGE_ROOT/$FOLDER"
    if [ ! -d "$HOST_PATH" ]; then
        echo -e "${YELLOW_BOLD}Warning: $HOST_PATH does not exist. Creating it...${RESET}"
        mkdir -p "$HOST_PATH"
    fi
done

gid=1000

docker build \
    --build-arg UID="$uid" \
    --build-arg GID="$gid" \
    --build-arg USER="$CONTAINER_USER" \
    --network=host \
    -t $PACKAGE_NAME/ros:jazzy_moveit . -f $PACKAGE_ROOT/.docker/Dockerfile \
    && docker create --name temp-container $PACKAGE_NAME/ros:jazzy_moveit \
    && docker cp temp-container:/home/${CONTAINER_USER}/ros2_ws/. $PACKAGE_ROOT/ros2_ws/. \
    && docker rm temp-container

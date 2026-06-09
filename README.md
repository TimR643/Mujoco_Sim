# ROS 2 MuJoCo Simulation for Franka Robotics Panda (FER)

This repository provides a high-fidelity physics simulation for the FER robot using **MuJoCo** and **ROS 2 Jazzy**. It uses the `mujoco_ros2_control` framework and ships a fully Dockerized workflow with CycloneDDS for low-latency inter-process communication.

## Key Features
* **Modular URDF Wrapper**: Uses a top-level Xacro wrapper to inject MuJoCo physics without modifying upstream Franka packages.
* **Dockerized Workflow**: Consistent development environment with all dependencies (MuJoCo, MoveIt, ros2_control, CycloneDDS) pre-configured.

---

## Prerequisites

Ensure the following are installed on your host machine:
* **Docker** (latest version)
* **vcstool**: To manage repository dependencies.
  ```bash
  pip install vcstool
  ```

## Installation & Setup

1. Clone the repository:
```bash
git clone https://github.com/GKnerd/fer_ros2_simulation.git
cd fer_ros2_simulation
```

2. Create the source directory and import dependencies:
```bash
mkdir -p ros2_ws/src
vcs import ros2_ws/src < fer_ros2_mujoco.repos
```

3. Build the Docker image:
```bash
./.docker/build_image.sh
```
This builds the image, compiles the full ROS 2 workspace inside the container, and copies the built workspace back to `ros2_ws/` on your host.

## Running the Simulation

0. Prelaunch setup:
**Crucial**
CycloneDDS requires a massive receive buffer to reliably handle large trajectory messages without dropping packets. You must configure your Host OS kernel to allow this, or the Docker container will crash on boot.
```bash
sudo sysctl -w net.core.rmem_max=2147483647
```
>Note 1: To make this persist across reboots, add `net.core.rmem_max=2147483647` to your `/etc/sysctl.conf file`.
>Note 2: You don´t have to specify 2GBs as here, this is use case specific. The value was chosen arbitratily in this case. 

1. Launch the container:
```bash
./.docker/run_container.sh
```

2. Inside the container, run the main launch file:
```bash
ros2 launch franka_mujoco_sim_bringup fer_mujoco_ros2_control.launch.py
```
This opens the MuJoCo simulator and activates the effort controller for the arm and an effort controller for the hand.

If you wish to use the Mujoco simulator with MoveIt and an activated effort controller for the hand and arm you can use this launch file instead.

```bash
ros2 launch franka_mujoco_sim_bringup fer_mujoco_moveit.launch.py
```

## Repository Structure

```
fer_ros2_simulation/
├── .docker/
│   ├── Dockerfile              # Image definition (ROS 2 Jazzy + MoveIt + CycloneDDS)
│   ├── build_image.sh          # Builds the Docker image and extracts the built workspace
│   └── run_container.sh        # Runs the container with GPU/display/volume mounts
├── env/
│   └── cyclone_dds.xml         # CycloneDDS middleware profile
├── ros2_ws/
│   └── src/                    # Populated by vcs import (see Installation)
├── fer_ros2_mujoco.repos       # VCS dependency manifest
└── DDS_Profiles.md             # Reference guide for CycloneDDS configuration and some additional experimental tips which are not on main 
```

### Workspace packages (imported via `fer_ros2_mujoco.repos`)
| Package | Description |
|---|---|
| `franka_description` | Official Franka Robotics URDF and meshes |
| `franka_mujoco_sim_bringup` | Launch files, URDF wrapper, and controller configs |
| `mujoco_ros2_control` | MuJoCo hardware interface for `ros2_control` |
| `mujoco_vendor` | CMake vendor package that integrates the MuJoCo binary |
| `cartesian_controllers` | Cartesian-space controllers for the arm |
| `panda_moveit_config` | MoveIt configuration for the Panda robot |

---

## Contribution Guidelines

This repository is currently a work in progress.

* **No direct commits to `main`**: All development must happen in feature branches.
* Create a new branch for your task:
  ```bash
  git checkout -b feature/your-feature-name
  ```
* Run a clean `colcon build` before submitting a Pull Request.
# Mujoco_Sim

## Perfect-condition Polymetis/GELLO → LeRobot verification pipeline

This repository now includes `polymetis_lerobot_mujoco`, a Python package for
testing the full imitation-learning path in MuJoCo before using the physical
GELLO. The Panda command path is deliberately the same as in `gello_software` for
Franka FER/Panda: Python sends 8-D commands (`7 arm joints + normalized gripper`)
through `polymetis.RobotInterface` and `polymetis.GripperInterface`. No ROS 2
controller, `FollowJointTrajectory` action, or `ros2_control` command path is
used for recording or policy rollout.

### What is included

* A MuJoCo-native FRAMOS D435e wrist-camera MJCF snippet.
* A deterministic single-cube pick trajectory in GELLO/Panda 8-D joint format.
* A hardcoded-agent recorder that replaces only the physical GELLO device while
  keeping the Polymetis Franka control boundary.
* A local LeRobot-style dataset boundary and wrappers for ACT training and
  policy rollout through Polymetis.


### `gello_software` checkout

`gello_software/` is intentionally a **local external checkout**, not a tracked
submodule of this repository. Clone or copy your GELLO repository into the host
folder `gello_software/`; `run_container.sh` mounts that folder to
`/home/fer_ros2_sim/gello_software` inside Docker. This avoids broken Gitlink
entries in VS Code while still making the GELLO launcher available in the
container.


### Recommended three-terminal MuJoCo → Polymetis → Recorder flow

Use this flow when you want to first see/load the MuJoCo simulation, then attach
the Polymetis/GELLO server layer, and only then run the hardcoded recorder.

1. **Container terminal A: start MuJoCo/RViz first**
   ```bash
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_mujoco_environment.sh
   ```
   The default launch file is now the lighter `fer_mujoco_ros2_control.launch.py`
   because this is the stable base environment for attaching Polymetis. Override
   with `LAUNCH_FILE=fer_mujoco_moveit.launch.py` only if you explicitly need
   MoveIt/RViz during this step. The wrapper also starts a short-lived
   `/mujoco_robot_description` republisher watchdog before `ros2 launch`; this
   handles the launch-order race where `mujoco_ros2_control_node` misses the
   one-shot MJCF description publication and then all controller spawners time
   out on `/controller_manager/list_controllers`.

2. **Container terminal B: verify MuJoCo/ros2_control readiness, then attach/start Polymetis**
   ```bash
   docker exec -it fer_ros2_mujoco_docker bash
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/check_mujoco_environment.sh
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_polymetis_after_mujoco.sh
   ```

   If `check_mujoco_environment.sh` reports that `/controller_manager/list_controllers`
   or `/joint_states` is missing, keep Terminal A open and fix the MuJoCo launch
   before starting Polymetis. The repeated controller-spawner warnings are a
   symptom of this missing readiness. You do **not** need a real-time kernel to
   fix a missing controller-manager service; first restore the normal MuJoCo
   launch path. `run_container.sh` no longer forces a container-wide DDS override, so the
   original ROS/MuJoCo launch path keeps its default middleware behavior. If you
   explicitly want to test the larger DDS profile, start only the MuJoCo wrapper
   with `MUJOCO_DDS_PROFILE=large`; otherwise no DDS override is applied.

3. **Container terminal C: wait for Polymetis and record**
   ```bash
   docker exec -it fer_ros2_mujoco_docker bash
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_after_polymetis_ready.sh
   ```

This makes the required ordering explicit: MuJoCo/ROS simulation first, then
Polymetis/GELLO server, then the LeRobot-style recording.

### Quick start

Run the Docker helper scripts from the **host checkout**, not from inside the
container. If your prompt looks like `fer_ros2_sim@...:~/ros2_ws$`, you are
already inside the container; type `exit` first and then run the Docker scripts
from the directory that contains `.docker/`.

1. On the host, build and enter the container from any checkout directory name:
   ```bash
   cd /path/to/your/fer_ros2_mujoco_docker
   ./.docker/build_image.sh
   ./.docker/run_container.sh
   ```
2. Inside the container, the verification tools run from the isolated
   `/opt/fer_lerobot_venv` Python environment. If you edited the mounted package
   after building the image, refresh the editable install:
   ```bash
   python3 -m pip install --no-deps --no-build-isolation -e /home/fer_ros2_sim/polymetis_lerobot_mujoco
   ```
3. If `micromamba` or `tmux` is missing after restarting the `--rm`
   container, install/repair the persistent Polymetis environment once. The
   helper stores micromamba, the Miniconda-compatible shim folder, and the env in
   host-mounted folders so they survive container restarts. It also installs
   missing `tmux`/`bzip2` packages in already-running old containers, creates a
   Miniconda-compatible `~/miniconda3/etc/profile.d/conda.sh` shim, and adds
   `conda`/`source` compatibility commands for legacy `gello_software` tmux
   panes:
   ```bash
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
   ```
4. Activate the Polymetis environment before real recording:
   ```bash
   export MAMBA_ROOT_PREFIX=/home/fer_ros2_sim/micromamba
   eval "$(micromamba shell hook --shell bash)"
   micromamba activate polymetis_py38
   export PATH=/home/fer_ros2_sim/.local/bin:$PATH
   command -v conda
   python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
   ```
5. Start your MuJoCo Franka behind the Polymetis endpoint used by your
   `gello_software` Panda setup. For the legacy tmux launcher, use the
   compatibility wrapper so the activated micromamba environment, `conda.sh`
   shim, `source` shim, existing/new tmux server environment, and Conda hook
   edge cases such as `libxml2_deactivate.sh` under `set -u` are all handled
   consistently:
   ```bash
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
   ```
   If the container still shows old `tmux set-environment` lines without
   `tmux list-sessions`, leave the container and update/check the host checkout;
   `run_container.sh` now warns when the host wrapper is missing that fix.
6. Add `polymetis_lerobot_mujoco/mujoco/framos_d435e_wrist_camera.xml` to the
   Panda wrist/hand body in your MJCF and expose that rendered camera as an
   OpenCV-readable stream/device.
7. If Polymetis is not installed/active yet, run a no-robot smoke test first:
   ```bash
   ROBOT_BACKEND=mock CAMERA_FLAG=--no-camera \
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
   ```
8. After installing/activating your real `gello_software` Polymetis environment
   and starting the Polymetis MuJoCo endpoint, record the real hardcoded pick.
   The wrapper uses the currently active `python`, so activate the Polymetis
   conda/micromamba environment before calling it.
   The detailed conda/mamba setup is documented in
   `polymetis_lerobot_mujoco/docs/POLYMETIS_GELLO_PIPELINE.md`.
   ```bash
   CAMERA_FLAG=--no-camera \
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
   ```
   If you previously exported `CONFIG=.` in the same shell, either run
   `unset CONFIG` first or set
   `CONFIG=/home/fer_ros2_sim/polymetis_lerobot_mujoco/configs/perfect_pick.yaml`;
   the wrappers now also warn and fall back to the default YAML when `CONFIG` is
   a directory. If the next error is `grpc._channel._InactiveRpcError` with
   `failed to connect to all addresses`, the Python side is ready but the
   MuJoCo/Polymetis robot server is not reachable yet; start that endpoint in a
   second terminal or update `polymetis.robot_ip` / `polymetis.gripper_ip` in the
   YAML config.
9. Train and replay with the wrappers documented in
   `polymetis_lerobot_mujoco/docs/POLYMETIS_GELLO_PIPELINE.md`.

Tune only the task waypoints in
`polymetis_lerobot_mujoco/configs/perfect_pick.yaml` to match the cube pose in
your MuJoCo scene while keeping the Polymetis endpoint and observation/action
names unchanged.

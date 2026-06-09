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
3. Start your MuJoCo Franka behind the Polymetis endpoint used by your
   `gello_software` Panda setup.
4. Add `polymetis_lerobot_mujoco/mujoco/framos_d435e_wrist_camera.xml` to the
   Panda wrist/hand body in your MJCF and expose that rendered camera as an
   OpenCV-readable stream/device.
5. If Polymetis is not installed/active yet, run a no-robot smoke test first:
   ```bash
   ROBOT_BACKEND=mock CAMERA_FLAG=--no-camera \
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
   ```
6. After installing/activating your real `gello_software` Polymetis environment
   and starting the Polymetis MuJoCo endpoint, record the real hardcoded pick.
   The wrapper uses the currently active `python`, so activate the Polymetis
   conda/micromamba environment before calling it.
   The detailed conda/mamba setup is documented in
   `polymetis_lerobot_mujoco/docs/POLYMETIS_GELLO_PIPELINE.md`.
   ```bash
   CAMERA_FLAG=--no-camera \
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
   ```
7. Train and replay with the wrappers documented in
   `polymetis_lerobot_mujoco/docs/POLYMETIS_GELLO_PIPELINE.md`.

Tune only the task waypoints in
`polymetis_lerobot_mujoco/configs/perfect_pick.yaml` to match the cube pose in
your MuJoCo scene while keeping the Polymetis endpoint and observation/action
names unchanged.

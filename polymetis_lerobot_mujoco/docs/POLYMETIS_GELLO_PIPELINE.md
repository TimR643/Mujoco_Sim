# Polymetis/GELLO-compatible MuJoCo → LeRobot verification pipeline

This pipeline intentionally does **not** command the Franka through ROS 2
controllers. For the Panda it follows the same control boundary as
`gello_software`: a Python robot object backed by Polymetis exposes an 8-D state
and command vector (`7 arm joints + normalized gripper`) and can be used by a
GELLO agent, a hardcoded agent, or a policy agent.

## 1. Start MuJoCo as the Polymetis-controlled robot

Use the same Polymetis server/client setup that your `gello_software` Panda path
uses. In perfect-condition simulation, the Polymetis endpoint should point at the
MuJoCo Franka instead of the real FCI robot. The recorder defaults to
`127.0.0.1` for both arm and gripper in `configs/perfect_pick.yaml`.

The important invariant is:

```text
Python recorder/policy → polymetis.RobotInterface / GripperInterface → MuJoCo Franka
```

There is no `FollowJointTrajectory`, `ros2_control`, or ROS 2 action server in
this path.

## 2. Add the wrist camera in MuJoCo

Insert `mujoco/framos_d435e_wrist_camera.xml` inside the Panda wrist/hand body in
your MJCF model. The snippet adds a camera named `framos_d435e_color` at the
wrist. Publish or expose the rendered camera as an OpenCV-readable stream/device
and set `camera.wrist.device` in `configs/perfect_pick.yaml` accordingly.

For a quick dry run without camera plumbing, pass `--no-camera` or set
`CAMERA_FLAG=--no-camera` in the shell wrappers.

## 3. Start the Docker environment correctly

Run Docker helper scripts from the **host checkout**. They are intentionally not
available from inside `~/ros2_ws` in an already-running container.

```bash
# Host terminal, in the directory that contains .docker/
cd /path/to/your/fer_ros2_mujoco_docker
./.docker/build_image.sh
./.docker/run_container.sh
```

Inside the container the package is mounted at
`/home/fer_ros2_sim/polymetis_lerobot_mujoco`. The Docker image places LeRobot
and the verification CLI entry points in an isolated Python environment at
`/opt/fer_lerobot_venv` and adds it to `PATH`. If you edited the package after
building the image, refresh the editable install:

```bash
python3 -m pip install --no-deps --no-build-isolation -e /home/fer_ros2_sim/polymetis_lerobot_mujoco
```

The container intentionally does not install Polymetis itself. Official Polymetis
installation is conda/source based and targets a dedicated Python environment;
use the same Polymetis environment you use for `gello_software`, or make it
visible to this container before selecting the real `polymetis` backend. See the
official installation docs: https://facebookresearch.github.io/fairo/polymetis/installation.html

## 4. Smoke-test the recorder without Polymetis

If `import polymetis` fails, verify the data path with the in-process mock robot
first. This does not control MuJoCo, but it confirms config loading, hardcoded
trajectory interpolation, dataset writing, and CLI wiring:

```bash
ROBOT_BACKEND=mock CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

## 5. Record one hardcoded pick episode through Polymetis

The hardcoded agent replaces only the physical GELLO device. It produces the
same style of absolute 8-D Panda command that a GELLO agent would produce.

```bash
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

Remove `CAMERA_FLAG=--no-camera` once the MuJoCo wrist camera is available to
OpenCV. Episodes are written below `lerobot.root` with keys named like LeRobot
observations/actions: `observation.state`, `observation.images.wrist`, and
`action`.

## 6. Train the LeRobot policy

After converting/registering the local dataset if required by your installed
LeRobot version, train with the included wrapper:

```bash
DATASET_REPO_ID=local/fer_mujoco_cube_pick \
OUTPUT_DIR=/home/fer_ros2_sim/data/lerobot_outputs/act_fer_mujoco_cube_pick \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/train_lerobot_act.sh
```

## 7. Execute the trained model through Polymetis

```bash
POLICY_PATH=/home/fer_ros2_sim/data/lerobot_outputs/act_fer_mujoco_cube_pick/checkpoints/last/pretrained_model \
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/run_policy_rollout.sh
```

Again, remove `CAMERA_FLAG=--no-camera` after the wrist camera stream is ready.
The policy rollout uses the same Polymetis command path as recording.

## 8. Tune only the task waypoints

Tune `trajectory.waypoints` in `configs/perfect_pick.yaml` to your cube pose.
Keep the Polymetis endpoint, dataset metadata, and observation/action names
stable so the verification run remains comparable to the real GELLO pipeline.

## 9. Troubleshooting: `No such file or directory` for `.docker/*`

If you see a prompt like this:

```text
fer_ros2_sim@tim:~/ros2_ws$
```

you are already inside the container. The Docker helper scripts live in the host
repository checkout and are not mounted into `~/ros2_ws`. Leave the container and
run them on the host:

```bash
exit
cd /path/to/your/fer_ros2_mujoco_docker
./.docker/build_image.sh
./.docker/run_container.sh
```

The path `/workspace/Mujoco_Sim` is only an example from an automation workspace;
use the actual directory where you cloned this repository.

## 10. Troubleshooting: ROS 2 controller-manager overrun messages

Messages such as `Overrun detected! The controller manager missed its desired
rate of 1000 Hz` come from the ROS 2 `ros2_control_node`. They are not produced
by the Polymetis/LeRobot verification recorder. For this verification path, the
Franka command interface should be Polymetis, not ROS 2 controllers. If you start
a ROS 2 MuJoCo launch file, that can still be useful for other experiments, but
it is not the command path used by `record_hardcoded_pick.sh` or
`run_policy_rollout.sh`.

## 11. Troubleshooting: Docker build fails while installing LeRobot

If the build fails with a message like:

```text
ERROR: Cannot uninstall packaging 24.0, RECORD file not found.
Hint: The package was installed by debian.
```

then pip tried to install LeRobot into the system Python environment and attempted
to replace a Debian-managed Python package. The Dockerfile now avoids that class
of failure by installing LeRobot, PyArrow, OpenCV, and the verification package
inside `/opt/fer_lerobot_venv` instead of the system interpreter. Rebuild the
image after pulling this change:

```bash
./.docker/build_image.sh
```

Only run `./.docker/run_container.sh` after the build completes successfully. If
you executed both commands as two separate shell lines, the run command can still
start an older image after a failed build.

## 12. Troubleshooting: `ModuleNotFoundError: No module named 'polymetis'`

This means the LeRobot/verification venv is working, but the real Polymetis
client library is not installed or not visible in the running container. This is
expected in a plain ROS Docker image because Polymetis is not a standard PyPI
dependency; install/activate your `gello_software` Polymetis environment for real
MuJoCo control. Until then, run:

```bash
ROBOT_BACKEND=mock CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

That mock command should produce a dataset episode without commanding MuJoCo.
After Polymetis is installed and your MuJoCo Polymetis endpoint is running, omit
`ROBOT_BACKEND=mock` so the default `robot_backend: polymetis` is used.

## 13. Make a real Polymetis environment available

The verification Docker image provides the LeRobot tools in
`/opt/fer_lerobot_venv`, but it intentionally does not install the real Polymetis
client. For real MuJoCo/Franka control, run the recorder from the same conda or
mamba environment that your `gello_software` Panda setup uses.

### Option A: reuse an existing `gello_software` Polymetis environment

Inside the container or on the host where the Polymetis MuJoCo endpoint is
reachable:

```bash
conda activate <your-gello-polymetis-env>
python -c "import polymetis; print(polymetis.__file__)"
python -m pip install --no-deps --no-build-isolation -e /home/fer_ros2_sim/polymetis_lerobot_mujoco
which python
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

Use `--no-deps` so pip does not try to replace the carefully pinned Polymetis
conda packages.

### Option B: create a fresh Polymetis conda environment

The official Polymetis installation recommends a conda environment with
`python=3.8` and installing from the `pytorch`, `fair-robotics`, `aihabitat`, and
`conda-forge` channels. Use `mamba` if available; otherwise replace `mamba` with
`conda`.

```bash
mamba create -n polymetis python=3.8
mamba activate polymetis
mamba install -c pytorch -c fair-robotics -c aihabitat -c conda-forge polymetis
python -c "from polymetis import RobotInterface, GripperInterface; print('polymetis ok')"
python -m pip install --no-deps --no-build-isolation -e /home/fer_ros2_sim/polymetis_lerobot_mujoco
which python
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

If you do not have the repository mounted at `/home/fer_ros2_sim`, substitute the
actual path to `polymetis_lerobot_mujoco`.

### Important: training and recording can use different Python environments

Recording through Polymetis can run in the Polymetis conda environment and write
data to `/home/fer_ros2_sim/data/lerobot_mujoco_cube_pick`. Training can then run
from `/opt/fer_lerobot_venv` with `train_lerobot_act.sh`. This avoids forcing
newer LeRobot dependencies into the older Polymetis Python environment.

## 14. Troubleshooting: conda Polymetis is active but the recorder still uses `/opt/fer_lerobot_venv`

If the traceback starts with `/opt/fer_lerobot_venv/bin/fer-polymetis-record-hardcoded-pick`,
you are running the old console entry point from the LeRobot venv instead of the
currently activated Polymetis conda Python. The wrapper scripts now avoid that by
calling `python -m polymetis_lerobot_mujoco...` and adding the package checkout to
`PYTHONPATH`. Pull this change and run the wrapper script by absolute path:

```bash
cd /home/fer_ros2_sim/polymetis_lerobot_mujoco
git pull  # if this directory is a git checkout; otherwise update it from the host mount
export MAMBA_ROOT_PREFIX=/home/fer_ros2_sim/micromamba
eval "$(micromamba shell hook --shell bash)"
micromamba activate polymetis_py38
which python
python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

A second symptom of an outdated checkout is:

```text
ERROR: Package 'polymetis-lerobot-mujoco' requires a different Python: 3.8.15 not in '>=3.10'
```

The package metadata has been lowered to `requires-python = ">=3.8"`. If you still
see `>=3.10`, the container is using an older copy of this repository. Pull or
remount the updated repository, then rerun the editable install.

## 15. Troubleshooting: `micromamba: command not found` after restarting the container

The Docker container is started with `--rm`, so anything installed only inside the
container filesystem disappears when you type `exit`. The run script now mounts
three persistent host folders into the container:

- `.micromamba_container/` → `/home/fer_ros2_sim/micromamba`
- `.local_container/` → `/home/fer_ros2_sim/.local`
- `gello_software/` → `/home/fer_ros2_sim/gello_software`

After pulling this change, restart the container. Then install micromamba and the
Polymetis env once with:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
```

For later container sessions, activate the persisted environment with:

```bash
export MAMBA_ROOT_PREFIX=/home/fer_ros2_sim/micromamba
eval "$(micromamba shell hook --shell bash)"
micromamba activate polymetis_py38
which python
python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
```

If `cd gello_software` failed before, it was because the repo directory was not
mounted into the container. The run script now mounts it at
`/home/fer_ros2_sim/gello_software`; populate the host `gello_software/` folder
with your checkout if you want to use it inside this container.

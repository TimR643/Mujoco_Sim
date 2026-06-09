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

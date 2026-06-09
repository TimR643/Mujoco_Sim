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
`/opt/fer_lerobot_venv`, but that virtualenv is intentionally **not** prepended to
the global `PATH` so normal ROS launch helpers keep using the system ROS Python.
If you edited the package after building the image, refresh the editable install
explicitly in the venv:

```bash
/opt/fer_lerobot_venv/bin/python -m pip install --no-deps --no-build-isolation -e /home/fer_ros2_sim/polymetis_lerobot_mujoco
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

## 16. Troubleshooting: `Cannot locate Polymetis version!`

The conda Polymetis package imports `polymetis._version`, which shells out to a
`conda` command to locate the installed package version. In this container we use
`micromamba`, so a plain Polymetis import can fail with:

```text
/bin/sh: 1: conda: not found
Exception: Cannot locate Polymetis version!
```

The setup helper now creates a small compatibility shim at
`/home/fer_ros2_sim/.local/bin/conda` that forwards `conda ...` calls to
`micromamba ...`, and `run_container.sh` puts that directory on `PATH`. After
pulling this change, rerun:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
```

Then activate with the shim on `PATH`:

```bash
export MAMBA_ROOT_PREFIX=/home/fer_ros2_sim/micromamba
eval "$(micromamba shell hook --shell bash)"
micromamba activate polymetis_py38
export PATH=/home/fer_ros2_sim/.local/bin:$PATH
command -v conda
conda list polymetis
python -c "from polymetis import RobotInterface, GripperInterface; print('real polymetis ok')"
```

## 17. Troubleshooting: `IsADirectoryError: ... '.'` while loading the config

The recorder expects `--config` to point to the YAML file
`/home/fer_ros2_sim/polymetis_lerobot_mujoco/configs/perfect_pick.yaml`. If your
shell contains an old `CONFIG=.` export, Python receives the current directory
instead of that YAML file and older wrappers failed with:

```text
IsADirectoryError: [Errno 21] Is a directory: '.'
```

The wrappers now validate `CONFIG` before Python starts. If `CONFIG` points to a
directory, they print a warning and fall back to the package default config. You
can also clean your shell explicitly:

```bash
unset CONFIG
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

Or pass the config file explicitly:

```bash
CONFIG=/home/fer_ros2_sim/polymetis_lerobot_mujoco/configs/perfect_pick.yaml \
CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

## 18. Troubleshooting: `grpc._channel._InactiveRpcError` / `failed to connect to all addresses`

This is the next expected error once the Python environment and YAML config are
correct: Polymetis is installed, but there is no Polymetis robot server reachable
at the configured address. The default config points both the arm and gripper to
`127.0.0.1`, so the MuJoCo-backed Polymetis endpoint must already be running in
another terminal in the same container/network namespace before the recorder can
connect.

Use this order:

1. Terminal A: activate the same `polymetis_py38` environment and start your
   MuJoCo/Polymetis server exactly as you start it for the `gello_software`
   Panda path.
2. Terminal B: activate `polymetis_py38`, then run the recorder:

   ```bash
   unset CONFIG
   CAMERA_FLAG=--no-camera \
   /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
   ```

3. If the server is not listening on localhost, edit
   `polymetis_lerobot_mujoco/configs/perfect_pick.yaml` and set
   `polymetis.robot_ip` and `polymetis.gripper_ip` to the reachable host/IP.

To verify only the LeRobot writer and hardcoded trajectory without any Polymetis
server, keep using the mock backend:

```bash
ROBOT_BACKEND=mock CAMERA_FLAG=--no-camera \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

## 19. Troubleshooting: `start_gello_panda.sh` cannot find `conda.sh` or `tmux`

Some `gello_software` launch scripts are written for a workstation Miniconda
installation and source `/home/fer_ros2_sim/miniconda3/etc/profile.d/conda.sh`.
This Docker image uses persistent `micromamba` instead. The run script now mounts
`~/miniconda3` from a persistent host folder, so the compatibility profile also
survives `--rm` container restarts. Rerun the setup helper after pulling this
change; it creates a Miniconda-compatible profile shim and a `conda` command shim
that delegate to micromamba:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
```

If you are using an already-running container that was built before `tmux` was
added to the image, rerun the setup helper. It now installs missing `tmux` and
`bzip2` packages through `sudo apt-get` before checking Polymetis, so the fix also
works without rebuilding the image:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
```

Then prefer the compatibility launcher instead of calling the legacy script
manually. It activates `polymetis_py38`, verifies the Polymetis import, updates an
already-running tmux server when one exists, otherwise lets the legacy launcher
start a new tmux server with the current environment, and finally executes
`start_gello_panda.sh`:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
```

### `source: not found` or `conda activate polymetis` inside tmux panes

If `start_gello_panda.sh` creates tmux panes with `/bin/sh -c "source ...;
conda activate polymetis; ..."`, two extra compatibility details matter:

- `/bin/sh` does not have Bash's `source` builtin.
- An executable `conda activate ...` cannot modify its parent shell, so a direct
  micromamba subprocess prints `Shell not initialized`.

Rerun the setup helper after pulling this change. It now creates:

- `~/miniconda3/etc/profile.d/conda.sh`, which defines a shell-level `conda`
  function backed by micromamba and maps the legacy env name `polymetis` to
  `polymetis_py38`.
- `~/.local/bin/conda`, where `conda activate`/`deactivate` are safe no-ops for
  legacy subprocess calls.
- `~/.local/bin/source`, a no-op compatibility command for legacy `/bin/sh` tmux
  commands that use `source`.

Use this exact sequence before rerunning the launcher:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
```

If your GELLO checkout or launcher has a different path, override it explicitly:

```bash
GELLO_ROOT=/home/fer_ros2_sim/gello_software START_SCRIPT=/home/fer_ros2_sim/gello_software/start_gello_panda.sh /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
```


### `no server running on /tmp/tmux-.../default` from the compatibility launcher

That message meant the wrapper tried to force-create a tmux server and then set
global tmux environment variables after the empty server had already exited. The
wrapper no longer does that. If no tmux server exists, it now simply starts the
legacy GELLO launcher and lets the first tmux command in that launcher create the
server while inheriting the already-activated Polymetis environment.

Use the same command again after pulling this fix:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
```

### `libxml2_deactivate.sh: ... unbound variable` during `micromamba activate`

Some packages installed by the Polymetis Conda stack provide activation or
deactivation hooks that read variables which are not always set. If a wrapper is
running with Bash `set -u`, activating an environment that is already active can
fail with a message like:

```text
.../etc/conda/deactivate.d/libxml2_deactivate.sh: line 3: xml_catalog_files_libxml2: unbound variable
```

The compatibility setup and launcher now temporarily disable `nounset` only
around micromamba hook evaluation and environment activation/deactivation, then
restore it. Rerun the setup helper and start GELLO via the compatibility wrapper:

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/setup_polymetis_py38.sh
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
```

## 20. Troubleshooting: host says `Already up to date`, but the container still shows old wrapper lines

If this command inside the container still shows direct `tmux set-environment`
lines without an `if tmux list-sessions ...` guard, the mounted host checkout is
still stale:

```bash
nl -ba /home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh | sed -n '42,56p'
```

Leave the container and verify the file on the host, not inside Docker:

```bash
exit
cd ~/fer_ros2_mujoco_docker
grep -n "tmux list-sessions" polymetis_lerobot_mujoco/scripts/start_gello_panda_compat.sh
git log -1 --oneline
```

The host file must contain `tmux list-sessions`. If `git pull` says `Already up
to date` but the grep finds nothing, your local branch/remote does not contain
this fix yet. Apply the branch that contains this change, or update the file from
the PR before starting the container again. The run script now prints a warning
when the host wrapper lacks the marker, before Docker starts.

## 21. Troubleshooting: VS Code cannot open `gello_software (<commit>)`

If VS Code shows an error like `Unable to open 'gello_software (9be5302)'` or a
`git:/.../gello_software?...` URI, Git is treating `gello_software` as a Gitlink
/submodule entry. This repository should not track `gello_software` as a submodule;
it is a local external checkout mounted into Docker. The fix is to remove the
Gitlink from this repository's index and ignore the local checkout directory.

After pulling the fix, `git status --short` should no longer show `M
gello_software` merely because your local GELLO checkout changed. Clone/copy your
GELLO repository into the ignored host folder instead:

```bash
cd ~/fer_ros2_mujoco_docker
mkdir -p gello_software
# copy or clone your GELLO repo contents into ./gello_software
./.docker/run_container.sh
```

Inside the container the same folder appears at
`/home/fer_ros2_sim/gello_software`.

## 22. Recommended ordered launch: MuJoCo first, Polymetis second, recorder third

For visual debugging, start the simulation before trying to connect Polymetis. Use
three terminals attached to the same Docker container.

### Terminal A: MuJoCo/RViz simulation

```bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_mujoco_environment.sh
```

By default this launches `franka_mujoco_sim_bringup` with the lighter
`fer_mujoco_ros2_control.launch.py`. Use this as the stable base environment
before attaching Polymetis. The wrapper starts a `/mujoco_robot_description`
republisher watchdog before the launch so the ros2_control node can still obtain
the MJCF description if it misses the converter's one-shot publication. This
addresses the failure pattern where every controller spawner times out on
`/controller_manager/list_controllers` and the MuJoCo node later reports a
`Timeout waiting for /mujoco_robot_description topic`. To launch the MoveIt/RViz
setup instead:

```bash
LAUNCH_FILE=fer_mujoco_moveit.launch.py \
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_mujoco_environment.sh
```

### Terminal B: Polymetis/GELLO server layer after simulation is up

```bash
docker exec -it fer_ros2_mujoco_docker bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/check_mujoco_environment.sh
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/start_polymetis_after_mujoco.sh
```

The check helper verifies that `/controller_manager/list_controllers` and
`/joint_states` are present and reports `/mujoco_robot_description` when visible.
The Polymetis helper then waits until `/joint_states` and the controller manager
are available before calling the GELLO compatibility launcher. Keep this terminal
or its tmux session open. If the check fails, the MuJoCo launch is not ready yet;
do not start Polymetis. If controller spawners repeatedly print `Could not
contact service /controller_manager/list_controllers`, do not chase a
real-time-kernel issue first. A few 1000 Hz overrun warnings are expected on
non-real-time Docker hosts; a missing controller-manager service means the normal
MuJoCo launch path has not reached readiness. The Docker run script no longer
forces a container-wide DDS override and no longer prepends
`/opt/fer_lerobot_venv/bin` to the global `PATH`, so the original ROS/MuJoCo
launch path keeps its default middleware and system ROS Python behavior. If you
explicitly want to test the larger message-size DDS profile, start Terminal A
with `MUJOCO_DDS_PROFILE=large`; the default path applies no DDS override.

### Terminal C: wait for Polymetis and record

```bash
docker exec -it fer_ros2_mujoco_docker bash
/home/fer_ros2_sim/polymetis_lerobot_mujoco/scripts/record_after_polymetis_ready.sh
```

This helper activates `polymetis_py38`, waits until `RobotInterface` and
`GripperInterface` on `127.0.0.1` are reachable, and then runs
`record_hardcoded_pick.sh` with `CAMERA_FLAG=--no-camera` by default. Remove or
override `CAMERA_FLAG` once the wrist camera stream is available.

If Terminal C times out, the Polymetis server layer in Terminal B did not bind to
the configured robot/gripper endpoint. Check the Terminal B tmux panes before
starting the recorder.

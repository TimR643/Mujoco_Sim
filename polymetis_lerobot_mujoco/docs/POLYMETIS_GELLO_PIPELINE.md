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

## 3. Install the Python package

From the repository root inside your container or Python environment:

```bash
python3 -m pip install -e polymetis_lerobot_mujoco
```

The environment must already contain the same Polymetis and `gello_software`
Panda dependencies you use for the real Franka path.

## 4. Record one hardcoded pick episode

The hardcoded agent replaces only the physical GELLO device. It produces the
same style of absolute 8-D Panda command that a GELLO agent would produce.

```bash
CONFIG=/workspace/Mujoco_Sim/polymetis_lerobot_mujoco/configs/perfect_pick.yaml \
CAMERA_FLAG=--no-camera \
polymetis_lerobot_mujoco/scripts/record_hardcoded_pick.sh
```

Remove `CAMERA_FLAG=--no-camera` once the MuJoCo wrist camera is available to
OpenCV. Episodes are written below `lerobot.root` with keys named like LeRobot
observations/actions: `observation.state`, `observation.images.wrist`, and
`action`.

## 5. Train the LeRobot policy

After converting/registering the local dataset if required by your installed
LeRobot version, train with the included wrapper:

```bash
DATASET_REPO_ID=local/fer_mujoco_cube_pick \
OUTPUT_DIR=/home/fer_ros2_sim/data/lerobot_outputs/act_fer_mujoco_cube_pick \
polymetis_lerobot_mujoco/scripts/train_lerobot_act.sh
```

## 6. Execute the trained model through Polymetis

```bash
POLICY_PATH=/home/fer_ros2_sim/data/lerobot_outputs/act_fer_mujoco_cube_pick/checkpoints/last/pretrained_model \
CAMERA_FLAG=--no-camera \
polymetis_lerobot_mujoco/scripts/run_policy_rollout.sh
```

Again, remove `CAMERA_FLAG=--no-camera` after the wrist camera stream is ready.
The policy rollout uses the same Polymetis command path as recording.

## 7. Tune only the task waypoints

Tune `trajectory.waypoints` in `configs/perfect_pick.yaml` to your cube pose.
Keep the Polymetis endpoint, dataset metadata, and observation/action names
stable so the verification run remains comparable to the real GELLO pipeline.

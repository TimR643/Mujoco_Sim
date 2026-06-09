from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class OpenCVCameraConfig:
    device: int | str = 0
    width: int = 640
    height: int = 480
    fps: int = 30


class OpenCVCamera:
    def __init__(self, config: OpenCVCameraConfig) -> None:
        self.config = config
        self.capture = cv2.VideoCapture(config.device)
        if not self.capture.isOpened():
            raise RuntimeError(f"Could not open wrist camera device {config.device!r}.")
        self.capture.set(cv2.CAP_PROP_FRAME_WIDTH, config.width)
        self.capture.set(cv2.CAP_PROP_FRAME_HEIGHT, config.height)
        self.capture.set(cv2.CAP_PROP_FPS, config.fps)

    def read_rgb(self) -> np.ndarray:
        ok, frame_bgr = self.capture.read()
        if not ok:
            raise RuntimeError("Failed to read wrist camera frame.")
        return cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)

    def close(self) -> None:
        self.capture.release()

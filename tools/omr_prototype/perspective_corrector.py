"""
Perspective Corrector
Warps the detected OMR sheet quadrilateral into canonical standard coordinates.
"""

import numpy as np
from PIL import Image
from typing import Tuple


class PerspectiveCorrector:
    def __init__(self, target_width: int = 1200, target_height: int = 1650):
        self.target_width = target_width
        self.target_height = target_height

    def _compute_perspective_coeffs(self, dst_pts: np.ndarray, src_pts: np.ndarray) -> np.ndarray:
        """
        Computes 8 transformation coefficients for PIL Image.transform.
        Maps destination points (canonical) back to source points (input image).
        """
        matrix = []
        for (u, v), (x, y) in zip(dst_pts, src_pts):
            matrix.append([u, v, 1, 0, 0, 0, -x * u, -x * v])
            matrix.append([0, 0, 0, u, v, 1, -y * u, -y * v])
        A = np.array(matrix, dtype=np.float64)
        B = src_pts.reshape(8).astype(np.float64)
        coeffs = np.linalg.lstsq(A, B, rcond=None)[0]
        return coeffs

    def warp(self, img_rgb: np.ndarray, corners: np.ndarray) -> np.ndarray:
        """
        Warps input RGB image using 4 corners [TL, TR, BR, BL]
        into canonical size (target_width, target_height).
        """
        dst_pts = np.array([
            [0.0, 0.0],
            [float(self.target_width - 1), 0.0],
            [float(self.target_width - 1), float(self.target_height - 1)],
            [0.0, float(self.target_height - 1)],
        ], dtype=np.float32)

        coeffs = self._compute_perspective_coeffs(dst_pts, corners)
        pil_img = Image.fromarray(img_rgb)
        warped_pil = pil_img.transform(
            (self.target_width, self.target_height),
            Image.Transform.PERSPECTIVE,
            coeffs,
            Image.Resampling.BILINEAR,
        )
        return np.array(warped_pil, dtype=np.uint8)

"""
OMR Sheet Boundary Detector
Locates the 4 corners of the physical OMR sheet in the photograph.
"""

import numpy as np
from scipy.ndimage import label, binary_fill_holes, gaussian_filter
from typing import Optional, Tuple


class SheetDetector:
    def __init__(self, min_area_ratio: float = 0.20, target_aspect_ratio: float = 1.375):
        self.min_area_ratio = min_area_ratio
        self.target_aspect_ratio = target_aspect_ratio

    def order_corners(self, pts: np.ndarray) -> np.ndarray:
        """
        Orders 4 points as: [Top-Left, Top-Right, Bottom-Right, Bottom-Left].
        """
        pts = np.asarray(pts, dtype=np.float32)
        assert pts.shape == (4, 2), "Points must be 4x2"

        # Sum of coords: TL has minimum x+y, BR has maximum x+y
        s = pts.sum(axis=1)
        tl = pts[np.argmin(s)]
        br = pts[np.argmax(s)]

        # Difference (x - y): TR has maximum x-y, BL has minimum x-y
        diff = pts[:, 0] - pts[:, 1]
        tr = pts[np.argmax(diff)]
        bl = pts[np.argmin(diff)]

        return np.array([tl, tr, br, bl], dtype=np.float32)

    def detect(self, img_rgb: np.ndarray, raw_gray: np.ndarray) -> Tuple[Optional[np.ndarray], float, str]:
        """
        Detects sheet corners using raw grayscale contrast.
        Returns: (corners, confidence, message)
        corners is (4, 2) array: [TL, TR, BR, BL] or None.
        """
        h, w = raw_gray.shape[:2]
        total_area = float(h * w)

        # 1. Smooth slightly to eliminate high-frequency paper text noise
        smoothed = gaussian_filter(raw_gray, sigma=2.0)

        # Check contrast between background and sheet
        p_low = np.percentile(smoothed, 10)
        p_high = np.percentile(smoothed, 90)

        if (p_high - p_low) > 40:
            thresh_val = (p_low + p_high) / 2.0
            paper_mask = binary_fill_holes(smoothed > thresh_val)

            labeled, num_features = label(paper_mask)
            if num_features > 0:
                sizes = [np.sum(labeled == i) for i in range(1, num_features + 1)]
                best_idx = int(np.argmax(sizes)) + 1
                best_size = sizes[best_idx - 1]

                area_ratio = best_size / total_area
                if area_ratio >= self.min_area_ratio:
                    y_indices, x_indices = np.where(labeled == best_idx)
                    pts = np.column_stack((x_indices, y_indices))

                    # Subsample points for fast extreme point search
                    if len(pts) > 2000:
                        sub_indices = np.linspace(0, len(pts) - 1, 2000, dtype=int)
                        pts = pts[sub_indices]

                    s = pts[:, 0] + pts[:, 1]
                    tl = pts[np.argmin(s)]
                    br = pts[np.argmax(s)]

                    diff = pts[:, 0] - pts[:, 1]
                    tr = pts[np.argmax(diff)]
                    bl = pts[np.argmin(diff)]

                    corners = np.array([tl, tr, br, bl], dtype=np.float32)
                    ordered = self.order_corners(corners)

                    # Validate quadrilateral geometry
                    width_top = np.linalg.norm(ordered[1] - ordered[0])
                    width_bottom = np.linalg.norm(ordered[2] - ordered[3])
                    height_left = np.linalg.norm(ordered[3] - ordered[0])
                    height_right = np.linalg.norm(ordered[2] - ordered[1])

                    avg_w = (width_top + width_bottom) / 2.0
                    avg_h = (height_left + height_right) / 2.0

                    if avg_w > 50 and avg_h > 50:
                        aspect = avg_h / avg_w
                        if 1.05 <= aspect <= 1.85:
                            quad_area = avg_w * avg_h
                            aspect_score = 1.0 - min(0.3, abs(aspect - self.target_aspect_ratio) / self.target_aspect_ratio)
                            area_score = min(1.0, (quad_area / total_area) / 0.35)
                            confidence = float(np.clip(0.6 * area_score + 0.4 * aspect_score, 0.4, 1.0))
                            return ordered, float(confidence), "SHEET_DETECTED"

        # 2. Fallback: Full frame close-up photo
        corners = np.array([
            [0.0, 0.0],
            [float(w - 1), 0.0],
            [float(w - 1), float(h - 1)],
            [0.0, float(h - 1)],
        ], dtype=np.float32)

        return corners, 0.85, "FULL_FRAME_ASSUMED"

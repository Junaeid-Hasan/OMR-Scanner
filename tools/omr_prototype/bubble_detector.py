"""
Bubble Detector & Fill Score Analyzer
Analyzes circular ROIs to measure ink density and fill score without interference
from the outer printed circle boundary.
"""

import numpy as np
from typing import Dict, Tuple, NamedTuple
from tools.omr_prototype.omr_config import BubbleCoord, OMRTemplate, DEFAULT_TEMPLATE


class BubbleScore(NamedTuple):
    fill_score: float
    dark_pixel_ratio: float
    mean_darkness: float
    state: str  # "EMPTY", "FILLED", "UNCERTAIN"


class BubbleDetector:
    def __init__(self, template: OMRTemplate = DEFAULT_TEMPLATE):
        self.template = template

    def _sample_circle_mask(self, h: int, w: int, cx: float, cy: float, radius: float) -> np.ndarray:
        """Generates a boolean circular disc mask centered at (cx, cy)."""
        y_coords, x_coords = np.ogrid[:h, :w]
        dist_sq = (x_coords - cx) ** 2 + (y_coords - cy) ** 2
        return dist_sq <= (radius ** 2)

    def analyze_bubble(self, gray_warped: np.ndarray, coord: BubbleCoord) -> BubbleScore:
        """
        Calculates the fill score for a single bubble.
        - Excludes outer circle border by evaluating only r <= coord.inner_radius.
        - Uses local background normalization to resist uneven lighting and shadows.
        """
        h, w = gray_warped.shape[:2]
        cx, cy = coord.x, coord.y
        r_inner = coord.inner_radius
        r_outer = coord.radius

        # Bounding box for local analysis patch (radius + padding)
        pad = int(r_outer + 12)
        x0 = max(0, int(cx - pad))
        x1 = min(w, int(cx + pad + 1))
        y0 = max(0, int(cy - pad))
        y1 = min(h, int(cy + pad + 1))

        patch = gray_warped[y0:y1, x0:x1]
        ph, pw = patch.shape
        local_cx = cx - x0
        local_cy = cy - y0

        # Create inner ROI mask (strictly interior to printed circle)
        inner_mask = self._sample_circle_mask(ph, pw, local_cx, local_cy, r_inner)

        # Estimate local paper brightness using outer surrounding ring (r_outer+3 to r_outer+10)
        ring_mask = (
            self._sample_circle_mask(ph, pw, local_cx, local_cy, r_outer + 8)
            & ~self._sample_circle_mask(ph, pw, local_cx, local_cy, r_outer + 2)
        )

        ring_pixels = patch[ring_mask]
        if len(ring_pixels) > 10:
            local_paper_lum = float(np.percentile(ring_pixels, 85))
        else:
            local_paper_lum = float(np.percentile(patch, 85))

        local_paper_lum = max(50.0, local_paper_lum)

        inner_pixels = patch[inner_mask]
        if len(inner_pixels) == 0:
            return BubbleScore(fill_score=0.0, dark_pixel_ratio=0.0, mean_darkness=0.0, state="EMPTY")

        # Relative darkness relative to local paper: [0 = paper white, 1 = absolute black]
        rel_darkness = np.clip((local_paper_lum - inner_pixels) / local_paper_lum, 0.0, 1.0)

        # A pixel is considered marked if relative darkness is >= 0.22 and absolute difference >= 25
        ink_pixel_mask = (rel_darkness >= 0.22) & ((local_paper_lum - inner_pixels) >= 25.0)
        dark_pixel_ratio = float(np.mean(ink_pixel_mask))
        mean_darkness = float(np.mean(rel_darkness))

        # Composite fill score
        fill_score = 0.70 * dark_pixel_ratio + 0.30 * mean_darkness
        fill_score = float(np.clip(fill_score, 0.0, 1.0))

        # State classification
        if fill_score >= self.template.filled_threshold:
            state = "FILLED"
        elif fill_score < self.template.empty_threshold:
            state = "EMPTY"
        else:
            state = "UNCERTAIN"

        return BubbleScore(
            fill_score=round(fill_score, 4),
            dark_pixel_ratio=round(dark_pixel_ratio, 4),
            mean_darkness=round(mean_darkness, 4),
            state=state,
        )

    def analyze_all(self, gray_warped: np.ndarray) -> Dict[int, Dict[str, BubbleScore]]:
        """Analyzes all 30 questions (120 bubbles) and returns structured scores."""
        results = {}
        for q_num, options_dict in self.template.bubbles.items():
            results[q_num] = {}
            for opt, coord in options_dict.items():
                results[q_num][opt] = self.analyze_bubble(gray_warped, coord)
        return results

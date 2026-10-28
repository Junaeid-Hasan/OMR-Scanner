"""
OMR Configuration & Template System
Defines canonical sheet geometry, question coordinates, and classification thresholds.
"""

from dataclasses import dataclass
from typing import Dict, List, Tuple


@dataclass(frozen=True)
class BubbleCoord:
    x: float
    y: float
    radius: float
    inner_radius: float


@dataclass
class OMRTemplate:
    canonical_width: int = 1200
    canonical_height: int = 1650
    total_questions: int = 30
    options: Tuple[str, ...] = ("A", "B", "C", "D")

    # Thresholds
    empty_threshold: float = 0.18
    filled_threshold: float = 0.42
    uncertainty_margin: float = 0.12

    # Coordinate mapping: question_number (1..30) -> {"A": BubbleCoord, "B": ...}
    bubbles: Dict[int, Dict[str, BubbleCoord]] = None

    def __post_init__(self):
        if self.bubbles is None:
            self.bubbles = self._generate_default_coordinates()

    def _generate_default_coordinates(self) -> Dict[int, Dict[str, BubbleCoord]]:
        """
        Generates standard coordinates for the 3-section layout:
        Section 1: Questions 1–10  (Left column)
        Section 2: Questions 11–20 (Center column)
        Section 3: Questions 21–30 (Right column)
        """
        bubbles: Dict[int, Dict[str, BubbleCoord]] = {}

        # Column X start positions for the first bubble (A)
        # Columns: Section 1 (x=160), Section 2 (x=530), Section 3 (x=900)
        col_x_starts = [160, 530, 900]
        bubble_dx = 52       # horizontal distance between A, B, C, D centers
        row_y_start = 450    # vertical start for row 1 in each section
        row_dy = 96          # vertical spacing between consecutive questions
        radius = 18.0
        inner_radius = 12.0  # inner sampling radius (excludes outer printed circle)

        sections = [
            (range(1, 11), col_x_starts[0]),
            (range(11, 21), col_x_starts[1]),
            (range(21, 31), col_x_starts[2]),
        ]

        for q_range, start_x in sections:
            for idx, q_num in enumerate(q_range):
                row_y = row_y_start + idx * row_dy
                bubbles[q_num] = {}
                for opt_idx, opt in enumerate(self.options):
                    bx = start_x + opt_idx * bubble_dx
                    bubbles[q_num][opt] = BubbleCoord(
                        x=float(bx),
                        y=float(row_y),
                        radius=radius,
                        inner_radius=inner_radius,
                    )

        return bubbles


# Default global template instance
DEFAULT_TEMPLATE = OMRTemplate()

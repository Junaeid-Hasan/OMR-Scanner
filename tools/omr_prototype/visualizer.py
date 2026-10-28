"""
OMR Debug Visualizer
Generates an annotated visual inspection image showing:
- Green: Detected selected bubble
- Gray: Clean empty bubbles
- Red: Multiple filled bubbles (invalid)
- Yellow/Orange: Uncertain marks requiring review
- Question labels and fill scores
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from typing import Dict
from tools.omr_prototype.omr_config import OMRTemplate, DEFAULT_TEMPLATE
from tools.omr_prototype.answer_classifier import DetectedAnswer
from tools.omr_prototype.bubble_detector import BubbleScore


class DebugVisualizer:
    def __init__(self, template: OMRTemplate = DEFAULT_TEMPLATE):
        self.template = template

    def draw_annotations(
        self,
        warped_rgb: np.ndarray,
        detected_answers: Dict[int, DetectedAnswer],
        bubble_scores: Dict[int, Dict[str, BubbleScore]],
        sheet_corners: np.ndarray = None,
    ) -> Image.Image:
        """
        Renders debug overlays on top of the canonical warped sheet image.
        """
        img = Image.fromarray(warped_rgb).convert("RGB")
        draw = ImageDraw.Draw(img)

        # Colors (RGB)
        COLOR_EMPTY = (160, 160, 160)     # Gray
        COLOR_SELECTED = (20, 180, 20)    # Vibrant Green
        COLOR_MULTIPLE = (230, 40, 40)    # Red
        COLOR_UNCERTAIN = (245, 175, 20)  # Amber / Yellow
        COLOR_TEXT = (20, 20, 20)

        for q_num, ans in detected_answers.items():
            q_bubbles = self.template.bubbles[q_num]
            classification = ans.classification

            # Question status badge position (left of bubble A)
            first_bubble = q_bubbles["A"]
            badge_x = first_bubble.x - 70
            badge_y = first_bubble.y - 10

            # Draw question label: e.g. "Q1: C" or "Q1: BLANK"
            summary_text = f"Q{q_num}: {ans.primary_answer or classification}"
            draw.text((badge_x, badge_y), summary_text, fill=COLOR_TEXT)

            for opt, coord in q_bubbles.items():
                cx, cy = coord.x, coord.y
                r = coord.radius
                score_info = bubble_scores[q_num][opt]
                score = score_info.fill_score

                # Determine bubble ring color and fill highlight
                if classification == "SINGLE" and opt in ans.selected_options:
                    ring_color = COLOR_SELECTED
                    fill_color = (20, 180, 20, 60)
                    line_width = 3
                elif classification == "MULTIPLE" and opt in ans.selected_options:
                    ring_color = COLOR_MULTIPLE
                    fill_color = (230, 40, 40, 70)
                    line_width = 3
                elif classification == "UNCERTAIN" and opt in ans.selected_options:
                    ring_color = COLOR_UNCERTAIN
                    fill_color = (245, 175, 20, 70)
                    line_width = 3
                else:
                    ring_color = COLOR_EMPTY
                    fill_color = None
                    line_width = 1

                # Draw outer inspection ring
                bbox = [cx - r, cy - r, cx + r, cy + r]
                draw.ellipse(bbox, outline=ring_color, width=line_width)

                # Draw inner sampling circle marker
                inner_r = coord.inner_radius
                inner_bbox = [cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r]
                draw.ellipse(inner_bbox, outline=ring_color, width=1)

                # Draw tiny score text below bubble
                score_text = f"{int(round(score * 100))}%"
                draw.text((cx - 10, cy + r + 2), score_text, fill=(70, 70, 70))

        # Add top banner with legend
        banner_h = 45
        draw.rectangle([0, 0, self.template.canonical_width, banner_h], fill=(245, 245, 245))
        draw.text((20, 14), "OMR Scanner Prototype v1.0", fill=(10, 10, 10))

        # Legend items
        legend_items = [
            ("Green: Single Answer", COLOR_SELECTED),
            ("Gray: Empty", COLOR_EMPTY),
            ("Red: Multiple", COLOR_MULTIPLE),
            ("Yellow: Uncertain (Review)", COLOR_UNCERTAIN),
        ]
        leg_x = 350
        for text, col in legend_items:
            draw.rectangle([leg_x, 15, leg_x + 15, 30], fill=col)
            draw.text((leg_x + 22, 14), text, fill=(20, 20, 20))
            leg_x += 210

        return img

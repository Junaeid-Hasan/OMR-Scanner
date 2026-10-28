"""
Automated Test Suite for OMR Computer Vision Engine (Phase 1)
Tests:
- Clean blank sheet (no false positive fills on printed circles)
- Known ground truth answer patterns across Section 1, 2, 3
- Multiple mark detection
- Blank detection
- Uncertain / faint mark handling
- Perspective distortion & desk placement simulation
"""

import os
import sys
import unittest
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from tools.omr_prototype.omr_engine import OMRScanner
from tools.omr_prototype.generate_sample_sheet import (
    generate_clean_sheet,
    create_sample_marked_sheet,
    simulate_phone_photo,
)


class TestOMRComputerVisionEngine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scanner = OMRScanner()
        os.makedirs("assets/test_images", exist_ok=True)
        os.makedirs("output", exist_ok=True)

    def test_01_clean_sheet_all_blank(self):
        """Tests that a clean sheet with 0 student marks detects 30 BLANK answers."""
        clean_img = generate_clean_sheet()
        img_path = "assets/test_images/test_clean_sheet.png"
        clean_img.save(img_path)

        rgb_arr = np.array(clean_img, dtype=np.uint8)
        result = self.scanner.scan(rgb_arr)

        self.assertEqual(result.status, "SUCCESS")
        self.assertEqual(len(result.detected_answers), 30)

        for q_num, ans in result.detected_answers.items():
            self.assertEqual(
                ans.classification,
                "BLANK",
                f"Question {q_num} should be BLANK but got {ans.classification} (scores: {ans.bubble_scores})",
            )
            self.assertEqual(len(ans.selected_options), 0)

    def test_02_known_ground_truth_marks(self):
        """Tests precision on defined answers across all 3 vertical sections."""
        ground_truth = {
            # Section 1 (Q 1 - 10)
            1: "A", 2: "B", 3: "C", 4: "D", 5: "A",
            6: "B", 7: "C", 8: "D", 9: "A", 10: "B",
            # Section 2 (Q 11 - 20)
            11: "C", 12: "D", 13: "A", 14: "B", 15: "BLANK",
            16: "C", 17: "D", 18: "A", 19: "B", 20: "C",
            # Section 3 (Q 21 - 30)
            21: "D", 22: "A", 23: "B", 24: "C", 25: ["A", "B"], # Multiple
            26: "D", 27: "A", 28: "B", 29: "C", 30: "LIGHT_D",  # Faint mark
        }

        marked_img = create_sample_marked_sheet(ground_truth)
        img_path = "assets/test_images/test_marked_sheet.png"
        marked_img.save(img_path)

        rgb_arr = np.array(marked_img, dtype=np.uint8)
        result = self.scanner.scan(rgb_arr)

        self.assertEqual(len(result.detected_answers), 30)

        correct_singles = 0
        for q_num, expected in ground_truth.items():
            detected = result.detected_answers[q_num]

            if expected == "BLANK":
                self.assertEqual(detected.classification, "BLANK", f"Q{q_num} expected BLANK")
            elif isinstance(expected, list):
                self.assertEqual(detected.classification, "MULTIPLE", f"Q{q_num} expected MULTIPLE")
                self.assertSetEqual(set(detected.selected_options), set(expected))
            elif expected.startswith("LIGHT_"):
                # Light mark must be either UNCERTAIN or detected with warning
                self.assertIn(detected.classification, ["UNCERTAIN", "SINGLE"], f"Q{q_num} faint mark handling")
            else:
                self.assertEqual(detected.classification, "SINGLE", f"Q{q_num} expected SINGLE")
                self.assertEqual(detected.primary_answer, expected, f"Q{q_num} expected {expected}")
                self.assertGreaterEqual(detected.confidence, 0.70)
                correct_singles += 1

        self.assertEqual(correct_singles, 27)

    def test_03_camera_perspective_distortion(self):
        """Tests sheet boundary detection and perspective unwarping on desk background."""
        ground_truth = {
            1: "C", 5: "B", 10: "D", 15: "A", 20: "C", 25: "B", 30: "D",
        }
        marked_img = create_sample_marked_sheet(ground_truth)
        desk_photo, true_corners = simulate_phone_photo(marked_img, rotation_deg=2.5, tilt_x=20, tilt_y=15)
        photo_path = "assets/test_images/test_desk_photo.png"
        desk_photo.save(photo_path)

        rgb_arr = np.array(desk_photo, dtype=np.uint8)
        result = self.scanner.scan(rgb_arr)

        self.assertIsNotNone(result.warped_rgb)
        self.assertGreaterEqual(result.quality_metrics["sheet_detection_confidence"], 0.70)

        # Check marked questions
        for q_num, expected in ground_truth.items():
            detected = result.detected_answers[q_num]
            self.assertEqual(detected.classification, "SINGLE", f"Q{q_num} expected SINGLE under distortion")
            self.assertEqual(detected.primary_answer, expected, f"Q{q_num} answer under distortion")


if __name__ == "__main__":
    unittest.main()

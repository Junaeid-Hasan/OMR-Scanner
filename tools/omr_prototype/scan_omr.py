"""
OMR Scanner CLI Runner (Phase 1 Milestone Entrypoint)
Usage:
    python3 tools/omr_prototype/scan_omr.py --image <path_to_image> [--output <debug_image_path>]
"""

import argparse
import json
import os
import sys
import numpy as np
from PIL import Image

# Ensure tools package is importable
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from tools.omr_prototype.omr_engine import OMRScanner
from tools.omr_prototype.visualizer import DebugVisualizer


def run_scanner(image_path: str, output_path: str = "output/annotated_result.png"):
    print("==================================================")
    print(" OMR SCANNER PROTOTYPE - PHASE 1")
    print(f" Input Image: {image_path}")
    print("==================================================\n")

    if not os.path.exists(image_path):
        print(f"Error: Input file does not exist: {image_path}", file=sys.stderr)
        sys.exit(1)

    pil_img = Image.open(image_path).convert("RGB")
    img_rgb = np.array(pil_img, dtype=np.uint8)

    scanner = OMRScanner()
    result = scanner.scan(img_rgb)

    print(f"Overall Status: {result.status}")
    print(f"Message:        {result.message}")
    print(f"Quality Metrics: {json.dumps(result.quality_metrics, indent=2)}\n")

    header_q = "Question"
    header_a = "Answer"
    header_c = "Classification"
    header_cf = "Confidence"
    header_s = "Option Fill Scores (A, B, C, D)"
    print(f"{header_q:<10} | {header_a:<8} | {header_c:<16} | {header_cf:<10} | {header_s}")
    print("-" * 80)

    for q_num in sorted(result.detected_answers.keys()):
        ans = result.detected_answers[q_num]
        ans_str = ans.primary_answer or (",".join(ans.selected_options) if ans.selected_options else "BLANK")
        scores_str = "  ".join([f"{opt}:{s:.2f}" for opt, s in sorted(ans.bubble_scores.items())])
        q_label = f"Q{q_num}"
        print(f"{q_label:<10} | {ans_str:<8} | {ans.classification:<16} | {ans.confidence:<10.2f} | {scores_str}")

    print("-" * 80)

    # Save annotated debug image
    if result.warped_rgb is not None:
        visualizer = DebugVisualizer()
        annotated_img = visualizer.draw_annotations(
            result.warped_rgb,
            result.detected_answers,
            result.bubble_scores,
            result.sheet_corners,
        )
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        annotated_img.save(output_path)
        print(f"\n[Annotated Debug Image Saved] -> {output_path}")

    return result


def main():
    parser = argparse.ArgumentParser(description="Scan OMR sheet image and extract answers.")
    parser.add_argument("--image", required=True, help="Path to input OMR photograph/image")
    parser.add_argument("--output", default="output/annotated_result.png", help="Path to save annotated debug image")
    args = parser.parse_args()

    run_scanner(args.image, args.output)


if __name__ == "__main__":
    main()

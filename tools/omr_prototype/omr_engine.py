"""
OMR Computer Vision Engine
High-level orchestrator connecting Preprocessor, SheetDetector, PerspectiveCorrector,
BubbleDetector, and AnswerClassifier.
"""

import numpy as np
from dataclasses import dataclass
from typing import Dict, Optional, Any
from tools.omr_prototype.omr_config import OMRTemplate, DEFAULT_TEMPLATE
from tools.omr_prototype.preprocessor import ImagePreprocessor
from tools.omr_prototype.sheet_detector import SheetDetector
from tools.omr_prototype.perspective_corrector import PerspectiveCorrector
from tools.omr_prototype.bubble_detector import BubbleDetector, BubbleScore
from tools.omr_prototype.answer_classifier import AnswerClassifier, DetectedAnswer
from tools.omr_prototype.visualizer import DebugVisualizer


@dataclass
class ScanResult:
    status: str  # "SUCCESS", "SCAN_UNCERTAIN", "FAILED"
    message: str
    detected_answers: Dict[int, DetectedAnswer]
    bubble_scores: Dict[int, Dict[str, BubbleScore]]
    quality_metrics: Dict[str, Any]
    warped_rgb: Optional[np.ndarray] = None
    sheet_corners: Optional[np.ndarray] = None


class OMRScanner:
    def __init__(self, template: OMRTemplate = DEFAULT_TEMPLATE):
        self.template = template
        self.preprocessor = ImagePreprocessor()
        self.sheet_detector = SheetDetector()
        self.perspective_corrector = PerspectiveCorrector(
            target_width=template.canonical_width,
            target_height=template.canonical_height,
        )
        self.bubble_detector = BubbleDetector(template)
        self.answer_classifier = AnswerClassifier(template)
        self.visualizer = DebugVisualizer(template)

    def scan(self, img_rgb: np.ndarray) -> ScanResult:
        """
        Executes the deterministic end-to-end OMR scanning pipeline on an input RGB image.
        """
        # 1. Preprocess input image
        prep = self.preprocessor.process(img_rgb)
        scaled_rgb = prep["normalized_rgb"]
        raw_gray = prep["raw_gray"]
        scale = prep["scale"]

        # 2. Detect sheet boundary and corners
        corners_scaled, sheet_conf, detect_msg = self.sheet_detector.detect(scaled_rgb, raw_gray)
        if corners_scaled is None or sheet_conf < 0.35:
            return ScanResult(
                status="SCAN_UNCERTAIN",
                message=f"Sheet could not be located reliably ({detect_msg}).",
                detected_answers={},
                bubble_scores={},
                quality_metrics={"sheet_detection_confidence": sheet_conf},
            )

        # Map corners back to original image space
        corners_orig = corners_scaled / scale

        # 3. Perspective correction to canonical coordinate system
        warped_rgb = self.perspective_corrector.warp(img_rgb, corners_orig)

        # 4. Prepare warped grayscale image with illumination compensation
        warped_gray = self.preprocessor.to_grayscale(warped_rgb)
        warped_gray = self.preprocessor.compensate_illumination(warped_gray)

        # 5. Extract bubble ROIs and compute fill scores
        bubble_scores = self.bubble_detector.analyze_all(warped_gray)

        # 6. Classify each question answer
        detected_answers = self.answer_classifier.classify_all(bubble_scores)

        # 7. Quality & Confidence Analysis
        confidences = [ans.confidence for ans in detected_answers.values()]
        avg_confidence = float(np.mean(confidences)) if confidences else 0.0
        uncertain_count = sum(1 for ans in detected_answers.values() if ans.classification == "UNCERTAIN")

        quality = {
            "sheet_detection_confidence": round(float(sheet_conf), 2),
            "average_question_confidence": round(avg_confidence, 2),
            "uncertain_questions_count": uncertain_count,
            "detection_method": detect_msg,
        }

        status = "SUCCESS" if (sheet_conf >= 0.70 and uncertain_count <= 5) else "UNCERTAIN"

        return ScanResult(
            status=status,
            message="Sheet processed successfully" if status == "SUCCESS" else "Some marks require teacher review",
            detected_answers=detected_answers,
            bubble_scores=bubble_scores,
            quality_metrics=quality,
            warped_rgb=warped_rgb,
            sheet_corners=corners_orig,
        )

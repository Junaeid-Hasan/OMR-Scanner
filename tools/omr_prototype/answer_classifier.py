"""
Answer Classifier & Decision Engine
Evaluates bubble fill scores per question to determine SINGLE, BLANK, MULTIPLE, or UNCERTAIN.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional
from tools.omr_prototype.omr_config import OMRTemplate, DEFAULT_TEMPLATE
from tools.omr_prototype.bubble_detector import BubbleScore


@dataclass
class DetectedAnswer:
    question_number: int
    selected_options: List[str]
    classification: str       # "SINGLE", "BLANK", "MULTIPLE", "UNCERTAIN"
    confidence: float         # 0.0 to 1.0
    bubble_scores: Dict[str, float]
    primary_answer: Optional[str] = None

    def __post_init__(self):
        if self.classification == "SINGLE" and len(self.selected_options) == 1:
            self.primary_answer = self.selected_options[0]
        else:
            self.primary_answer = None


class AnswerClassifier:
    def __init__(self, template: OMRTemplate = DEFAULT_TEMPLATE):
        self.template = template

    def classify_question(self, question_number: int, bubble_scores: Dict[str, BubbleScore]) -> DetectedAnswer:
        """
        Classifies a single question based on its 4 option bubble scores.
        """
        raw_scores = {opt: score.fill_score for opt, score in bubble_scores.items()}
        # Sort options descending by score
        sorted_opts = sorted(raw_scores.items(), key=lambda kv: kv[1], reverse=True)
        top_opt, top_score = sorted_opts[0]
        second_opt, second_score = sorted_opts[1]

        t_empty = self.template.empty_threshold
        t_filled = self.template.filled_threshold
        t_margin = self.template.uncertainty_margin

        # 1. BLANK: Top score is clearly below empty threshold
        if top_score < t_empty:
            confidence = round(float(np_clip(1.0 - (top_score / max(0.01, t_empty)) * 0.3, 0.70, 1.0)), 2)
            return DetectedAnswer(
                question_number=question_number,
                selected_options=[],
                classification="BLANK",
                confidence=confidence,
                bubble_scores=raw_scores,
            )

        # Count how many bubbles meet or exceed the filled threshold
        filled_opts = [opt for opt, s in sorted_opts if s >= t_filled]

        # 2. MULTIPLE: Two or more distinct bubbles are filled
        if len(filled_opts) >= 2:
            return DetectedAnswer(
                question_number=question_number,
                selected_options=filled_opts,
                classification="MULTIPLE",
                confidence=0.95,
                bubble_scores=raw_scores,
            )

        # 3. SINGLE: Exactly one bubble is filled AND dominates second place by margin
        if len(filled_opts) == 1 and (top_score - second_score) >= t_margin:
            # Margin confidence calculation
            margin_ratio = (top_score - second_score) / max(0.01, top_score)
            confidence = round(float(np_clip(0.70 + 0.30 * margin_ratio, 0.70, 1.0)), 2)
            return DetectedAnswer(
                question_number=question_number,
                selected_options=[top_opt],
                classification="SINGLE",
                confidence=confidence,
                bubble_scores=raw_scores,
            )

        # 4. UNCERTAIN: Mark is in intermediate zone or runner-up is too close
        candidate_options = [opt for opt, s in sorted_opts if s >= t_empty]
        return DetectedAnswer(
            question_number=question_number,
            selected_options=candidate_options,
            classification="UNCERTAIN",
            confidence=round(float(top_score), 2),
            bubble_scores=raw_scores,
        )

    def classify_all(self, all_bubble_scores: Dict[int, Dict[str, BubbleScore]]) -> Dict[int, DetectedAnswer]:
        """Classifies all 30 questions."""
        results = {}
        for q_num, scores in all_bubble_scores.items():
            results[q_num] = self.classify_question(q_num, scores)
        return results


def np_clip(val: float, low: float, high: float) -> float:
    return max(low, min(high, val))

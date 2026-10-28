import 'dart:math';
import 'package:image/image.dart' as img;
import '../../models/detected_answer.dart';
import '../layout/layout_detector.dart';

/// Evaluates bubble ink density and classifies each question
/// using question-local illumination normalization.
class BubbleClassifier {
  final double emptyThreshold;
  final double filledThreshold;
  final double marginThreshold;
  final double multipleThreshold;

  const BubbleClassifier({
    this.emptyThreshold = 0.25,
    this.filledThreshold = 0.40,
    this.marginThreshold = 0.15,
    this.multipleThreshold = 0.40,
  });

  /// Evaluates all question rows in [layout] against canonical [image].
  Map<int, DetectedAnswer> classifyAll(img.Image image, DetectedLayout layout) {
    final results = <int, DetectedAnswer>{};
    final otsuThresh = _computeOtsu(image);

    for (final entry in layout.questionRows.entries) {
      final qNum = entry.key;
      final qRow = entry.value;
      results[qNum] = classifyRow(image, qRow, globalOtsuThreshold: otsuThresh);
    }

    return results;
  }

  /// Classifies a single question row using Otsu circular mask fill counting
  /// matching the Python evaluate_answers methodology.
  DetectedAnswer classifyRow(
    img.Image image,
    DetectedQuestionRow qRow, {
    int? globalOtsuThreshold,
  }) {
    final otsuThresh = globalOtsuThreshold ?? _computeOtsu(image);
    final bubbleScores = <String, double>{};

    for (final optEntry in qRow.bubbles.entries) {
      final opt = optEntry.key;
      final bubble = optEntry.value;

      final cx = bubble.pixelX;
      final cy = bubble.pixelY;
      final r = bubble.radius;
      final sampleR = (r * 0.75).round();
      final sampleR2 = sampleR * sampleR;
      final circleArea = pi * sampleR2;

      int otsuDarkPixels = 0;

      for (int dy = -sampleR; dy <= sampleR; dy++) {
        for (int dx = -sampleR; dx <= sampleR; dx++) {
          if (dx * dx + dy * dy <= sampleR2) {
            final px = (cx + dx).round();
            final py = (cy + dy).round();
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              final p = image.getPixel(px, py);
              final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
              if (lum < otsuThresh) {
                otsuDarkPixels++;
              }
            }
          }
        }
      }

      final fillRatio = circleArea > 0 ? (otsuDarkPixels / circleArea) : 0.0;
      bubbleScores[opt] = double.parse(fillRatio.clamp(0.0, 1.0).toStringAsFixed(3));
    }

    final sortedEntries = bubbleScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topEntry = sortedEntries[0];
    final secondEntry = sortedEntries.length > 1 ? sortedEntries[1] : null;

    final double topScore = topEntry.value;
    final double secondScore = secondEntry?.value ?? 0.0;

    final isFilled = topScore >= filledThreshold ||
        (topScore >= 0.38 && (topScore - secondScore) >= marginThreshold);
    final isDistinct = (topScore - secondScore) >= marginThreshold; // >= 0.15

    if (isFilled && isDistinct) {
      // Clean SINGLE answer
      final selected = topEntry.key;
      return DetectedAnswer(
        questionNumber: qRow.questionNumber,
        selectedOptions: [selected],
        classification: AnswerClassification.single,
        confidence: min(0.99, max(0.85, topScore)),
        bubbleScores: bubbleScores,
        primaryAnswer: selected,
      );
    } else if (isFilled && !isDistinct && secondScore > multipleThreshold) {
      // MULTIPLE marks detected
      final marked = sortedEntries.where((e) => e.value > filledThreshold).map((e) => e.key).toList();
      return DetectedAnswer(
        questionNumber: qRow.questionNumber,
        selectedOptions: marked,
        classification: AnswerClassification.multiple,
        confidence: min(0.95, topScore),
        bubbleScores: bubbleScores,
      );
    } else if (isFilled && !isDistinct) {
      // UNCERTAIN mark (faint or smudge)
      return DetectedAnswer(
        questionNumber: qRow.questionNumber,
        selectedOptions: [topEntry.key],
        classification: AnswerClassification.uncertain,
        confidence: 0.50,
        bubbleScores: bubbleScores,
        primaryAnswer: topEntry.key,
      );
    } else {
      // BLANK question
      return DetectedAnswer(
        questionNumber: qRow.questionNumber,
        selectedOptions: [],
        classification: AnswerClassification.blank,
        confidence: min(0.99, max(0.85, 1.0 - topScore)),
        bubbleScores: bubbleScores,
      );
    }
  }

  /// Computes Otsu global threshold on [image].
  int _computeOtsu(img.Image image) {
    final hist = List<int>.filled(256, 0);
    final w = image.width;
    final h = image.height;
    int total = 0;

    for (int y = 0; y < h; y += 2) {
      for (int x = 0; x < w; x += 2) {
        final p = image.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        hist[lum]++;
        total++;
      }
    }

    double sumTotal = 0;
    for (int i = 0; i < 256; i++) {
      sumTotal += i * hist[i];
    }

    double sumB = 0;
    int weightB = 0;
    double maxVar = 0;
    int threshold = 128;

    for (int i = 0; i < 256; i++) {
      weightB += hist[i];
      if (weightB == 0) continue;
      final weightF = total - weightB;
      if (weightF == 0) break;

      sumB += i * hist[i];
      final meanB = sumB / weightB;
      final meanF = (sumTotal - sumB) / weightF;
      final varBetween = weightB * weightF * (meanB - meanF) * (meanB - meanF);

      if (varBetween > maxVar) {
        maxVar = varBetween;
        threshold = i;
      }
    }

    return threshold;
  }
}

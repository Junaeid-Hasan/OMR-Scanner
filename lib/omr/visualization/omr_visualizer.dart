import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../models/detected_answer.dart';
import '../layout/layout_detector.dart';

class VisualizationResult {
  final Uint8List bytes;
  final String? filePath;

  const VisualizationResult({
    required this.bytes,
    this.filePath,
  });
}

/// Renders visual debug overlays showing detected layout,
/// bubble centers, and answer classifications.
class OMRVisualizer {
  /// Generates an annotated review image on the canonical [sourceImage].
  static Future<VisualizationResult> generateAnnotatedImage({
    required img.Image sourceImage,
    required DetectedLayout layout,
    required Map<int, DetectedAnswer> answers,
    required String originalPath,
  }) async {
    final annotated = img.Image.from(sourceImage);

    // Color definitions matching detect_omr.py
    final candidateBlue = img.ColorRgb8(120, 180, 240);
    final detectedGreen = img.ColorRgb8(0, 220, 0);
    final multiplePurple = img.ColorRgb8(180, 0, 220);
    final uncertainAmber = img.ColorRgb8(255, 160, 0);
    final blankRed = img.ColorRgb8(220, 30, 30);

    for (final entry in layout.questionRows.entries) {
      final qNum = entry.key;
      final qRow = entry.value;
      final ans = answers[qNum];

      for (final optEntry in qRow.bubbles.entries) {
        final opt = optEntry.key;
        final bubble = optEntry.value;
        final bx = bubble.pixelX.round();
        final by = bubble.pixelY.round();
        final r = bubble.radius.round();

        // 1. Draw candidate bubble outline ring in subtle blue
        img.drawCircle(annotated, x: bx, y: by, radius: r, color: candidateBlue);

        // 2. Draw thick detected answer circle if selected
        final isSelected = ans?.selectedOptions.contains(opt) ?? false;
        if (isSelected && ans != null) {
          img.ColorRgb8 color;
          switch (ans.classification) {
            case AnswerClassification.single:
              color = detectedGreen;
              break;
            case AnswerClassification.multiple:
              color = multiplePurple;
              break;
            case AnswerClassification.uncertain:
              color = uncertainAmber;
              break;
            case AnswerClassification.blank:
              color = blankRed;
              break;
          }

          // Draw bold multi-pixel circle matching detect_omr.py
          img.drawCircle(annotated, x: bx, y: by, radius: r - 1, color: color);
          img.drawCircle(annotated, x: bx, y: by, radius: r, color: color);
          img.drawCircle(annotated, x: bx, y: by, radius: r + 1, color: color);
          img.drawCircle(annotated, x: bx, y: by, radius: r + 2, color: color);
          img.drawCircle(annotated, x: bx, y: by, radius: r + 3, color: color);
        }
      }
    }

    final jpgBytes = Uint8List.fromList(img.encodeJpg(annotated, quality: 90));
    String? outPath;

    try {
      final tempDir = Directory('${Directory.systemTemp.path}/omr_annotated');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      outPath = '${tempDir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(jpgBytes);
    } catch (_) {
      // Fallback: try direct systemTemp
      try {
        outPath = '${Directory.systemTemp.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(outPath).writeAsBytes(jpgBytes);
      } catch (_) {}
    }

    return VisualizationResult(
      bytes: jpgBytes,
      filePath: outPath,
    );
  }
}

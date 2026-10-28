import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import '../models/detected_answer.dart';
import '../models/scan_result.dart';
import '../omr/analysis/bubble_classifier.dart';
import '../omr/detection/class_9_10_detector.dart';
import '../omr/detection/sheet_detector.dart';
import '../omr/geometry/quadrilateral.dart';
import '../omr/geometry/homography.dart';
import '../omr/layout/layout_detector.dart';
import '../omr/template/omr_template.dart';
import '../omr/visualization/omr_visualizer.dart';

/// Production-grade Optical Mark Recognition (OMR) service.
///
/// Implements a complete geometric computer vision pipeline:
/// 1. Sheet Localization (contrast-based document boundary & corner detection)
/// 2. Geometric Validation (convexity, aspect ratio, area constraints)
/// 3. Perspective Correction (3x3 Projective Homography Warping to canonical representation)
/// 4. Layout Structure Discovery (column regions, question rows, bubble groups)
/// 5. Dynamic Bubble Center Snapping (local luminance gradient alignment)
/// 6. Question-Local Illumination Normalization (shadow- and exposure-invariant fill scoring)
/// 7. Multi-stage Pipeline Validation and Debug Visualizer Generation
class OmrService {
  final OMRTemplate template;
  final SheetDetector sheetDetector;
  final LayoutDetector layoutDetector;
  final BubbleClassifier bubbleClassifier;
  final Class910Detector class910Detector;

  OmrService({
    OMRTemplate? template,
    SheetDetector? sheetDetector,
    LayoutDetector? layoutDetector,
    BubbleClassifier? bubbleClassifier,
    Class910Detector? class910Detector,
  })  : template = template ?? OMRTemplate(),
        sheetDetector = sheetDetector ?? const SheetDetector(),
        layoutDetector = layoutDetector ?? const LayoutDetector(),
        bubbleClassifier = bubbleClassifier ?? const BubbleClassifier(),
        class910Detector = class910Detector ?? const Class910Detector();

  /// Scans any OMR sheet image offline using deterministic geometric computer vision.
  /// Supports both 'class_6_8' and 'class_9_10' modes.
  /// Optionally accepts a pre-detected [detectedQuad] corner quadrilateral.
  Future<ScanResult> scanImage(
    String imagePath, {
    String classMode = 'class_6_8',
    Quadrilateral? detectedQuad,
  }) async {
    try {
      // 1. Load image bytes (supports device storage or bundle assets)
      Uint8List? bytes;
      final file = File(imagePath);

      if (await file.exists()) {
        bytes = await file.readAsBytes();
      } else if (imagePath.startsWith('assets/')) {
        try {
          final data = await rootBundle.load(imagePath);
          bytes = data.buffer.asUint8List();
        } catch (_) {
          final fallback = File(imagePath);
          if (await fallback.exists()) {
            bytes = await fallback.readAsBytes();
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        return ScanResult(
          status: ScanStatus.failed,
          message: 'Image file does not exist on device.',
          detectedAnswers: const {},
          sheetDetectionConfidence: 0.0,
          classMode: classMode,
        );
      }

      // If classMode is class_9_10, dispatch to dedicated Class 9-10 detector
      if (classMode == 'class_9_10') {
        return await class910Detector.processSheet(
          imagePath,
          bytes,
          detectedQuad: detectedQuad,
        );
      }

      // 2. Decode image and normalize EXIF orientation
      var rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        return const ScanResult(
          status: ScanStatus.failed,
          message: 'Could not decode image format.',
          detectedAnswers: {},
          sheetDetectionConfidence: 0.0,
        );
      }
      rawImage = img.bakeOrientation(rawImage);
      debugPrint('[OMR:INPUT] Image: $imagePath | Size: ${bytes.length} bytes | Decoded: ${rawImage.width}x${rawImage.height}');

      // 3. Stage 1: Detect Sheet Boundaries & Corners
      final sheetResult = (detectedQuad != null && detectedQuad.isValid())
          ? SheetDetectionResult(
              quad: detectedQuad,
              confidence: 0.95,
              isCropped: false,
              message: 'Using live detected sheet quadrilateral',
            )
          : sheetDetector.detectSheet(rawImage);
      debugPrint('[OMR:BORDER] Located: isReliable=${sheetResult.isReliable}, isCropped=${sheetResult.isCropped}, message=${sheetResult.message}');
      if (!sheetResult.isReliable) {
        return ScanResult(
          status: ScanStatus.failed,
          message: 'Unable to reliably locate OMR sheet: ${sheetResult.message}',
          detectedAnswers: {},
          sheetDetectionConfidence: sheetResult.confidence,
          imagePath: imagePath,
          classMode: classMode,
        );
      }

      final quad = sheetResult.quad;

      // 4. Stage 2: Perspective Correction / Homography Normalization
      // Canonical canvas dimensions matching the standardized Bangla OMR layout
      final isPortrait = quad.targetMaxHeight > quad.targetMaxWidth;
      final int targetW = isPortrait ? 1120 : 1536;
      final int targetH = isPortrait ? 1536 : 1120;

      final canonicalSheet = sheetResult.isCropped &&
              rawImage.width == targetW &&
              rawImage.height == targetH
          ? rawImage
          : HomographyMatrix.warpPerspective(rawImage, quad, targetW, targetH);
      debugPrint('[OMR:WARP] Canonical Canvas: ${canonicalSheet.width}x${canonicalSheet.height} (isPortrait: $isPortrait)');

      // 5. Stage 3: Discover Structural Layout (Columns, Rows, Bubble Groups)
      final layout = layoutDetector.detectLayout(canonicalSheet);

      // 6. Stage 4: Question-Local Bubble Fill Scoring & Answer Classification
      final answers = bubbleClassifier.classifyAll(canonicalSheet, layout);
      debugPrint('[OMR:EVALUATION] Evaluated ${answers.length} questions.');

      // 7. Stage 5: Structural Validation & Quality Assessment
      final totalExpected = template.totalQuestions;
      final detectedCount = answers.length;

      if (detectedCount < totalExpected) {
        return ScanResult(
          status: ScanStatus.failed,
          message: 'Detected only $detectedCount of $totalExpected expected questions. Please upload a clearer image.',
          detectedAnswers: answers,
          sheetDetectionConfidence: sheetResult.confidence * 0.5,
          imagePath: imagePath,
          classMode: classMode,
        );
      }

      // 8. Stage 6: Generate Debug & Review Visualization Overlay
      Uint8List? rectifiedBytes;
      try {
        rectifiedBytes = Uint8List.fromList(img.encodeJpg(canonicalSheet, quality: 90));
      } catch (_) {}

      VisualizationResult? vizResult;
      try {
        vizResult = await OMRVisualizer.generateAnnotatedImage(
          sourceImage: canonicalSheet,
          layout: layout,
          answers: answers,
          originalPath: imagePath,
        );
      } catch (_) {}

      final uncertainCount = answers.values.where((a) => a.classification == AnswerClassification.uncertain).length;
      final overallConfidence = min(0.99, max(0.70, sheetResult.confidence * (1.0 - (uncertainCount / totalExpected) * 0.3)));
      final scanStatus = uncertainCount > 6 ? ScanStatus.uncertain : ScanStatus.success;

      return ScanResult(
        status: scanStatus,
        message: scanStatus == ScanStatus.success
            ? 'OMR Sheet scanned and answers extracted successfully.'
            : 'Some answers have faint or ambiguous marks that require teacher review.',
        detectedAnswers: answers,
        sheetDetectionConfidence: overallConfidence,
        imagePath: imagePath,
        annotatedImagePath: vizResult?.filePath,
        annotatedImageBytes: vizResult?.bytes,
        rectifiedImageBytes: rectifiedBytes,
        classMode: classMode,
      );
    } catch (e) {
      return ScanResult(
        status: ScanStatus.failed,
        message: 'OMR processing error: $e',
        detectedAnswers: {},
        sheetDetectionConfidence: 0.0,
        classMode: classMode,
      );
    }
  }
}

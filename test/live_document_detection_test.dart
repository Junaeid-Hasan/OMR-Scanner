import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omr_scanner/models/scan_result.dart';
import 'package:omr_scanner/omr/detection/live_document_detector.dart';
import 'package:omr_scanner/omr/detection/stability_tracker.dart';
import 'package:omr_scanner/omr/detection/sheet_detector.dart';
import 'package:omr_scanner/omr/geometry/coordinate_transformer.dart';
import 'package:omr_scanner/omr/geometry/homography.dart';
import 'package:omr_scanner/omr/geometry/quadrilateral.dart';
import 'package:omr_scanner/services/omr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live Document Detector Verification', () {
    const detector = LiveDocumentDetector();

    test('Accurately detects boundaries and 4 corners on standard clean OMR sheet', () {
      final file = File('assets/test_images/test_clean_sheet.png');
      expect(file.existsSync(), isTrue);

      final image = img.decodeImage(file.readAsBytesSync())!;
      final result = detector.detectFromImage(image);

      expect(result.isReliable, isTrue);
      expect(result.normalizedQuad, isNotNull);

      final quad = result.normalizedQuad!;
      expect(quad.isConvex(), isTrue);

      // Verify all normalized corners are within [0.0, 1.0]
      expect(quad.tl.x, inInclusiveRange(0.0, 0.40));
      expect(quad.tl.y, inInclusiveRange(0.0, 0.40));
      expect(quad.br.x, inInclusiveRange(0.60, 1.0));
      expect(quad.br.y, inInclusiveRange(0.60, 1.0));
    });

    test('Accurately detects boundaries on angled phone photo with desk background', () {
      final file = File('assets/test_images/test_desk_photo.png');
      expect(file.existsSync(), isTrue);

      final image = img.decodeImage(file.readAsBytesSync())!;
      final result = detector.detectFromImage(image);

      expect(result.isReliable, isTrue);
      expect(result.normalizedQuad, isNotNull);

      final quad = result.normalizedQuad!;
      expect(quad.isConvex(), isTrue);
      expect(quad.area, greaterThan(0.15)); // Occupies significant portion of frame
      expect(result.confidence, greaterThanOrEqualTo(0.70));
    });

    test('Rejects non-sheet blank and uniform noise images gracefully', () {
      final blankImage = img.Image(width: 800, height: 600);
      for (int y = 0; y < 600; y++) {
        for (int x = 0; x < 800; x++) {
          blankImage.setPixelRgb(x, y, 50, 50, 55);
        }
      }

      final result = detector.detectFromImage(blankImage);
      expect(result.isReliable, isFalse);
      expect(result.normalizedQuad, isNull);
      expect(result.message, contains('No document detected'));
    });

    test('Blur estimation correctly flags blurry/low-contrast frames', () {
      // Extremely low contrast uniform image
      final uniformImage = img.Image(width: 400, height: 400);
      for (int y = 0; y < 400; y++) {
        for (int x = 0; x < 400; x++) {
          uniformImage.setPixelRgb(x, y, 128, 128, 128);
        }
      }

      final result = detector.detectFromImage(uniformImage);
      expect(result.isBlurry, isTrue);
    });
  });

  group('Stability Tracker & Auto-Capture Verification', () {
    test('Transitions from searching -> detected -> steady -> readyToCapture upon stable hold', () {
      final tracker = StabilityTracker(requiredStableFrames: 4, driftThreshold: 0.03);

      expect(tracker.state, LiveTrackingState.searching);
      expect(tracker.shouldAutoCapture, isFalse);

      const steadyQuad = Quadrilateral(
        tl: Point2D(0.10, 0.10),
        tr: Point2D(0.90, 0.10),
        br: Point2D(0.90, 0.90),
        bl: Point2D(0.10, 0.90),
      );

      // Frame 1: First detection
      tracker.update(const LiveDetectionResult(
        normalizedQuad: steadyQuad,
        confidence: 0.85,
        blurScore: 80.0,
        isBlurry: false,
        isReliable: true,
        message: 'Document detected',
        processingTimeMs: 10,
      ));

      expect(tracker.state, LiveTrackingState.detected);
      expect(tracker.stableFrameCount, 1);
      expect(tracker.shouldAutoCapture, isFalse);

      // Frames 2..3: Steady hold with negligible sub-pixel jitter
      for (int i = 2; i <= 3; i++) {
        tracker.update(const LiveDetectionResult(
          normalizedQuad: Quadrilateral(
            tl: Point2D(0.101, 0.101),
            tr: Point2D(0.901, 0.101),
            br: Point2D(0.899, 0.899),
            bl: Point2D(0.101, 0.899),
          ),
          confidence: 0.88,
          blurScore: 85.0,
          isBlurry: false,
          isReliable: true,
          message: 'Document detected',
          processingTimeMs: 10,
        ));
        expect(tracker.state, LiveTrackingState.steady);
        expect(tracker.shouldAutoCapture, isFalse);
      }

      // Frame 4: Reaches requiredStableFrames -> readyToCapture!
      tracker.update(const LiveDetectionResult(
        normalizedQuad: Quadrilateral(
          tl: Point2D(0.10, 0.10),
          tr: Point2D(0.90, 0.10),
          br: Point2D(0.90, 0.90),
          bl: Point2D(0.10, 0.90),
        ),
        confidence: 0.90,
        blurScore: 88.0,
        isBlurry: false,
        isReliable: true,
        message: 'Document detected',
        processingTimeMs: 10,
      ));

      expect(tracker.state, LiveTrackingState.readyToCapture);
      expect(tracker.shouldAutoCapture, isTrue);
      expect(tracker.statusMessage, contains('Capturing'));

      // Lock capture
      tracker.lockCapture();
      expect(tracker.state, LiveTrackingState.capturing);
    });

    test('Resets stability count when phone moves abruptly (large drift)', () {
      final tracker = StabilityTracker(requiredStableFrames: 5, driftThreshold: 0.025);

      const quadA = Quadrilateral(
        tl: Point2D(0.10, 0.10),
        tr: Point2D(0.90, 0.10),
        br: Point2D(0.90, 0.90),
        bl: Point2D(0.10, 0.90),
      );

      // Stable frames
      for (int i = 0; i < 3; i++) {
        tracker.update(const LiveDetectionResult(
          normalizedQuad: quadA,
          confidence: 0.85,
          blurScore: 70.0,
          isBlurry: false,
          isReliable: true,
          message: 'Document detected',
          processingTimeMs: 10,
        ));
      }
      expect(tracker.stableFrameCount, 3);

      // Abrupt translation of sheet/phone (> 15% frame jump)
      const quadB = Quadrilateral(
        tl: Point2D(0.28, 0.25),
        tr: Point2D(0.95, 0.25),
        br: Point2D(0.95, 0.98),
        bl: Point2D(0.28, 0.98),
      );

      tracker.update(const LiveDetectionResult(
        normalizedQuad: quadB,
        confidence: 0.85,
        blurScore: 70.0,
        isBlurry: false,
        isReliable: true,
        message: 'Document detected',
        processingTimeMs: 10,
      ));

      // Stability decays immediately
      expect(tracker.stableFrameCount, lessThan(3));
      expect(tracker.state, LiveTrackingState.detected);
      expect(tracker.shouldAutoCapture, isFalse);
    });

    test('Flags camera motion blur and prevents premature auto-capture', () {
      final tracker = StabilityTracker(requiredStableFrames: 3);

      const quad = Quadrilateral(
        tl: Point2D(0.10, 0.10),
        tr: Point2D(0.90, 0.10),
        br: Point2D(0.90, 0.90),
        bl: Point2D(0.10, 0.90),
      );

      // Frame with motion blur
      tracker.update(const LiveDetectionResult(
        normalizedQuad: quad,
        confidence: 0.80,
        blurScore: 15.0, // Low blur score
        isBlurry: true,
        isReliable: false,
        message: 'Hold steady...',
        processingTimeMs: 10,
      ));

      expect(tracker.shouldAutoCapture, isFalse);
      expect(tracker.statusMessage, contains('Camera moving'));
    });
  });

  group('Coordinate Transformer & Screen Mapping Verification', () {
    test('Normalizes and denormalizes quadrilateral without distortion', () {
      const srcQuad = Quadrilateral(
        tl: Point2D(100, 200),
        tr: Point2D(900, 200),
        br: Point2D(900, 1400),
        bl: Point2D(100, 1400),
      );

      final norm = CoordinateTransformer.normalizeQuad(srcQuad, 1000, 1600);
      expect(norm.tl.x, closeTo(0.10, 1e-5));
      expect(norm.tl.y, closeTo(0.125, 1e-5));
      expect(norm.br.x, closeTo(0.90, 1e-5));
      expect(norm.br.y, closeTo(0.875, 1e-5));

      final restored = CoordinateTransformer.denormalizeQuad(norm, 1000, 1600);
      expect(restored.tl.x, closeTo(100, 1e-5));
      expect(restored.tl.y, closeTo(200, 1e-5));
      expect(restored.br.x, closeTo(900, 1e-5));
      expect(restored.br.y, closeTo(1400, 1e-5));
    });

    test('Maps normalized quad to Flutter screen offsets', () {
      const normQuad = Quadrilateral(
        tl: Point2D(0.1, 0.2),
        tr: Point2D(0.9, 0.2),
        br: Point2D(0.8, 0.8),
        bl: Point2D(0.2, 0.8),
      );

      final offsets = CoordinateTransformer.quadToScreenOffsets(normQuad, const Size(400, 800));
      expect(offsets.length, 4);
      expect(offsets[0].dx, 40.0);
      expect(offsets[0].dy, 160.0);
      expect(offsets[1].dx, 360.0);
      expect(offsets[1].dy, 160.0);
    });
  });

  group('Pipeline Integration with Pre-Detected Quadrilateral', () {
    test('OmrService seamlessly consumes pre-detected quadrilateral for assessment', () async {
      const deskPhoto = 'assets/test_images/test_desk_photo.png';
      expect(File(deskPhoto).existsSync(), isTrue);

      // Pre-detect with LiveDocumentDetector
      final image = img.decodeImage(File(deskPhoto).readAsBytesSync())!;
      final liveResult = const LiveDocumentDetector().detectFromImage(image);
      expect(liveResult.isReliable, isTrue);

      final denormQuad = CoordinateTransformer.denormalizeQuad(
        liveResult.normalizedQuad!,
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final omrService = OmrService();
      final scanResult = await omrService.scanImage(
        deskPhoto,
        detectedQuad: denormQuad,
      );

      expect(scanResult.status, ScanStatus.success);
      expect(scanResult.detectedAnswers.length, 30);
      expect(scanResult.detectedAnswers[1]!.primaryAnswer, 'C');
      expect(scanResult.detectedAnswers[10]!.primaryAnswer, 'D');
    });
  });

  group('Fast Document Acquisition & Side Noise Elimination Verification', () {
    test('Default StabilityTracker triggers readyToCapture in 2 consecutive steady frames', () {
      final tracker = StabilityTracker(); // Uses production defaults: 2 frames, 0.040 drift

      expect(tracker.requiredStableFrames, 2);
      expect(tracker.driftThreshold, 0.040);
      expect(tracker.state, LiveTrackingState.searching);

      const quad = Quadrilateral(
        tl: Point2D(0.12, 0.12),
        tr: Point2D(0.88, 0.12),
        br: Point2D(0.88, 0.88),
        bl: Point2D(0.12, 0.88),
      );

      // Frame 1: Detection
      tracker.update(const LiveDetectionResult(
        normalizedQuad: quad,
        confidence: 0.90,
        blurScore: 80.0,
        isBlurry: false,
        isReliable: true,
        message: 'Document detected',
        processingTimeMs: 8,
      ));
      expect(tracker.state, LiveTrackingState.detected);
      expect(tracker.shouldAutoCapture, isFalse);

      // Frame 2: Steady & Ready for auto-capture!
      tracker.update(const LiveDetectionResult(
        normalizedQuad: quad,
        confidence: 0.90,
        blurScore: 82.0,
        isBlurry: false,
        isReliable: true,
        message: 'Document detected',
        processingTimeMs: 7,
      ));
      expect(tracker.state, LiveTrackingState.readyToCapture);
      expect(tracker.shouldAutoCapture, isTrue);
      expect(tracker.statusMessage, contains('Capturing'));
    });

    test('Perspective warping eliminates surrounding desk noise from captured photo', () {
      final deskFile = File('assets/test_images/test_desk_photo.png');
      expect(deskFile.existsSync(), isTrue);

      final rawPhoto = img.decodeImage(deskFile.readAsBytesSync())!;

      // Verify the original photo contains dark desk pixels near its borders
      final topLeftDesk = rawPhoto.getPixel(10, 10);
      final deskLuminance = 0.299 * topLeftDesk.r + 0.587 * topLeftDesk.g + 0.114 * topLeftDesk.b;
      expect(deskLuminance, lessThan(80.0)); // Dark wooden desk noise

      // Detect sheet boundary
      final sheetRes = const SheetDetector().detectSheet(rawPhoto);
      expect(sheetRes.isReliable, isTrue);
      expect(sheetRes.isCropped, isFalse);

      // Rectify to canonical canvas
      final isPortrait = sheetRes.quad.targetMaxHeight > sheetRes.quad.targetMaxWidth;
      final int targetW = isPortrait ? 1120 : 1536;
      final int targetH = isPortrait ? 1536 : 1120;
      final rectified = HomographyMatrix.warpPerspective(rawPhoto, sheetRes.quad, targetW, targetH);

      expect(rectified.width, 1120);
      expect(rectified.height, 1536);

      // Verify the rectified photo contains ONLY paper (white background > 160) at borders, zero desk noise
      final cornerSample = rectified.getPixel(30, 30);
      final paperLuminance = 0.299 * cornerSample.r + 0.587 * cornerSample.g + 0.114 * cornerSample.b;
      expect(paperLuminance, greaterThan(160.0)); // Clean white paper, desk completely eliminated!
    });
  });
}

import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omr_scanner/models/detected_answer.dart';
import 'package:omr_scanner/models/scan_result.dart';
import 'package:omr_scanner/services/omr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Production Geometric Vision Pipeline Verification', () {
    late OmrService omrService;
    late img.Image basePortraitSheet;

    setUpAll(() {
      omrService = OmrService();
      final bytes = File('assets/test_images/test_marked_sheet.png').readAsBytesSync();
      basePortraitSheet = img.decodeImage(bytes)!;
    });

    test('Input 1: High-resolution (3600x2700) with desk background and slight perspective', () async {
      // Synthesize 3600x2700 photo with sheet occupying ~70% of frame placed on a dark wooden desk
      const dw = 3600;
      const dh = 2700;
      final photo = img.Image(width: dw, height: dh);

      // Dark desk texture
      for (int y = 0; y < dh; y++) {
        for (int x = 0; x < dw; x++) {
          final grain = ((x * 7 + y * 13) % 15);
          photo.setPixelRgb(x, y, 45 + grain, 35 + grain, 30 + grain);
        }
      }

      // Sheet scaled and placed with slight perspective
      final sheetScaled = img.copyResize(basePortraitSheet, width: 1500, height: 2062);
      const offsetX = 1050;
      const offsetY = 320;
      img.compositeImage(photo, sheetScaled, dstX: offsetX, dstY: offsetY);

      final tempPath = '.omr_annotated/test_high_res_desk.jpg';
      await File(tempPath).writeAsBytes(img.encodeJpg(photo, quality: 90));

      final result = await omrService.scanImage(tempPath);
      expect(result.status, isNot(ScanStatus.failed));
      expect(result.detectedAnswers.length, 30);

      // Verify answers correctly extracted despite 3600x2700 resolution
      expect(result.detectedAnswers[1]!.primaryAnswer, 'A');
      expect(result.detectedAnswers[2]!.primaryAnswer, 'B');
      expect(result.detectedAnswers[3]!.primaryAnswer, 'C');
      expect(result.detectedAnswers[4]!.primaryAnswer, 'D');
      expect(result.detectedAnswers[5]!.primaryAnswer, 'A');
      expect(result.detectedAnswers[15]!.classification, AnswerClassification.blank);
      expect(result.detectedAnswers[25]!.classification, AnswerClassification.multiple);
    });

    test('Input 2: Low-resolution (1280x960) with sheet occupying 60% of frame', () async {
      const dw = 1280;
      const dh = 960;
      final photo = img.Image(width: dw, height: dh);

      // Desk background
      for (int y = 0; y < dh; y++) {
        for (int x = 0; x < dw; x++) {
          photo.setPixelRgb(x, y, 40, 40, 45);
        }
      }

      final sheetScaled = img.copyResize(basePortraitSheet, width: 550, height: 756);
      const offsetX = 365;
      const offsetY = 102;
      img.compositeImage(photo, sheetScaled, dstX: offsetX, dstY: offsetY);

      final tempPath = '.omr_annotated/test_low_res_desk.jpg';
      await File(tempPath).writeAsBytes(img.encodeJpg(photo, quality: 85));

      final result = await omrService.scanImage(tempPath);
      expect(result.status, isNot(ScanStatus.failed));
      expect(result.detectedAnswers.length, 30);

      expect(result.detectedAnswers[1]!.primaryAnswer, 'A');
      expect(result.detectedAnswers[2]!.primaryAnswer, 'B');
      expect(result.detectedAnswers[15]!.classification, AnswerClassification.blank);
    });

    test('Input 3: Severe non-uniform lighting with shadow gradient across the sheet', () async {
      final shadowed = img.Image.from(basePortraitSheet);

      // Apply a strong diagonal shadow gradient (luminance drop up to 80 points)
      for (int y = 0; y < shadowed.height; y++) {
        for (int x = 0; x < shadowed.width; x++) {
          final factor = (x / shadowed.width * 0.4 + y / shadowed.height * 0.6);
          final drop = (factor * 75).round();
          final p = shadowed.getPixel(x, y);
          shadowed.setPixelRgb(
            x,
            y,
            max(0, p.r.toInt() - drop),
            max(0, p.g.toInt() - drop),
            max(0, p.b.toInt() - drop),
          );
        }
      }

      final tempPath = '.omr_annotated/test_shadowed_sheet.jpg';
      await File(tempPath).writeAsBytes(img.encodeJpg(shadowed, quality: 90));

      final result = await omrService.scanImage(tempPath);
      expect(result.status, isNot(ScanStatus.failed));
      expect(result.detectedAnswers.length, 30);

      // Local illumination normalization must prevent false BLANKs or false fills
      expect(result.detectedAnswers[1]!.primaryAnswer, 'A');
      expect(result.detectedAnswers[2]!.primaryAnswer, 'B');
      expect(result.detectedAnswers[15]!.classification, AnswerClassification.blank);
      expect(result.detectedAnswers[25]!.classification, AnswerClassification.multiple);
      expect(result.detectedAnswers[26]!.primaryAnswer, 'D');
    });

    test('Input 4: Bright overexposed illumination', () async {
      final bright = img.Image.from(basePortraitSheet);

      // Brighten all pixels towards 255
      for (int y = 0; y < bright.height; y++) {
        for (int x = 0; x < bright.width; x++) {
          final p = bright.getPixel(x, y);
          bright.setPixelRgb(
            x,
            y,
            min(255, p.r.toInt() + 25),
            min(255, p.g.toInt() + 25),
            min(255, p.b.toInt() + 25),
          );
        }
      }

      final tempPath = '.omr_annotated/test_bright_sheet.jpg';
      await File(tempPath).writeAsBytes(img.encodeJpg(bright, quality: 90));

      final result = await omrService.scanImage(tempPath);
      expect(result.status, isNot(ScanStatus.failed));
      expect(result.detectedAnswers.length, 30);

      expect(result.detectedAnswers[1]!.primaryAnswer, 'A');
      expect(result.detectedAnswers[2]!.primaryAnswer, 'B');
      expect(result.detectedAnswers[15]!.classification, AnswerClassification.blank);
    });

    test('Validation: Rejects non-sheet images cleanly with helpful message', () async {
      // Generate a blank image with random noise (no OMR document)
      final noise = img.Image(width: 800, height: 600);
      for (int y = 0; y < noise.height; y++) {
        for (int x = 0; x < noise.width; x++) {
          noise.setPixelRgb(x, y, 30, 30, 35);
        }
      }

      final tempPath = '.omr_annotated/test_blank_noise.jpg';
      await File(tempPath).writeAsBytes(img.encodeJpg(noise));

      final result = await omrService.scanImage(tempPath);
      expect(result.status, ScanStatus.failed);
      expect(result.message.contains('Unable to reliably locate OMR sheet'), isTrue);
    });
  });
}

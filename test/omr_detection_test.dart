import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omr_scanner/models/answer_key.dart';
import 'package:omr_scanner/models/detected_answer.dart';
import 'package:omr_scanner/models/scan_result.dart';
import 'package:omr_scanner/services/grading_service.dart';
import 'package:omr_scanner/services/omr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OMR Detection & Assessment on Student Sheet', () {
    test('Accurately detects all answers from filled student sheet', () async {
      const samplePath = 'assets/test_images/bangla_omr_sample.jpg';
      expect(File(samplePath).existsSync(), isTrue, reason: 'Sample sheet must exist');

      final omrService = OmrService();
      final scanResult = await omrService.scanImage(samplePath);

      expect(scanResult.status, ScanStatus.success);
      expect(scanResult.detectedAnswers.length, 30);

      // Expected student marks based on the uploaded sheet
      final expectedAnswers = <int, String?>{
        1: 'C',
        2: 'B',
        3: 'D',
        4: 'C',
        5: 'C',
        6: 'A',
        7: 'B',
        8: 'D',
        9: 'D',
        10: 'A',
        11: 'B',
        12: 'D',
        13: 'B',
        14: 'C',
        15: 'C',
        16: 'B',
        17: 'D',
        18: 'A',
        19: 'A',
        20: 'B',
        21: 'C',
        22: 'D',
        23: 'C',
        24: 'D',
        25: 'D',
        26: null, // Blank
        27: null, // Blank
        28: null, // Blank
        29: null, // Blank
        30: null, // Blank
      };

      for (int q = 1; q <= 30; q++) {
        final detected = scanResult.detectedAnswers[q];
        expect(detected, isNotNull, reason: 'Question $q should have a detection result');

        final expected = expectedAnswers[q];
        if (expected != null) {
          expect(
            detected!.classification,
            AnswerClassification.single,
            reason: 'Q$q expected SINGLE ($expected), got ${detected.classification.name} with score ${detected.bubbleScores}',
          );
          expect(
            detected.primaryAnswer,
            expected,
            reason: 'Q$q expected option $expected, detected ${detected.primaryAnswer}',
          );
        } else {
          expect(
            detected!.classification,
            AnswerClassification.blank,
            reason: 'Q$q should be classified as BLANK, got ${detected.classification.name} with score ${detected.bubbleScores}',
          );
        }
      }

      // Assessment with Official Answer Key
      final answerKey = AnswerKey(
        id: 'bangla_key_1',
        examName: 'নৈর্ব্যক্তিক অভীক্ষা (Model Test 1)',
        createdAt: DateTime.now(),
        totalQuestions: 30,
        answers: {
          1: 'C',
          2: 'B',
          3: 'D',
          4: 'C',
          5: 'C',
          6: 'A',
          7: 'B',
          8: 'D',
          9: 'D',
          10: 'A',
          11: 'B',
          12: 'D',
          13: 'B',
          14: 'C',
          15: 'C',
          16: 'B',
          17: 'D',
          18: 'A',
          19: 'A',
          20: 'B',
          21: 'C',
          22: 'D',
          23: 'C',
          24: 'D',
          25: 'D',
          26: 'A',
          27: 'B',
          28: 'C',
          29: 'D',
          30: 'A',
        },
      );

      final gradingService = GradingService();
      final examResult = gradingService.grade(
        examId: 'res_test_1',
        examName: answerKey.examName,
        answerKey: answerKey,
        studentAnswers: scanResult.detectedAnswers,
        annotatedImagePath: scanResult.annotatedImagePath,
      );

      expect(examResult.totalQuestions, 30);
      expect(examResult.correct, 25);
      expect(examResult.blank, 5);
      expect(examResult.wrong, 0);
      expect(examResult.multiple, 0);
      expect(examResult.reviewRequired, 0);
      expect(examResult.score, 25.0);
      expect(examResult.percentage, 83.33);
    });

    test('Accurately detects all 30 BLANK answers on clean un-marked sheet', () async {
      const cleanPath = 'assets/test_images/test_clean_sheet.png';
      expect(File(cleanPath).existsSync(), isTrue);

      final omrService = OmrService();
      final scanResult = await omrService.scanImage(cleanPath);

      expect(scanResult.status, ScanStatus.success);
      expect(scanResult.detectedAnswers.length, 30);

      for (int q = 1; q <= 30; q++) {
        final detected = scanResult.detectedAnswers[q]!;
        expect(
          detected.classification,
          AnswerClassification.blank,
          reason: 'Question $q on clean sheet should be BLANK but got ${detected.classification.name}',
        );
      }
    });

    test('Accurately detects marks, blanks, and multiple fills on standard portrait sheet', () async {
      const portraitPath = 'assets/test_images/test_marked_sheet.png';
      expect(File(portraitPath).existsSync(), isTrue);

      final omrService = OmrService();
      final scanResult = await omrService.scanImage(portraitPath);

      expect(scanResult.status, ScanStatus.success);
      expect(scanResult.detectedAnswers.length, 30);

      // Verify known answers on marked sheet:
      // Q1=A, Q2=B, Q3=C, Q4=D, Q5=A
      expect(scanResult.detectedAnswers[1]!.primaryAnswer, 'A');
      expect(scanResult.detectedAnswers[2]!.primaryAnswer, 'B');
      expect(scanResult.detectedAnswers[3]!.primaryAnswer, 'C');
      expect(scanResult.detectedAnswers[4]!.primaryAnswer, 'D');
      expect(scanResult.detectedAnswers[5]!.primaryAnswer, 'A');

      // Q15 is blank
      expect(scanResult.detectedAnswers[15]!.classification, AnswerClassification.blank);

      // Q25 has multiple marks (A and B)
      expect(scanResult.detectedAnswers[25]!.classification, AnswerClassification.multiple);
      expect(scanResult.detectedAnswers[25]!.selectedOptions, containsAll(['A', 'B']));

      // Q26=D, Q27=A, Q28=B, Q29=C
      expect(scanResult.detectedAnswers[26]!.primaryAnswer, 'D');
      expect(scanResult.detectedAnswers[27]!.primaryAnswer, 'A');
      expect(scanResult.detectedAnswers[28]!.primaryAnswer, 'B');
      expect(scanResult.detectedAnswers[29]!.primaryAnswer, 'C');
    });

    test('Accurately detects marks on phone photo with dark desk background and perspective tilt', () async {
      const deskPath = 'assets/test_images/test_desk_photo.png';
      expect(File(deskPath).existsSync(), isTrue);

      final omrService = OmrService();
      final scanResult = await omrService.scanImage(deskPath);

      expect(scanResult.status, ScanStatus.success);
      expect(scanResult.detectedAnswers.length, 30);

      // Ground truth marks on desk photo:
      final deskGroundTruth = {
        1: 'C',
        5: 'B',
        10: 'D',
        15: 'A',
        20: 'C',
        25: 'B',
        30: 'D',
      };

      for (final entry in deskGroundTruth.entries) {
        final detected = scanResult.detectedAnswers[entry.key]!;
        expect(
          detected.classification,
          AnswerClassification.single,
          reason: 'Q${entry.key} on desk photo expected SINGLE (${entry.value}), got ${detected.classification.name}',
        );
        expect(
          detected.primaryAnswer,
          entry.value,
          reason: 'Q${entry.key} expected ${entry.value}, detected ${detected.primaryAnswer}',
        );
      }
    });
  });
}

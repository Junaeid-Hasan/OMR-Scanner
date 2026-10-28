import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omr_scanner/models/answer_key.dart';
import 'package:omr_scanner/models/detected_answer.dart';
import 'package:omr_scanner/models/scan_result.dart';
import 'package:omr_scanner/omr/detection/class_9_10_detector.dart';
import 'package:omr_scanner/omr/geometry/quadrilateral.dart';
import 'package:omr_scanner/services/grading_service.dart';
import 'package:omr_scanner/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Class 9-10 Detector Vision & Extraction', () {
    const sampleImagePath = 'assets/test_images/bangla_omr_class9_10_sample.jpg';

    test('Loads and crops Class 9-10 OMR grid to 1200px canonical width', () {
      final file = File(sampleImagePath);
      expect(file.existsSync(), isTrue, reason: 'Sample image must exist in assets');

      final rawImage = img.decodeImage(file.readAsBytesSync());
      expect(rawImage, isNotNull);

      final detector = const Class910Detector();
      final cropped = detector.cropOmrGrid(rawImage!);
      expect(cropped.width, equals(1200));
      expect(cropped.height, greaterThan(800));
    });

    test('Processes blank Class 9-10 sheet without false positives', () async {
      final file = File(sampleImagePath);
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final detector = const Class910Detector();
      final result = await detector.processSheet(sampleImagePath, bytes);

      expect(result.status, isNot(ScanStatus.failed));
      expect(result.classMode, equals('class_9_10'));
      expect(result.detectedAnswers.length, equals(30));
      expect(result.annotatedImagePath, isNotNull);
      expect(File(result.annotatedImagePath!).existsSync(), isTrue);
      // Blank sheet should have NO false positives
      expect(result.setCode, isNull);
      expect(result.rollNumber, isNull);
      expect(result.registrationNumber, isNull);
      expect(result.subjectCode, isNull);
      for (int i = 1; i <= 30; i++) {
        expect(result.detectedAnswers[i]?.classification, equals(AnswerClassification.blank));
      }
    });

    test('Protects pre-rectified Class 9-10 OMR grid from double-cropping and double-warping', () async {
      final file = File(sampleImagePath);
      final rawImage = img.decodeImage(file.readAsBytesSync())!;
      final detector = const Class910Detector();
      final preRectifiedGrid = detector.cropOmrGrid(rawImage);
      expect(preRectifiedGrid.width, equals(1200));
      final gridH = preRectifiedGrid.height;
      expect(gridH, greaterThan(850));

      final preRectifiedBytes = Uint8List.fromList(img.encodeJpg(preRectifiedGrid));

      // Simulate a raw photo detectedQuad (coordinates in 3000x4000 frame) passed to processSheet
      final rawPhotoQuad = Quadrilateral(
        tl: const Point2D(200, 300),
        tr: const Point2D(2800, 320),
        br: const Point2D(2750, 3800),
        bl: const Point2D(220, 3750),
      );

      final result = await detector.processSheet(
        'rectified_test.jpg',
        preRectifiedBytes,
        detectedQuad: rawPhotoQuad,
      );

      expect(result.status, equals(ScanStatus.success));
      expect(result.detectedAnswers.length, equals(30));
      // Verify annotated image preserved full grid canvas and was not squished
      final annotatedImage = img.decodeImage(result.annotatedImageBytes!)!;
      expect(annotatedImage.width, equals(1200));
      expect(annotatedImage.height, equals(gridH));
    });

    test('Accurately detects marked bubbles and Set Code on user photo scan', () async {
      const userScanPath = 'assets/test_images/class_9_10_marked_user_scan.png';
      final file = File(userScanPath);
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final detector = const Class910Detector();
      final result = await detector.processSheet(userScanPath, bytes);

      expect(result.status, equals(ScanStatus.success));
      expect(result.setCode, equals('ক'));
      expect(result.rollNumber, equals('851862'));
      expect(result.registrationNumber, equals('2110759758'));
      expect(result.subjectCode, isNotNull);
      expect(result.detectedAnswers.length, equals(30));

      // Assert key marked questions on student sheet
      expect(result.detectedAnswers[1]?.classification, equals(AnswerClassification.single));
      expect(result.detectedAnswers[1]?.primaryAnswer, equals('A'));

      expect(result.detectedAnswers[2]?.classification, equals(AnswerClassification.single));
      expect(result.detectedAnswers[2]?.primaryAnswer, equals('B'));

      expect(result.detectedAnswers[5]?.classification, equals(AnswerClassification.single));
      expect(result.detectedAnswers[5]?.primaryAnswer, equals('A'));

      expect(result.detectedAnswers[6]?.classification, equals(AnswerClassification.single));
      expect(result.detectedAnswers[6]?.primaryAnswer, equals('C'));

      expect(result.detectedAnswers[13]?.classification, equals(AnswerClassification.single));
      expect(result.detectedAnswers[13]?.primaryAnswer, equals('A'));

      expect(result.detectedAnswers[16]?.classification, equals(AnswerClassification.single));
      expect(result.detectedAnswers[16]?.primaryAnswer, equals('B'));
    });

    test('Accurately detects marked bubbles and Set Code on raw angled camera photo via 5-Stage Micro-Homography', () async {
      const rawCameraPath = 'assets/test_images/class_9_10_raw_camera_scan.jpg';
      final file = File(rawCameraPath);
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final detector = const Class910Detector();
      final result = await detector.processSheet(rawCameraPath, bytes);

      expect(result.status, equals(ScanStatus.success));
      expect(result.setCode, equals('ক'));
      expect(result.detectedAnswers[1]?.primaryAnswer, equals('A'));
      expect(result.detectedAnswers[2]?.primaryAnswer, equals('B'));
      expect(result.detectedAnswers[5]?.primaryAnswer, equals('A'));
      expect(result.detectedAnswers[6]?.primaryAnswer, equals('C'));
      expect(result.detectedAnswers[7]?.primaryAnswer, equals('D'));
      expect(result.detectedAnswers[13]?.primaryAnswer, equals('A'));
      expect(result.annotatedImagePath, isNotNull);
      expect(File(result.annotatedImagePath!).existsSync(), isTrue);
    });
  });

  group('Class 9-10 4-Set Answer Key & Dynamic Grading', () {
    late AnswerKey fourSetKey;

    setUp(() {
      final setKa = {
        1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'A',
        6: 'B', 7: 'C', 8: 'D', 9: 'A', 10: 'B',
        11: 'C', 12: 'D', 13: 'A', 14: 'B', 15: 'C',
        16: 'B', 17: 'C', 18: 'D', 19: 'A', 20: 'B',
        21: 'C', 22: 'D', 23: 'A', 24: 'B', 25: 'C',
        26: 'D', 27: 'A', 28: 'B', 29: 'C', 30: 'D',
      };
      final setKha = {
        1: 'B', 2: 'C', 3: 'D', 4: 'A', 5: 'B',
        6: 'C', 7: 'D', 8: 'A', 9: 'B', 10: 'C',
        11: 'D', 12: 'A', 13: 'B', 14: 'C', 15: 'D',
        16: 'C', 17: 'D', 18: 'A', 19: 'B', 20: 'C',
        21: 'D', 22: 'A', 23: 'B', 24: 'C', 25: 'D',
        26: 'A', 27: 'B', 28: 'C', 29: 'D', 30: 'A',
      };
      final setGa = {
        1: 'C', 2: 'D', 3: 'A', 4: 'B', 5: 'C',
        6: 'D', 7: 'A', 8: 'B', 9: 'C', 10: 'D',
        11: 'A', 12: 'B', 13: 'C', 14: 'D', 15: 'A',
        16: 'D', 17: 'A', 18: 'B', 19: 'C', 20: 'D',
        21: 'A', 22: 'B', 23: 'C', 24: 'D', 25: 'A',
        26: 'B', 27: 'C', 28: 'D', 29: 'A', 30: 'B',
      };
      final setGha = {
        1: 'D', 2: 'A', 3: 'B', 4: 'C', 5: 'D',
        6: 'A', 7: 'B', 8: 'C', 9: 'D', 10: 'A',
        11: 'B', 12: 'C', 13: 'D', 14: 'A', 15: 'B',
        16: 'A', 17: 'B', 18: 'C', 19: 'D', 20: 'A',
        21: 'B', 22: 'C', 23: 'D', 24: 'A', 25: 'B',
        26: 'C', 27: 'D', 28: 'A', 29: 'B', 30: 'C',
      };

      fourSetKey = AnswerKey(
        id: 'test_class_9_10',
        examName: 'SSC Board Exam',
        createdAt: DateTime.now(),
        totalQuestions: 30,
        classMode: 'class_9_10',
        answers: setKa,
        setAnswers: {
          'ক': setKa,
          'খ': setKha,
          'গ': setGa,
          'ঘ': setGha,
        },
      );
    });

    test('AnswerKey identifies as Class 9-10 and correctly retrieves set-specific keys', () {
      expect(fourSetKey.isClass9And10, isTrue);
      expect(fourSetKey.classMode, equals('class_9_10'));

      final answersKa = fourSetKey.getAnswersForSet('ক');
      expect(answersKa[1], equals('A'));

      final answersKha = fourSetKey.getAnswersForSet('খ');
      expect(answersKha[1], equals('B'));

      final answersGa = fourSetKey.getAnswersForSet('গ');
      expect(answersGa[1], equals('C'));

      final answersGha = fourSetKey.getAnswersForSet('ঘ');
      expect(answersGha[1], equals('D'));
    });

    test('Serializes and deserializes AnswerKey preserving all 4 sets and classMode', () {
      final json = fourSetKey.toJson();
      final restored = AnswerKey.fromJson(json);

      expect(restored.id, equals(fourSetKey.id));
      expect(restored.classMode, equals('class_9_10'));
      expect(restored.isClass9And10, isTrue);
      expect(restored.setAnswers.length, equals(4));
      expect(restored.getAnswersForSet('খ')[1], equals('B'));
    });

    test('GradingService grades sheet against detected student Set Code', () {
      final gradingService = GradingService();

      // Student answering according to Set Kha (Q1='B', Q2='C', Q3='D' ...)
      final studentAnswers = <int, DetectedAnswer>{};
      final khaAnswers = fourSetKey.getAnswersForSet('খ');
      khaAnswers.forEach((q, ans) {
        studentAnswers[q] = DetectedAnswer(
          questionNumber: q,
          selectedOptions: [ans],
          classification: AnswerClassification.single,
          confidence: 0.95,
          bubbleScores: {ans: 0.95},
          primaryAnswer: ans,
        );
      });

      // Grade with detected set 'খ'
      final resultKha = gradingService.grade(
        examId: fourSetKey.id,
        examName: fourSetKey.examName,
        answerKey: fourSetKey,
        studentAnswers: studentAnswers,
        rollNumber: '123456',
        setCode: 'খ',
        registrationNumber: '1928374650',
        subjectCode: '101',
        classMode: 'class_9_10',
      );

      expect(resultKha.correct, equals(30));
      expect(resultKha.wrong, equals(0));
      expect(resultKha.score, equals(30.0));
      expect(resultKha.percentage, equals(100.0));
      expect(resultKha.rollNumber, equals('123456'));
      expect(resultKha.setCode, equals('খ'));
      expect(resultKha.registrationNumber, equals('1928374650'));
      expect(resultKha.subjectCode, equals('101'));
      expect(resultKha.classMode, equals('class_9_10'));

      // If graded mistakenly against Set 'ক', score should be significantly lower
      final resultKa = gradingService.grade(
        examId: fourSetKey.id,
        examName: fourSetKey.examName,
        answerKey: fourSetKey,
        studentAnswers: studentAnswers,
        setCode: 'ক',
        classMode: 'class_9_10',
      );
      expect(resultKa.score, lessThan(30.0));
    });
  });

  group('StorageService Mode Separation', () {
    test('Separates Class 6-8 and Class 9-10 answer keys and results', () async {
      final storage = StorageService();
      await storage.init();

      final keys68 = storage.getAnswerKeysForMode('class_6_8');
      final keys910 = storage.getAnswerKeysForMode('class_9_10');

      expect(keys68, isNotEmpty);
      expect(keys910, isNotEmpty);

      for (final k in keys68) {
        expect(k.classMode, equals('class_6_8'));
      }
      for (final k in keys910) {
        expect(k.classMode, equals('class_9_10'));
      }
    });
  });
}

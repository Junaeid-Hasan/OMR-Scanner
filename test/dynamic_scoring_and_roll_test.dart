import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omr_scanner/models/answer_key.dart';
import 'package:omr_scanner/models/detected_answer.dart';
import 'package:omr_scanner/models/exam_result.dart';
import 'package:omr_scanner/screens/answer_key/answer_key_screen.dart';
import 'package:omr_scanner/screens/result/result_screen.dart';
import 'package:omr_scanner/services/grading_service.dart';
import 'package:omr_scanner/widgets/roll_number_dialog.dart';
import 'package:omr_scanner/widgets/score_card.dart';

void main() {
  group('Dynamic Answer Key & Roll Number Verification', () {
    test('Exam with less than 30 questions assumes full marks equals selected answer count', () {
      final answers = <int, String>{
        1: 'A',
        2: 'B',
        3: 'C',
        4: 'D',
        5: 'A',
        6: 'B',
        7: 'C',
        8: 'D',
        9: 'A',
        10: 'B',
        11: 'C',
        12: 'D',
        13: 'A',
        14: 'B',
        15: 'C',
      };

      final key = AnswerKey(
        id: '15_q_key',
        examName: 'Class 10 Biology Quiz',
        createdAt: DateTime.now(),
        totalQuestions: 15,
        answers: answers,
      );

      final detected = <int, DetectedAnswer>{};
      for (int i = 1; i <= 15; i++) {
        detected[i] = DetectedAnswer(
          questionNumber: i,
          selectedOptions: [answers[i]!],
          classification: AnswerClassification.single,
          confidence: 0.99,
          bubbleScores: {answers[i]!: 0.99},
          primaryAnswer: answers[i]!,
        );
      }

      final gradingService = GradingService();
      final result = gradingService.grade(
        examId: 'test_res_1',
        examName: key.examName,
        answerKey: key,
        studentAnswers: detected,
        rollNumber: '105',
      );

      expect(result.totalQuestions, equals(15));
      expect(result.score, equals(15.0));
      expect(result.percentage, equals(100.0));
      expect(result.rollNumber, equals('105'));

      // Check serialization
      final json = result.toJson();
      expect(json['rollNumber'], equals('105'));
      expect(json['totalQuestions'], equals(15));

      final deserialized = ExamResult.fromJson(json);
      expect(deserialized.rollNumber, equals('105'));
      expect(deserialized.totalQuestions, equals(15));
    });

    testWidgets('ScoreCard renders without overflow on compact 320px screen width', (WidgetTester tester) async {
      // Simulate extreme narrow screen (320x568)
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final result = ExamResult(
        id: 'compact_test',
        examName: 'Mathematics Assessment Final Term',
        scannedAt: DateTime.now(),
        totalQuestions: 15,
        correct: 10,
        wrong: 2,
        blank: 1,
        multiple: 1,
        reviewRequired: 1,
        score: 10.0,
        percentage: 66.67,
        questionResults: [],
        rollNumber: 'Roll #42',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScoreCard(result: result),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Student Roll: Roll #42'), findsOneWidget);
      expect(find.text('10'), findsWidgets);
      expect(find.text(' / 15'), findsOneWidget);
      expect(tester.takeException(), isNull); // Verify no overflow errors thrown
    });

    testWidgets('RollNumberDialog renders without 25px overflow on 320px and 360px screens', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: RollNumberDialog(initialRoll: '101'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Student Roll Number'), findsOneWidget);
      expect(find.text('Proceed to Scan'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(tester.takeException(), isNull); // Zero overflow
    });

    testWidgets('AnswerKeyScreen has only one Clear button, one Save button, and no Fill all / Randomize', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: AnswerKeyScreen(),
      ));
      await tester.pumpAndSettle();

      // Only one Clear button (Clear Section)
      expect(find.text('Clear Section'), findsOneWidget);
      expect(find.text('Clear All'), findsNothing);

      // Only one Save button (at the bottom)
      expect(find.text('Save Answer Key'), findsOneWidget);

      // Removed Fill all A and Randomize
      expect(find.text('Fill All A'), findsNothing);
      expect(find.text('Randomize Section'), findsNothing);

      // Verify that selecting an answer does not show an 'x' icon
      await tester.tap(find.text('A').first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('RollNumberDialog does not have quick rolls chips', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: RollNumberDialog(initialRoll: '1'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Roll 101'), findsNothing);
      expect(find.text('Roll 102'), findsNothing);
    });

    testWidgets('ResultScreen has Home and Scan Next Sheet pinned in bottomNavigationBar', (WidgetTester tester) async {
      final key = AnswerKey(
        id: 'res_test_key',
        examName: 'Math Quiz',
        createdAt: DateTime.now(),
        totalQuestions: 10,
        answers: {1: 'A'},
      );

      final result = ExamResult(
        id: 'res_test_1',
        examName: key.examName,
        scannedAt: DateTime.now(),
        totalQuestions: 10,
        correct: 8,
        wrong: 2,
        blank: 0,
        multiple: 0,
        reviewRequired: 0,
        score: 8.0,
        percentage: 80.0,
        questionResults: [],
        rollNumber: '5',
      );

      await tester.pumpWidget(MaterialApp(
        home: ResultScreen(
          examResult: result,
          answerKey: key,
        ),
      ));
      await tester.pumpAndSettle();

      // Home and Scan Next Sheet are immediately visible
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Scan Next Sheet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

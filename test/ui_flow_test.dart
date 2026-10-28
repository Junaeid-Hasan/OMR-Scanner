import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omr_scanner/models/answer_key.dart';
import 'package:omr_scanner/models/detected_answer.dart';
import 'package:omr_scanner/models/scan_result.dart';
import 'package:omr_scanner/screens/review/review_screen.dart';
import 'package:omr_scanner/services/storage_service.dart';

void main() {
  testWidgets('Complete Teacher UI Workflow: Review -> Correction -> Result', (WidgetTester tester) async {
    await StorageService().init(inMemoryOnly: true);

    // Create a 30-question key
    final answers = <int, String>{};
    for (int i = 1; i <= 30; i++) {
      answers[i] = 'A';
    }
    final key = AnswerKey(
      id: 'flow_key',
      examName: 'Midterm Physics',
      createdAt: DateTime.now(),
      totalQuestions: 30,
      answers: answers,
    );

    // Create simulated student scan result with 1 uncertain answer (Q5)
    final detected = <int, DetectedAnswer>{};
    for (int i = 1; i <= 30; i++) {
      if (i == 5) {
        // Q5 is UNCERTAIN
        detected[i] = DetectedAnswer(
          questionNumber: 5,
          selectedOptions: ['B'],
          classification: AnswerClassification.uncertain,
          confidence: 0.35,
          bubbleScores: {'B': 0.35},
        );
      } else {
        // Correct 'A'
        detected[i] = DetectedAnswer(
          questionNumber: i,
          selectedOptions: ['A'],
          classification: AnswerClassification.single,
          confidence: 0.95,
          bubbleScores: {'A': 0.9},
          primaryAnswer: 'A',
        );
      }
    }

    final scanResult = ScanResult(
      status: ScanStatus.uncertain,
      message: '1 mark requires teacher review',
      detectedAnswers: detected,
      sheetDetectionConfidence: 0.95,
    );

    // Pump Review Screen directly
    await tester.pumpWidget(MaterialApp(
      home: ReviewScreen(scanResult: scanResult, answerKey: key),
    ));
    await tester.pumpAndSettle();

    // Verify Review screen elements
    expect(find.text('Review Sheet Scan'), findsOneWidget);
    expect(find.textContaining('1 question(s) need review'), findsOneWidget);
    expect(find.text('Score: 29 / 30'), findsOneWidget);

    // Tap on Question 5 to review and correct
    await tester.tap(find.text('Q5'));
    await tester.pumpAndSettle();

    expect(find.text('Question 5 Review'), findsOneWidget);

    // Teacher confirms answer is 'A'
    final optAButtons = find.widgetWithText(ElevatedButton, 'A');
    await tester.tap(optAButtons.last);
    await tester.pumpAndSettle();

    // Score should now be dynamically updated to 30 / 30!
    expect(find.text('Score: 30 / 30'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);

    // Finalize results
    await tester.tap(find.text('Confirm & View Result'));
    await tester.pumpAndSettle();

    // Verify Result Screen is displayed
    expect(find.text('Exam Result'), findsOneWidget);
    expect(find.text(' / 30'), findsOneWidget); // Score on ScoreCard
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('Detailed Question Breakdown'), findsOneWidget);
  });
}

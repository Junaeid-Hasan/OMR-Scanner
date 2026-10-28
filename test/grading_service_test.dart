import 'package:flutter_test/flutter_test.dart';
import 'package:omr_scanner/models/answer_key.dart';
import 'package:omr_scanner/models/detected_answer.dart';
import 'package:omr_scanner/models/question_result.dart';
import 'package:omr_scanner/services/grading_service.dart';

void main() {
  group('GradingService Offline Tests', () {
    late GradingService gradingService;
    late AnswerKey answerKey;

    setUp(() {
      gradingService = GradingService();
      // Generate sample 30-question answer key
      final answers = <int, String>{};
      for (int i = 1; i <= 30; i++) {
        answers[i] = ['A', 'B', 'C', 'D'][(i - 1) % 4];
      }
      answerKey = AnswerKey(
        id: 'test_key_1',
        examName: 'Math Test',
        createdAt: DateTime.now(),
        totalQuestions: 30,
        answers: answers,
      );
    });

    test('All correct answers yield 100% score', () {
      final studentAnswers = <int, DetectedAnswer>{};
      for (int i = 1; i <= 30; i++) {
        final correctOpt = answerKey.answers[i]!;
        studentAnswers[i] = DetectedAnswer(
          questionNumber: i,
          selectedOptions: [correctOpt],
          classification: AnswerClassification.single,
          confidence: 0.95,
          bubbleScores: {correctOpt: 0.90},
          primaryAnswer: correctOpt,
        );
      }

      final result = gradingService.grade(
        examId: 'res_1',
        examName: answerKey.examName,
        answerKey: answerKey,
        studentAnswers: studentAnswers,
      );

      expect(result.correct, 30);
      expect(result.wrong, 0);
      expect(result.blank, 0);
      expect(result.multiple, 0);
      expect(result.reviewRequired, 0);
      expect(result.score, 30.0);
      expect(result.percentage, 100.0);
    });

    test('Blank and Multiple answers award 0 marks', () {
      final studentAnswers = <int, DetectedAnswer>{
        1: const DetectedAnswer(
          questionNumber: 1,
          selectedOptions: [],
          classification: AnswerClassification.blank,
          confidence: 0.90,
          bubbleScores: {},
        ),
        2: const DetectedAnswer(
          questionNumber: 2,
          selectedOptions: ['A', 'B'],
          classification: AnswerClassification.multiple,
          confidence: 0.90,
          bubbleScores: {'A': 0.8, 'B': 0.8},
        ),
      };

      final result = gradingService.grade(
        examId: 'res_2',
        examName: answerKey.examName,
        answerKey: answerKey,
        studentAnswers: studentAnswers,
      );

      expect(result.blank, 29); // Q1 explicit + Q3..Q30 missing
      expect(result.multiple, 1);
      expect(result.score, 0.0);
    });

    test('Uncertain answers trigger review status', () {
      final studentAnswers = <int, DetectedAnswer>{
        5: const DetectedAnswer(
          questionNumber: 5,
          selectedOptions: ['A'],
          classification: AnswerClassification.uncertain,
          confidence: 0.40,
          bubbleScores: {'A': 0.3},
        ),
      };

      final result = gradingService.grade(
        examId: 'res_3',
        examName: answerKey.examName,
        answerKey: answerKey,
        studentAnswers: studentAnswers,
      );

      expect(result.reviewRequired, 1);
      final q5 = result.questionResults.firstWhere((q) => q.questionNumber == 5);
      expect(q5.status, QuestionStatus.review);
      expect(q5.marks, 0.0);
    });
  });
}

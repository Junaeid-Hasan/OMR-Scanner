import '../models/answer_key.dart';
import '../models/detected_answer.dart';
import '../models/question_result.dart';
import '../models/exam_result.dart';

class GradingService {
  /// Evaluates student answers against the teacher answer key according to strict rules.
  ExamResult grade({
    required String examId,
    required String examName,
    required AnswerKey answerKey,
    required Map<int, DetectedAnswer> studentAnswers,
    String? annotatedImagePath,
    String? rollNumber,
    String? setCode,
    String? registrationNumber,
    String? subjectCode,
    String classMode = 'class_6_8',
  }) {
    final List<QuestionResult> questionResults = [];
    int correct = 0;
    int wrong = 0;
    int blank = 0;
    int multiple = 0;
    int review = 0;
    double totalScore = 0.0;

    // In Class 9-10 mode, look up the answers for the detected setCode
    final effectiveAnswers = answerKey.isClass9And10
        ? answerKey.getAnswersForSet(setCode)
        : answerKey.answers;

    final effectiveTotalQuestions = answerKey.totalQuestions > 0
        ? answerKey.totalQuestions
        : (effectiveAnswers.isNotEmpty ? effectiveAnswers.length : 30);

    for (int q = 1; q <= effectiveTotalQuestions; q++) {
      final correctAnswer = effectiveAnswers[q] ?? '';
      final detected = studentAnswers[q];

      if (detected == null || detected.classification == AnswerClassification.blank) {
        blank++;
        questionResults.add(QuestionResult(
          questionNumber: q,
          studentAnswer: null,
          correctAnswer: correctAnswer,
          status: QuestionStatus.blank,
          marks: 0.0,
          confidence: detected?.confidence ?? 1.0,
        ));
      } else if (detected.classification == AnswerClassification.uncertain) {
        review++;
        questionResults.add(QuestionResult(
          questionNumber: q,
          studentAnswer: detected.selectedOptions.isNotEmpty ? detected.selectedOptions.join(',') : null,
          correctAnswer: correctAnswer,
          status: QuestionStatus.review,
          marks: 0.0,
          confidence: detected.confidence,
        ));
      } else if (detected.classification == AnswerClassification.multiple) {
        multiple++;
        questionResults.add(QuestionResult(
          questionNumber: q,
          studentAnswer: detected.selectedOptions.join(','),
          correctAnswer: correctAnswer,
          status: QuestionStatus.multiple,
          marks: 0.0,
          confidence: detected.confidence,
        ));
      } else {
        // SINGLE
        final ans = detected.primaryAnswer ?? (detected.selectedOptions.isNotEmpty ? detected.selectedOptions.first : '');
        if (ans.toUpperCase() == correctAnswer.toUpperCase()) {
          correct++;
          totalScore += 1.0;
        } else {
          wrong++;
        }
        questionResults.add(QuestionResult(
          questionNumber: q,
          studentAnswer: ans,
          correctAnswer: correctAnswer,
          status: ans.toUpperCase() == correctAnswer.toUpperCase()
              ? QuestionStatus.correct
              : QuestionStatus.wrong,
          marks: ans.toUpperCase() == correctAnswer.toUpperCase() ? 1.0 : 0.0,
          confidence: detected.confidence,
        ));
      }
    }

    final double percentage = effectiveTotalQuestions > 0
        ? (totalScore / effectiveTotalQuestions) * 100.0
        : 0.0;

    return ExamResult(
      id: examId,
      examName: examName,
      scannedAt: DateTime.now(),
      totalQuestions: effectiveTotalQuestions,
      correct: correct,
      wrong: wrong,
      blank: blank,
      multiple: multiple,
      reviewRequired: review,
      score: totalScore,
      percentage: double.parse(percentage.toStringAsFixed(2)),
      questionResults: questionResults,
      annotatedImagePath: annotatedImagePath,
      rollNumber: rollNumber,
      setCode: setCode,
      registrationNumber: registrationNumber,
      subjectCode: subjectCode,
      classMode: classMode,
    );
  }
}

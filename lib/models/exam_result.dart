import 'question_result.dart';

class ExamResult {
  final String id;
  final String examName;
  final DateTime scannedAt;
  final int totalQuestions;
  final int correct;
  final int wrong;
  final int blank;
  final int multiple;
  final int reviewRequired;
  final double score;
  final double percentage;
  final List<QuestionResult> questionResults;
  final String? annotatedImagePath;
  final String? rollNumber;
  final String? setCode;
  final String? registrationNumber;
  final String? subjectCode;
  final String classMode;

  const ExamResult({
    required this.id,
    required this.examName,
    required this.scannedAt,
    this.totalQuestions = 30,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.multiple,
    required this.reviewRequired,
    required this.score,
    required this.percentage,
    required this.questionResults,
    this.annotatedImagePath,
    this.rollNumber,
    this.setCode,
    this.registrationNumber,
    this.subjectCode,
    this.classMode = 'class_6_8',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'examName': examName,
        'scannedAt': scannedAt.toIso8601String(),
        'totalQuestions': totalQuestions,
        'correct': correct,
        'wrong': wrong,
        'blank': blank,
        'multiple': multiple,
        'reviewRequired': reviewRequired,
        'score': score,
        'percentage': percentage,
        'questionResults': questionResults.map((e) => e.toJson()).toList(),
        'annotatedImagePath': annotatedImagePath,
        'rollNumber': rollNumber,
        'setCode': setCode,
        'registrationNumber': registrationNumber,
        'subjectCode': subjectCode,
        'classMode': classMode,
      };

  factory ExamResult.fromJson(Map<String, dynamic> json) {
    return ExamResult(
      id: json['id'] as String,
      examName: json['examName'] as String,
      scannedAt: DateTime.parse(json['scannedAt'] as String),
      totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 30,
      correct: (json['correct'] as num).toInt(),
      wrong: (json['wrong'] as num).toInt(),
      blank: (json['blank'] as num).toInt(),
      multiple: (json['multiple'] as num).toInt(),
      reviewRequired: (json['reviewRequired'] as num).toInt(),
      score: (json['score'] as num).toDouble(),
      percentage: (json['percentage'] as num).toDouble(),
      questionResults: (json['questionResults'] as List)
          .map((e) => QuestionResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      annotatedImagePath: json['annotatedImagePath'] as String?,
      rollNumber: json['rollNumber'] as String?,
      setCode: json['setCode'] as String?,
      registrationNumber: json['registrationNumber'] as String?,
      subjectCode: json['subjectCode'] as String?,
      classMode: (json['classMode'] as String?) ?? 'class_6_8',
    );
  }
}

enum QuestionStatus {
  correct,
  wrong,
  blank,
  multiple,
  review,
}

class QuestionResult {
  final int questionNumber;
  final String? studentAnswer;
  final String correctAnswer;
  final QuestionStatus status;
  final double marks;
  final double confidence;

  const QuestionResult({
    required this.questionNumber,
    this.studentAnswer,
    required this.correctAnswer,
    required this.status,
    required this.marks,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'studentAnswer': studentAnswer,
        'correctAnswer': correctAnswer,
        'status': status.name,
        'marks': marks,
        'confidence': confidence,
      };

  factory QuestionResult.fromJson(Map<String, dynamic> json) {
    return QuestionResult(
      questionNumber: json['questionNumber'] as int,
      studentAnswer: json['studentAnswer'] as String?,
      correctAnswer: json['correctAnswer'] as String,
      status: QuestionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => QuestionStatus.wrong,
      ),
      marks: (json['marks'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  QuestionResult copyWith({
    int? questionNumber,
    String? studentAnswer,
    String? correctAnswer,
    QuestionStatus? status,
    double? marks,
    double? confidence,
  }) {
    return QuestionResult(
      questionNumber: questionNumber ?? this.questionNumber,
      studentAnswer: studentAnswer ?? this.studentAnswer,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      status: status ?? this.status,
      marks: marks ?? this.marks,
      confidence: confidence ?? this.confidence,
    );
  }
}

enum AnswerClassification {
  single,
  blank,
  multiple,
  uncertain,
}

class DetectedAnswer {
  final int questionNumber;
  final List<String> selectedOptions;
  final AnswerClassification classification;
  final double confidence;
  final Map<String, double> bubbleScores;
  final String? primaryAnswer;

  const DetectedAnswer({
    required this.questionNumber,
    required this.selectedOptions,
    required this.classification,
    required this.confidence,
    required this.bubbleScores,
    this.primaryAnswer,
  });

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'selectedOptions': selectedOptions,
        'classification': classification.name,
        'confidence': confidence,
        'bubbleScores': bubbleScores,
        'primaryAnswer': primaryAnswer,
      };

  factory DetectedAnswer.fromJson(Map<String, dynamic> json) {
    return DetectedAnswer(
      questionNumber: json['questionNumber'] as int,
      selectedOptions: List<String>.from(json['selectedOptions'] as List),
      classification: AnswerClassification.values.firstWhere(
        (e) => e.name == json['classification'],
        orElse: () => AnswerClassification.uncertain,
      ),
      confidence: (json['confidence'] as num).toDouble(),
      bubbleScores: Map<String, double>.from(
        (json['bubbleScores'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ),
      ),
      primaryAnswer: json['primaryAnswer'] as String?,
    );
  }

  DetectedAnswer copyWith({
    int? questionNumber,
    List<String>? selectedOptions,
    AnswerClassification? classification,
    double? confidence,
    Map<String, double>? bubbleScores,
    String? primaryAnswer,
  }) {
    return DetectedAnswer(
      questionNumber: questionNumber ?? this.questionNumber,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      classification: classification ?? this.classification,
      confidence: confidence ?? this.confidence,
      bubbleScores: bubbleScores ?? this.bubbleScores,
      primaryAnswer: primaryAnswer ?? this.primaryAnswer,
    );
  }
}

class AnswerKey {
  final String id;
  final String examName;
  final DateTime createdAt;
  final int totalQuestions;
  final Map<int, String> answers; // Default or Set A answers: {1: 'A', 2: 'C', ...}
  final String classMode; // 'class_6_8' or 'class_9_10'
  final Map<String, Map<int, String>> setAnswers; // e.g. {'ক': {...}, 'খ': {...}, 'গ': {...}, 'ঘ': {...}}

  const AnswerKey({
    required this.id,
    required this.examName,
    required this.createdAt,
    this.totalQuestions = 30,
    required this.answers,
    this.classMode = 'class_6_8',
    this.setAnswers = const {},
  });

  bool get isClass9And10 => classMode == 'class_9_10';

  bool get isComplete => answers.length == totalQuestions;

  /// Retrieves answers for a specific set code ('ক', 'খ', 'গ', 'ঘ' or 'A', 'B', 'C', 'D').
  Map<int, String> getAnswersForSet(String? setCode) {
    if (!isClass9And10 || setCode == null || setCode.trim().isEmpty) {
      return answers;
    }
    final raw = setCode.trim();
    final upper = raw.toUpperCase();

    if (setAnswers.containsKey(raw)) return setAnswers[raw]!;
    if (setAnswers.containsKey(upper)) return setAnswers[upper]!;

    String? alt;
    switch (raw) {
      case 'ক': alt = 'A'; break;
      case 'খ': alt = 'B'; break;
      case 'গ': alt = 'C'; break;
      case 'ঘ': alt = 'D'; break;
      case 'A': alt = 'ক'; break;
      case 'B': alt = 'খ'; break;
      case 'C': alt = 'গ'; break;
      case 'D': alt = 'ঘ'; break;
    }
    if (alt != null && setAnswers.containsKey(alt)) {
      return setAnswers[alt]!;
    }

    return answers;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'examName': examName,
        'createdAt': createdAt.toIso8601String(),
        'totalQuestions': totalQuestions,
        'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
        'classMode': classMode,
        'setAnswers': setAnswers.map(
          (setKey, setMap) => MapEntry(
            setKey,
            setMap.map((k, v) => MapEntry(k.toString(), v)),
          ),
        ),
      };

  factory AnswerKey.fromJson(Map<String, dynamic> json) {
    final Map<String, Map<int, String>> sets = {};
    if (json['setAnswers'] != null && json['setAnswers'] is Map) {
      (json['setAnswers'] as Map).forEach((k, v) {
        if (v is Map) {
          sets[k.toString()] = v.map((qk, qv) => MapEntry(int.parse(qk.toString()), qv as String));
        }
      });
    }

    final parsedAnswers = (json['answers'] as Map).map(
      (k, v) => MapEntry(int.parse(k.toString()), v as String),
    );

    return AnswerKey(
      id: json['id'] as String,
      examName: json['examName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 30,
      answers: parsedAnswers,
      classMode: (json['classMode'] as String?) ?? 'class_6_8',
      setAnswers: sets.isNotEmpty ? sets : (json['classMode'] == 'class_9_10' ? {'ক': parsedAnswers} : const {}),
    );
  }

  AnswerKey copyWith({
    String? id,
    String? examName,
    DateTime? createdAt,
    int? totalQuestions,
    Map<int, String>? answers,
    String? classMode,
    Map<String, Map<int, String>>? setAnswers,
  }) {
    return AnswerKey(
      id: id ?? this.id,
      examName: examName ?? this.examName,
      createdAt: createdAt ?? this.createdAt,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      answers: answers ?? this.answers,
      classMode: classMode ?? this.classMode,
      setAnswers: setAnswers ?? this.setAnswers,
    );
  }
}


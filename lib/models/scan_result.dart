import 'dart:typed_data';
import 'detected_answer.dart';

enum ScanStatus {
  success,
  uncertain,
  failed,
}

class ScanResult {
  final ScanStatus status;
  final String message;
  final Map<int, DetectedAnswer> detectedAnswers;
  final double sheetDetectionConfidence;
  final String? imagePath;
  final String? annotatedImagePath;
  final Uint8List? annotatedImageBytes;
  final Uint8List? rectifiedImageBytes;
  final String? rollNumber;
  final String? setCode;
  final String? registrationNumber;
  final String? subjectCode;
  final String classMode;
  final String alignmentQuality;

  const ScanResult({
    required this.status,
    required this.message,
    required this.detectedAnswers,
    required this.sheetDetectionConfidence,
    this.imagePath,
    this.annotatedImagePath,
    this.annotatedImageBytes,
    this.rectifiedImageBytes,
    this.rollNumber,
    this.setCode,
    this.registrationNumber,
    this.subjectCode,
    this.classMode = 'class_6_8',
    this.alignmentQuality = 'Good',
  });

  int get uncertainCount => detectedAnswers.values
      .where((a) => a.classification == AnswerClassification.uncertain)
      .length;

  int get multipleCount => detectedAnswers.values
      .where((a) => a.classification == AnswerClassification.multiple)
      .length;

  int get blankCount => detectedAnswers.values
      .where((a) => a.classification == AnswerClassification.blank)
      .length;
}

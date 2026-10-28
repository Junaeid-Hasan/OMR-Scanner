import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/answer_key.dart';
import '../../models/exam_result.dart';
import '../../models/question_result.dart';
import '../../omr/template/omr_template.dart';
import '../../widgets/score_card.dart';
import '../camera/camera_screen.dart';

class ResultScreen extends StatelessWidget {
  final ExamResult examResult;
  final AnswerKey answerKey;

  const ResultScreen({
    super.key,
    required this.examResult,
    required this.answerKey,
  });

  @override
  Widget build(BuildContext context) {
    final hasAnnotatedImage = examResult.annotatedImagePath != null &&
        File(examResult.annotatedImagePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Result'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScoreCard(result: examResult),
            if (hasAnnotatedImage) ...[
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      color: Colors.blue.shade50,
                      child: const Row(
                        children: [
                          Icon(Icons.center_focus_strong, color: Color(0xFF1E56A0), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Scanned Sheet (Detected Answers Highlighted)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: Center(
                        child: Image.file(
                          File(examResult.annotatedImagePath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Detailed Question Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: examResult.questionResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final q = examResult.questionResults[index];
                  final isCorrect = q.status == QuestionStatus.correct;
                  final studentText = q.studentAnswer != null
                      ? '${OMRTemplate.toBangla(q.studentAnswer!)} (${q.studentAnswer})'
                      : 'BLANK';
                  final keyText = q.correctAnswer.isNotEmpty
                      ? '${OMRTemplate.toBangla(q.correctAnswer)} (${q.correctAnswer})'
                      : '-';

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: isCorrect ? Colors.green.shade50 : Colors.red.shade50,
                      child: Text(
                        '${q.questionNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCorrect ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Student: $studentText',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isCorrect ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'Key: $keyText',
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      isCorrect ? '+1.0' : '0.0',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCorrect ? Colors.green : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.home_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Home'),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Scan Next Sheet'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4338CA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(answerKey: answerKey),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

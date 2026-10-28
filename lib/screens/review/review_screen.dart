import 'package:flutter/material.dart';
import '../../models/answer_key.dart';
import '../../models/detected_answer.dart';
import '../../models/exam_result.dart';
import '../../models/question_result.dart';
import '../../models/scan_result.dart';
import '../../omr/template/omr_template.dart';
import '../../services/grading_service.dart';
import '../../services/storage_service.dart';
import '../preview/processed_image_screen.dart';
import '../result/result_screen.dart';

class ReviewScreen extends StatefulWidget {
  final ScanResult scanResult;
  final AnswerKey answerKey;
  final String? rollNumber;
  final String? setCode;
  final String? registrationNumber;
  final String? subjectCode;

  const ReviewScreen({
    super.key,
    required this.scanResult,
    required this.answerKey,
    this.rollNumber,
    this.setCode,
    this.registrationNumber,
    this.subjectCode,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final GradingService _gradingService = GradingService();
  late Map<int, DetectedAnswer> _studentAnswers;
  late ExamResult _currentExamResult;
  late String? _currentRoll;
  late String? _currentSetCode;
  late String? _currentReg;
  late String? _currentSubject;

  @override
  void initState() {
    super.initState();
    _studentAnswers = Map<int, DetectedAnswer>.from(widget.scanResult.detectedAnswers);
    _currentRoll = widget.rollNumber ?? widget.scanResult.rollNumber;
    _currentSetCode = widget.setCode ?? widget.scanResult.setCode ?? 'ক';
    _currentReg = widget.registrationNumber ?? widget.scanResult.registrationNumber;
    _currentSubject = widget.subjectCode ?? widget.scanResult.subjectCode;
    _recalculateGrading();
  }

  void _recalculateGrading() {
    setState(() {
      _currentExamResult = _gradingService.grade(
        examId: 'res_${DateTime.now().millisecondsSinceEpoch}',
        examName: widget.answerKey.examName,
        answerKey: widget.answerKey,
        studentAnswers: _studentAnswers,
        annotatedImagePath: widget.scanResult.annotatedImagePath,
        rollNumber: _currentRoll,
        setCode: _currentSetCode,
        registrationNumber: _currentReg,
        subjectCode: _currentSubject,
        classMode: widget.scanResult.classMode,
      );
    });
  }

  void _showCorrectionDialog(int qNum) {
    final currentAnswer = _studentAnswers[qNum];
    final effectiveAnswers = widget.answerKey.isClass9And10
        ? widget.answerKey.getAnswersForSet(_currentSetCode)
        : widget.answerKey.answers;
    final correctAnswer = effectiveAnswers[qNum] ?? '-';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Question $qNum Review',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Key: $correctAnswer',
                        style: const TextStyle(fontSize: 15, color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Detected state: ${currentAnswer?.classification.name.toUpperCase()} '
                  '(${currentAnswer?.selectedOptions.join(',') ?? 'None'})',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),
                const Divider(height: 24),
                const Text('Select teacher-verified answer:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(
                  children: ['A', 'B', 'C', 'D'].map((opt) {
                    final bangla = OMRTemplate.toBangla(opt);
                    final isSel = currentAnswer?.primaryAnswer == opt;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSel ? Theme.of(context).primaryColor : Colors.grey.shade100,
                            foregroundColor: isSel ? Colors.white : Colors.black87,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: () {
                            _applyCorrection(qNum, opt);
                            Navigator.pop(ctx);
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(bangla, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text(opt, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Center(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.clear, color: Colors.orange),
                    label: const Text('Mark as BLANK', style: TextStyle(color: Colors.orange)),
                    onPressed: () {
                      _applyCorrection(qNum, null);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyCorrection(int qNum, String? confirmedOption) {
    if (confirmedOption == null) {
      _studentAnswers[qNum] = DetectedAnswer(
        questionNumber: qNum,
        selectedOptions: [],
        classification: AnswerClassification.blank,
        confidence: 1.0,
        bubbleScores: _studentAnswers[qNum]?.bubbleScores ?? {},
      );
    } else {
      _studentAnswers[qNum] = DetectedAnswer(
        questionNumber: qNum,
        selectedOptions: [confirmedOption],
        classification: AnswerClassification.single,
        confidence: 1.0,
        bubbleScores: _studentAnswers[qNum]?.bubbleScores ?? {},
        primaryAnswer: confirmedOption,
      );
    }
    _recalculateGrading();
  }

  void _editMetadataField(String title, String initialValue, Function(String) onSave) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit $title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: 'Enter $title',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.trim();
              Navigator.pop(ctx);
              onSave(val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeResults() async {
    // Save to local storage
    await StorageService().saveExamResult(_currentExamResult);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            examResult: _currentExamResult,
            answerKey: widget.answerKey,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uncertainCount = _currentExamResult.reviewRequired;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Sheet Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'View Detected Sheet',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProcessedImageScreen(
                    scanResult: widget.scanResult,
                    answerKey: widget.answerKey,
                    rollNumber: widget.rollNumber,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: 'Finalize',
            onPressed: _finalizeResults,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner with review alert or score overview
          if (uncertainCount > 0)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$uncertainCount question(s) need review. Tap to confirm.',
                      style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          if (widget.scanResult.classMode == 'class_9_10') ...[
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Extracted Student Information',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Class 9-10', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Set Code Selector
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Set Code', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                              DropdownButton<String>(
                                value: _currentSetCode ?? 'ক',
                                isDense: true,
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: ['ক', 'খ', 'গ', 'ঘ'].map((s) {
                                  return DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      'Set $s',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF4338CA)),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _currentSetCode = val;
                                      _recalculateGrading();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Roll Number
                      Expanded(
                        child: InkWell(
                          onTap: () => _editMetadataField('Roll Number', _currentRoll ?? '', (v) {
                            setState(() {
                              _currentRoll = v;
                              _recalculateGrading();
                            });
                          }),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Text('Roll No', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                    Spacer(),
                                    Icon(Icons.edit, size: 12, color: Color(0xFF94A3B8)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentRoll?.isNotEmpty == true ? _currentRoll! : 'Empty',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _currentRoll?.isNotEmpty == true ? const Color(0xFF0F172A) : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Subject Code
                      Expanded(
                        child: InkWell(
                          onTap: () => _editMetadataField('Subject Code', _currentSubject ?? '', (v) {
                            setState(() {
                              _currentSubject = v;
                              _recalculateGrading();
                            });
                          }),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Text('Subject Code', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                    Spacer(),
                                    Icon(Icons.edit, size: 12, color: Color(0xFF94A3B8)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentSubject?.isNotEmpty == true ? _currentSubject! : 'Empty',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _currentSubject?.isNotEmpty == true ? const Color(0xFF0F172A) : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Registration Number
                      Expanded(
                        child: InkWell(
                          onTap: () => _editMetadataField('Registration Number', _currentReg ?? '', (v) {
                            setState(() {
                              _currentReg = v;
                              _recalculateGrading();
                            });
                          }),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Text('Registration No', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                    Spacer(),
                                    Icon(Icons.edit, size: 12, color: Color(0xFF94A3B8)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentReg?.isNotEmpty == true ? _currentReg! : 'Empty',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _currentReg?.isNotEmpty == true ? const Color(0xFF0F172A) : Colors.orange,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Live score pill with roll number and overflow protection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentRoll != null && _currentRoll!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFC7D2FE)),
                          ),
                          child: Text(
                            'Roll: $_currentRoll',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF4338CA)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_currentSetCode != null && _currentSetCode!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Text(
                            'Set: $_currentSetCode',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF059669)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          'Score: ${_currentExamResult.score.toInt()} / ${_currentExamResult.totalQuestions}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _currentExamResult.percentage >= 50
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _currentExamResult.percentage >= 50
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFFECDD3),
                    ),
                  ),
                  child: Text(
                    '${_currentExamResult.percentage}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _currentExamResult.percentage >= 50 ? const Color(0xFF059669) : const Color(0xFFE11D48),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Header Row
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                SizedBox(width: 60, child: Text('Q#', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Student', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Correct', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 80, child: Text('Status', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),

          // Question List
          Expanded(
            child: ListView.separated(
              itemCount: _currentExamResult.questionResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final q = _currentExamResult.questionResults[index];
                return _buildQuestionRow(q);
              },
            ),
          ),

          // Bottom Finalize Button
          Container(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _finalizeResults,
                icon: const Icon(Icons.task_alt),
                label: const Text('Confirm & View Result', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionRow(QuestionResult q) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (q.status) {
      case QuestionStatus.correct:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = '✓ 1.0';
        break;
      case QuestionStatus.wrong:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = '✗ 0.0';
        break;
      case QuestionStatus.blank:
        statusColor = Colors.orange;
        statusIcon = Icons.remove_circle_outline;
        statusText = 'Blank';
        break;
      case QuestionStatus.multiple:
        statusColor = Colors.purple;
        statusIcon = Icons.error_outline;
        statusText = 'Multiple';
        break;
      case QuestionStatus.review:
        statusColor = Colors.amber.shade800;
        statusIcon = Icons.help_outline;
        statusText = 'REVIEW';
        break;
    }

    final isUncertain = q.status == QuestionStatus.review;

    return ListTile(
      tileColor: isUncertain ? Colors.amber.shade50 : null,
      onTap: () => _showCorrectionDialog(q.questionNumber),
      title: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              'Q${q.questionNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          Expanded(
            child: Text(
              q.studentAnswer != null
                  ? '${OMRTemplate.toBangla(q.studentAnswer!)} (${q.studentAnswer})'
                  : 'BLANK',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isUncertain ? Colors.amber.shade900 : Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              q.correctAnswer.isNotEmpty
                  ? '${OMRTemplate.toBangla(q.correctAnswer)} (${q.correctAnswer})'
                  : '-',
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(width: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

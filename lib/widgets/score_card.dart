import 'package:flutter/material.dart';
import '../models/exam_result.dart';

class ScoreCard extends StatelessWidget {
  final ExamResult result;

  const ScoreCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isPassed = result.percentage >= 50;
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isPassed
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFF1F2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(
                  color: isPassed ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isPassed ? Icons.check_circle : Icons.info_outline,
                  color: isPassed ? const Color(0xFF059669) : const Color(0xFFE11D48),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        result.examName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isPassed ? const Color(0xFF065F46) : const Color(0xFF9F1239),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (result.rollNumber != null && result.rollNumber!.isNotEmpty)
                            Text(
                              'Student Roll: ${result.rollNumber}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isPassed ? const Color(0xFF047857) : const Color(0xFFBE123C),
                              ),
                            ),
                          if (result.setCode != null && result.setCode!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4338CA).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Set: ${result.setCode}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4338CA),
                                ),
                              ),
                            ),
                          if (result.subjectCode != null && result.subjectCode!.isNotEmpty)
                            Text(
                              'Subject: ${result.subjectCode}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                            ),
                          if (result.registrationNumber != null && result.registrationNumber!.isNotEmpty)
                            Text(
                              'Reg: ${result.registrationNumber}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPassed ? const Color(0xFF059669) : const Color(0xFFE11D48),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${result.percentage}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Score Body
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${result.score.toInt()}',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          color: primaryColor,
                          letterSpacing: -1,
                        ),
                      ),
                      Text(
                        ' / ${result.totalQuestions}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFF1F5F9), height: 1),
                const SizedBox(height: 16),

                // Metrics Badges Row (Using Wrap to avoid pixel overflow)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildStatBadge('Correct', '${result.correct}', const Color(0xFF059669), const Color(0xFFECFDF5)),
                    _buildStatBadge('Wrong', '${result.wrong}', const Color(0xFFE11D48), const Color(0xFFFFF1F2)),
                    _buildStatBadge('Blank', '${result.blank}', const Color(0xFF64748B), const Color(0xFFF1F5F9)),
                    if (result.multiple > 0)
                      _buildStatBadge('Multiple', '${result.multiple}', const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
                    if (result.reviewRequired > 0)
                      _buildStatBadge('Review', '${result.reviewRequired}', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color textColor, Color bgColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: textColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

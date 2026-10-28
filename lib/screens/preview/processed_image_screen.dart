import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/answer_key.dart';
import '../../models/scan_result.dart';
import '../review/review_screen.dart';

enum PreviewDisplayMode {
  detectedCircles,
  rectifiedOriginal,
}

class ProcessedImageScreen extends StatefulWidget {
  final ScanResult scanResult;
  final AnswerKey answerKey;
  final String? rollNumber;

  const ProcessedImageScreen({
    super.key,
    required this.scanResult,
    required this.answerKey,
    this.rollNumber,
  });

  @override
  State<ProcessedImageScreen> createState() => _ProcessedImageScreenState();
}

class _ProcessedImageScreenState extends State<ProcessedImageScreen> {
  final TransformationController _transformationController = TransformationController();
  PreviewDisplayMode _displayMode = PreviewDisplayMode.detectedCircles;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _toggleZoom() {
    if (_transformationController.value.isIdentity()) {
      _transformationController.value = Matrix4.identity()..scale(2.2);
    } else {
      _resetZoom();
    }
  }

  void _showLegendDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.palette_outlined, color: Color(0xFF1E56A0)),
            SizedBox(width: 8),
            Text('Overlay Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLegendRow(const Color(0xFF00DC00), 'Green Circle', 'Valid detected answer bubble (fill > 40%, distinct margin)'),
            const SizedBox(height: 12),
            _buildLegendRow(const Color(0xFF78B4F0), 'Blue Circle', 'Self-calibrating bubble grid candidate coordinate'),
            const SizedBox(height: 12),
            _buildLegendRow(const Color(0xFFFFA000), 'Amber Circle', 'Uncertain or low-contrast mark requiring teacher verification'),
            const SizedBox(height: 12),
            _buildLegendRow(const Color(0xFFB400DC), 'Purple Circle', 'Multiple marks detected for a single question'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendRow(Color color, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ],
    );
  }

  void _proceedToReview() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          scanResult: widget.scanResult,
          answerKey: widget.answerKey,
          rollNumber: widget.rollNumber ?? widget.scanResult.rollNumber,
          setCode: widget.scanResult.setCode,
          registrationNumber: widget.scanResult.registrationNumber,
          subjectCode: widget.scanResult.subjectCode,
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    final scan = widget.scanResult;

    if (_displayMode == PreviewDisplayMode.rectifiedOriginal && scan.rectifiedImageBytes != null) {
      return Image.memory(
        scan.rectifiedImageBytes!,
        fit: BoxFit.contain,
      );
    }

    if (scan.annotatedImageBytes != null) {
      return Image.memory(
        scan.annotatedImageBytes!,
        fit: BoxFit.contain,
      );
    }

    if (scan.annotatedImagePath != null && File(scan.annotatedImagePath!).existsSync()) {
      return Image.file(
        File(scan.annotatedImagePath!),
        fit: BoxFit.contain,
      );
    }

    if (scan.imagePath != null && File(scan.imagePath!).existsSync()) {
      return Image.file(
        File(scan.imagePath!),
        fit: BoxFit.contain,
      );
    }

    return const Center(
      child: Text(
        'Processed image preview unavailable',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scanResult;
    final int detectedCount = scan.detectedAnswers.length;
    final bool isClass910 = scan.classMode == 'class_9_10' || widget.answerKey.classMode == 'class_9_10';
    final int expectedCount = isClass910 ? 30 : widget.answerKey.totalQuestions;
    final int uncertain = scan.uncertainCount;
    final int multiple = scan.multipleCount;
    final String confidencePct = (scan.sheetDetectionConfidence * 100).toStringAsFixed(1);
    final bool isTemplateMismatch = (widget.answerKey.classMode == 'class_9_10' && scan.classMode != 'class_9_10') ||
        (widget.answerKey.classMode != 'class_9_10' && scan.classMode == 'class_9_10') ||
        (scan.detectedAnswers.isNotEmpty && widget.answerKey.totalQuestions != scan.detectedAnswers.length && widget.answerKey.totalQuestions == 25 && scan.detectedAnswers.length == 30);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Final Processed Sheet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Detected Circles & Calibration Grid',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade300),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Circle Color Legend',
            onPressed: _showLegendDialog,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Reset Zoom',
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Control Bar: Display Mode Toggle & Metrics
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1E293B),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<PreviewDisplayMode>(
                          segments: const [
                            ButtonSegment(
                              value: PreviewDisplayMode.detectedCircles,
                              icon: Icon(Icons.check_circle_outline, size: 16),
                              label: Text('Detected Circles', style: TextStyle(fontSize: 12)),
                            ),
                            ButtonSegment(
                              value: PreviewDisplayMode.rectifiedOriginal,
                              icon: Icon(Icons.crop_original, size: 16),
                              label: Text('Rectified Sheet', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                          selected: {_displayMode},
                          onSelectionChanged: (Set<PreviewDisplayMode> selection) {
                            setState(() {
                              _displayMode = selection.first;
                            });
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white;
                              }
                              return Colors.white70;
                            }),
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return const Color(0xFF2563EB);
                              }
                              return const Color(0xFF334155);
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (scan.classMode == 'class_9_10' || scan.setCode != null || scan.rollNumber != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(scan.rollNumber ?? widget.rollNumber ?? '-', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Roll', style: TextStyle(color: Colors.blue.shade200, fontSize: 10)),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(scan.setCode ?? '-', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Set Code', style: TextStyle(color: Colors.blue.shade200, fontSize: 10)),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(scan.subjectCode ?? '-', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Subject', style: TextStyle(color: Colors.blue.shade200, fontSize: 10)),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(scan.registrationNumber ?? '-', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Registration', style: TextStyle(color: Colors.blue.shade200, fontSize: 10)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isTemplateMismatch) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade600),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Template Mismatch: Scanned Class 9–10 sheet (30 Qs) with Answer Key configured for ${widget.answerKey.totalQuestions} Qs. Score will grade up to Q${min(detectedCount, widget.answerKey.totalQuestions)}.',
                              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Metrics Badges (Wrap to prevent overflow on narrow screens)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: scan.alignmentQuality == 'Good'
                              ? Colors.green.withValues(alpha: 0.2)
                              : (scan.alignmentQuality == 'Fair'
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : Colors.red.withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scan.alignmentQuality == 'Good'
                                ? Colors.green.withValues(alpha: 0.4)
                                : (scan.alignmentQuality == 'Fair'
                                    ? Colors.amber.withValues(alpha: 0.5)
                                    : Colors.red.withValues(alpha: 0.5)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              scan.alignmentQuality == 'Good'
                                  ? Icons.verified
                                  : (scan.alignmentQuality == 'Fair' ? Icons.info_outline : Icons.warning_amber_rounded),
                              size: 13,
                              color: scan.alignmentQuality == 'Good'
                                  ? Colors.greenAccent
                                  : (scan.alignmentQuality == 'Fair' ? Colors.amberAccent : Colors.redAccent),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Alignment: ${scan.alignmentQuality}',
                              style: TextStyle(
                                fontSize: 11,
                                color: scan.alignmentQuality == 'Good'
                                    ? Colors.greenAccent
                                    : (scan.alignmentQuality == 'Fair' ? Colors.amberAccent : Colors.redAccent),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.crop_free, size: 13, color: Colors.blue.shade300),
                            const SizedBox(width: 4),
                            Text(
                              '$detectedCount/$expectedCount Qs Mapped',
                              style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '$confidencePct% Quality',
                          style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (uncertain > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                '$uncertain Review Needed',
                                style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      if (multiple > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_2, size: 12, color: Colors.purpleAccent),
                              const SizedBox(width: 4),
                              Text(
                                '$multiple Multiple Marked',
                                style: const TextStyle(fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Zoom Hint Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.black.withValues(alpha: 0.4),
              child: const Text(
                'Pinch or double-tap anywhere on the sheet to zoom into individual bubbles',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ),

            // Main Interactive Zoomable Viewer
            Expanded(
              child: GestureDetector(
                onDoubleTap: _toggleZoom,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.7,
                  maxScale: 6.0,
                  boundaryMargin: const EdgeInsets.all(40),
                  child: Center(
                    child: _buildImageContent(),
                  ),
                ),
              ),
            ),

            // Bottom Navigation Actions
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                boxShadow: [
                  BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  // Retake Button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF475569)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retake', style: TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Proceed Button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.arrow_forward, size: 20),
                      label: const Text(
                        'Review Sheet Scan',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      onPressed: _proceedToReview,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

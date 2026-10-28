import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import '../../models/answer_key.dart';
import '../../models/exam_result.dart';
import '../../models/scan_result.dart';
import '../../services/omr_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/document_scanner_animation.dart';
import '../../widgets/roll_number_dialog.dart';
import '../answer_key/answer_key_screen.dart';
import '../camera/camera_screen.dart';
import '../result/result_screen.dart';
import '../preview/processed_image_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  String _currentMode = 'class_6_8';
  List<AnswerKey> _answerKeys = [];
  List<ExamResult> _recentResults = [];
  AnswerKey? _selectedKey;
  bool _isLoading = false;
  bool _isProcessingFile = false;
  String? _processingImagePath;
  String? _currentRollNumber;
  int _rollCounter = 1;

  @override
  void initState() {
    super.initState();
    _storageService.addListener(_onStorageChanged);
    _answerKeys = _storageService.getAnswerKeysForMode(_currentMode);
    _recentResults = _storageService.getExamResultsForMode(_currentMode);
    if (_answerKeys.isNotEmpty) {
      _selectedKey = _answerKeys.first;
    }
    _loadData();
  }

  @override
  void dispose() {
    _storageService.removeListener(_onStorageChanged);
    super.dispose();
  }

  void _onStorageChanged() {
    if (mounted) {
      setState(() {
        _answerKeys = _storageService.getAnswerKeysForMode(_currentMode);
        _recentResults = _storageService.getExamResultsForMode(_currentMode);
        if (_selectedKey == null || _selectedKey!.classMode != _currentMode) {
          _selectedKey = _answerKeys.isNotEmpty ? _answerKeys.first : null;
        }
      });
    }
  }

  Future<void> _loadData() async {
    if (!_storageService.isInitialized) {
      setState(() => _isLoading = true);
      await _storageService.init();
    }
    final keys = _storageService.getAnswerKeysForMode(_currentMode);
    final results = _storageService.getExamResultsForMode(_currentMode);

    if (mounted) {
      setState(() {
        _answerKeys = keys;
        _recentResults = results;
        if (_selectedKey == null || _selectedKey!.classMode != _currentMode) {
          _selectedKey = keys.isNotEmpty ? keys.first : null;
        }
        _isLoading = false;
      });
    }
  }

  void _switchMode(String mode) {
    if (_currentMode == mode) return;
    setState(() {
      _currentMode = mode;
      _answerKeys = _storageService.getAnswerKeysForMode(mode);
      _recentResults = _storageService.getExamResultsForMode(mode);
      _selectedKey = _answerKeys.isNotEmpty ? _answerKeys.first : null;
    });
  }

  void _showUserManualDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: Color(0xFF4338CA), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Manual & Guide',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Quick instructions for grading OMR sheets',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Simple Text Guidelines
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildManualStep(
                        step: '1',
                        title: 'Configure Answer Key',
                        description:
                            'Tap "New Key" on the home page. Type your exam title, select the correct option (A, B, C, D) for each question, and tap "Save Answer Key". If you select fewer than 30 questions, full marks automatically matches your count.',
                      ),
                      const SizedBox(height: 12),
                      _buildManualStep(
                        step: '2',
                        title: 'Hold Steady with Good Light',
                        description:
                            'Place the student\'s OMR sheet on a flat table under uniform lighting. Ensure all 4 corners and the outer border of the sheet are clearly visible.',
                      ),
                      const SizedBox(height: 12),
                      _buildManualStep(
                        step: '3',
                        title: 'Scan & Enter Roll Number',
                        description:
                            'Tap the center Camera button (or "Upload File" to pick an image). Type the student\'s Roll Number when prompted, then scan.',
                      ),
                      const SizedBox(height: 12),
                      _buildManualStep(
                        step: '4',
                        title: 'Review & Verify Results',
                        description:
                            'The app automatically detects marked bubbles. Any faint or ambiguous marks are highlighted. Tap any question to verify or adjust.',
                      ),
                      const SizedBox(height: 12),
                      _buildManualStep(
                        step: '5',
                        title: 'Instant Scoring & History',
                        description:
                            'Confirm the results to view obtained marks and detailed breakdown. Your recent scans history on the home page updates immediately.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4338CA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualStep({
    required String step,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF4338CA),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF475569),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<String?> _askRollNumber() async {
    final suggested = '$_rollCounter';
    final roll = await RollNumberDialog.show(context, initialRoll: suggested);
    if (roll != null && roll.isNotEmpty) {
      final parsed = int.tryParse(roll);
      if (parsed != null) {
        _rollCounter = parsed + 1;
      }
      // Allow dialog dismiss transition to cleanly finish without hitching
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return roll;
  }

  void _navigateToCreateKey([AnswerKey? existing]) async {
    final result = await Navigator.push<AnswerKey>(
      context,
      MaterialPageRoute(
        builder: (_) => AnswerKeyScreen(
          existingKey: existing,
          initialClassMode: _currentMode,
        ),
      ),
    );
    if (result != null) {
      if (result.classMode != _currentMode) {
        _currentMode = result.classMode;
      }
      _loadData();
      setState(() => _selectedKey = result);
    }
  }

  void _startCameraScanning() {
    if (_selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create or select an Answer Key first!'),
          backgroundColor: Colors.orange,
        ),
      );
      _navigateToCreateKey();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(answerKey: _selectedKey!),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _pickFromStorageAndScan() async {
    if (_selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create or select an Answer Key first!'),
          backgroundColor: Colors.orange,
        ),
      );
      _navigateToCreateKey();
      return;
    }

    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (file == null) return;

      final isClass910 = (_selectedKey?.classMode ?? _currentMode) == 'class_9_10';
      String? roll;
      if (!isClass910) {
        roll = await _askRollNumber();
        if (roll == null) return;
      }

      setState(() {
        _isProcessingFile = true;
        _processingImagePath = file.path;
        _currentRollNumber = roll ?? 'Auto-detecting...';
      });

      // Yield frame so the laser scanner animation mounts and renders initial sweep
      await Future.delayed(const Duration(milliseconds: 150));

      final omrService = OmrService();
      final stopwatch = Stopwatch()..start();
      final scanResult = await omrService.scanImage(
        file.path,
        classMode: _selectedKey?.classMode ?? _currentMode,
      );

      // Ensure laser animation runs cleanly for at least 800ms
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 800) {
        await Future.delayed(Duration(milliseconds: 800 - elapsed));
      }

      if (!mounted) return;
      setState(() => _isProcessingFile = false);

      if (scanResult.status == ScanStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(scanResult.message), backgroundColor: Colors.red),
        );
        return;
      }

      final finalRoll = (isClass910 && scanResult.rollNumber != null && scanResult.rollNumber!.isNotEmpty)
          ? scanResult.rollNumber!
          : (roll ?? '000000');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessedImageScreen(
            scanResult: scanResult,
            answerKey: _selectedKey!,
            rollNumber: finalRoll,
          ),
        ),
      ).then((_) => _loadData());
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _scanSampleSheet() async {
    if (_selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an Answer Key first!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isClass910 = (_selectedKey?.classMode ?? _currentMode) == 'class_9_10';
    final assetPath = isClass910
        ? 'assets/test_images/bangla_omr_class9_10_sample.jpg'
        : 'assets/test_images/bangla_omr_sample.jpg';

    try {
      final tempFile = File('${Directory.systemTemp.path}/sample_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final byteData = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      String? roll;
      if (!isClass910) {
        roll = '101';
      }

      setState(() {
        _isProcessingFile = true;
        _processingImagePath = tempFile.path;
        _currentRollNumber = roll ?? 'Auto-detecting...';
      });

      await Future.delayed(const Duration(milliseconds: 150));

      final omrService = OmrService();
      final stopwatch = Stopwatch()..start();
      final scanResult = await omrService.scanImage(
        tempFile.path,
        classMode: _selectedKey?.classMode ?? _currentMode,
      );

      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 800) {
        await Future.delayed(Duration(milliseconds: 800 - elapsed));
      }

      if (!mounted) return;
      setState(() => _isProcessingFile = false);

      if (scanResult.status == ScanStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(scanResult.message), backgroundColor: Colors.red),
        );
        return;
      }

      final finalRoll = (isClass910 && scanResult.rollNumber != null && scanResult.rollNumber!.isNotEmpty)
          ? scanResult.rollNumber!
          : (roll ?? '000000');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessedImageScreen(
            scanResult: scanResult,
            answerKey: _selectedKey!,
            rollNumber: finalRoll,
          ),
        ),
      ).then((_) => _loadData());
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sample scan error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icons/app_logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.document_scanner_rounded, color: Color(0xFF4338CA), size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'OMR Scanner',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF0F172A)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Scan Sample Sheet',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: const Icon(Icons.flash_on_rounded, color: Color(0xFF4338CA), size: 18),
            ),
            onPressed: _isProcessingFile ? null : _scanSampleSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4338CA)),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF4338CA),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 100.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Mode Selector (Class 6 - 8 vs Class 9 - 10)
                        _buildModeSelector(),

                        // 1. Active Exam Key Card
                        _buildActiveKeyCard(),
                        const SizedBox(height: 18),

                        // 2. Middle Section: Recent Scans History
                        _buildRecentHistorySection(),
                      ],
                    ),
                  ),
                ),

          // High-tech laser document scanning animation overlay
          if (_isProcessingFile)
            Container(
              color: Colors.black.withValues(alpha: 0.82),
              alignment: Alignment.center,
              child: DocumentScanningAnimation(
                imagePath: _processingImagePath,
                rollNumber: _currentRollNumber,
                examTitle: _selectedKey?.examName,
              ),
            ),
        ],
      ),

      // Bottom Action Dock: Center Camera button, beside Gallery icon & Sample
      bottomNavigationBar: _buildBottomActionDock(),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              title: 'Class 6 - 8',
              subtitle: 'Basic OMR Format',
              icon: Icons.school_outlined,
              activeIcon: Icons.school_rounded,
              mode: 'class_6_8',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildModeTab(
              title: 'Class 9 - 10',
              subtitle: '4 Sets • Roll • Reg • Sub',
              icon: Icons.history_edu_outlined,
              activeIcon: Icons.history_edu_rounded,
              mode: 'class_9_10',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required String subtitle,
    required IconData icon,
    required IconData activeIcon,
    required String mode,
  }) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF4338CA).withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
          border: isSelected ? Border.all(color: const Color(0xFFC7D2FE)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 20,
              color: isSelected ? const Color(0xFF4338CA) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF1E1B4B) : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF4338CA) : const Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveKeyCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Accent Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFFF1F5F9)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ACTIVE EXAM KEY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                if (_selectedKey != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      'Full Marks: ${_selectedKey!.totalQuestions}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _answerKeys.isEmpty
                ? Column(
                    children: [
                      const Text(
                        'No answer keys configured yet.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                          label: const Text('Create First Answer Key', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4338CA),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _navigateToCreateKey(),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active Exam Selector dropdown styled as a sleek card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF4338CA), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<AnswerKey>(
                                  isExpanded: true,
                                  value: _selectedKey,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF4338CA)),
                                  items: _answerKeys.map((k) {
                                    return DropdownMenuItem<AnswerKey>(
                                      value: k,
                                      child: Text(
                                        k.examName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: Color(0xFF1E1B4B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedKey = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Metrics & action pills row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.help_outline_rounded, size: 14, color: Color(0xFF475569)),
                                const SizedBox(width: 4),
                                Text(
                                  '${_selectedKey?.answers.length ?? 0} Questions',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Attractive styled Edit Button
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _navigateToCreateKey(_selectedKey),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_outlined, size: 14, color: Color(0xFF4338CA)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: Color(0xFF4338CA),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Attractive New Key Button with Gradient & Shadow
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _navigateToCreateKey(),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4338CA).withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_rounded, size: 16, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'New Key',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
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
      ),
    );
  }

  Widget _buildRecentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Recent Scans Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: Color(0xFF0F172A)),
                SizedBox(width: 6),
                Text(
                  'Recent Scans History',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_recentResults.length} records',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // History List or Empty State
        if (_recentResults.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            alignment: Alignment.center,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.document_scanner_outlined, size: 40, color: Color(0xFF4338CA)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Scans in History',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap the Camera button below to scan student sheets or pick from Gallery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentResults.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final res = _recentResults[index];
              final isPass = res.percentage >= 50;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: Row(
                    children: [
                      if (res.rollNumber != null && res.rollNumber!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFC7D2FE)),
                          ),
                          child: Text(
                            'Roll: ${res.rollNumber}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (res.setCode != null && res.setCode!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD8B4FE)),
                          ),
                          child: Text(
                            'Set: ${res.setCode}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7E22CE),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          res.examName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (res.classMode == 'class_9_10' &&
                            ((res.subjectCode != null && res.subjectCode!.isNotEmpty) ||
                             (res.registrationNumber != null && res.registrationNumber!.isNotEmpty))) ...[
                          Row(
                            children: [
                              if (res.subjectCode != null && res.subjectCode!.isNotEmpty)
                                Text(
                                  'Sub: ${res.subjectCode}  •  ',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                                ),
                              if (res.registrationNumber != null && res.registrationNumber!.isNotEmpty)
                                Text(
                                  'Reg: ${res.registrationNumber}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0D9488)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                        ],
                        Row(
                          children: [
                            Text(
                              '${res.scannedAt.year}-${res.scannedAt.month.toString().padLeft(2, '0')}-${res.scannedAt.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                            const Text(' • ', style: TextStyle(color: Color(0xFFCBD5E1))),
                            Flexible(
                              child: Text(
                                '${res.correct} Correct • ${res.wrong} Wrong',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Prominently display obtained marks instead of percentage
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isPass ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isPass ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${res.score.toInt()}/${res.totalQuestions}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: isPass ? const Color(0xFF059669) : const Color(0xFFE11D48),
                              ),
                            ),
                            Text(
                              'Marks',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 9,
                                color: isPass ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18),
                    ],
                  ),
                  onTap: () {
                    if (_selectedKey != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResultScreen(
                            examResult: res,
                            answerKey: _selectedKey!,
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildBottomActionDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Gallery Upload Button (beside camera)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isProcessingFile ? null : _pickFromStorageAndScan,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Icon(Icons.photo_library_rounded, color: Color(0xFF334155), size: 22),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Upload File',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Middle Prominent Camera Button
            GestureDetector(
              onTap: _isProcessingFile ? null : _startCameraScanning,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4338CA), Color(0xFF312E81)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4338CA).withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),

            // User Manual Guide Button
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showUserManualDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: const Icon(Icons.menu_book_rounded, color: Color(0xFF4338CA), size: 22),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'User Manual',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4338CA)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

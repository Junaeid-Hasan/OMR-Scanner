import 'package:flutter/material.dart';
import '../../models/answer_key.dart';
import '../../omr/template/omr_template.dart';
import '../../services/storage_service.dart';
import '../../widgets/answer_option_pill.dart';

class AnswerKeyScreen extends StatefulWidget {
  final AnswerKey? existingKey;
  final String initialClassMode;

  const AnswerKeyScreen({
    super.key,
    this.existingKey,
    this.initialClassMode = 'class_6_8',
  });

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  final Map<int, String> _answers = {};
  final Map<String, Map<int, String>> _setAnswers = {
    'ক': {},
    'খ': {},
    'গ': {},
    'ঘ': {},
  };
  late String _selectedMode;
  String _currentSet = 'ক';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.existingKey?.classMode ?? widget.initialClassMode;
    _nameController = TextEditingController(
      text: widget.existingKey?.examName ?? '',
    );
    if (widget.existingKey != null) {
      _answers.addAll(widget.existingKey!.answers);
      if (widget.existingKey!.setAnswers.isNotEmpty) {
        widget.existingKey!.setAnswers.forEach((k, v) {
          _setAnswers[k] = Map<int, String>.from(v);
        });
      } else {
        _setAnswers['ক'] = Map<int, String>.from(widget.existingKey!.answers);
      }
    }
    for (final s in ['ক', 'খ', 'গ', 'ঘ']) {
      _setAnswers.putIfAbsent(s, () => {});
    }
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  bool get _isClass9And10 => _selectedMode == 'class_9_10';
  Map<int, String> get _currentMap => _isClass9And10 ? _setAnswers[_currentSet]! : _answers;

  void _selectAnswer(int question, String option) {
    setState(() {
      final map = _currentMap;
      if (map[question] == option) {
        map.remove(question); // toggle off
      } else {
        map[question] = option;
      }
    });
  }

  int _countSection(int start, int end) {
    int count = 0;
    final map = _currentMap;
    for (int i = start; i <= end; i++) {
      if (map.containsKey(i)) count++;
    }
    return count;
  }

  void _clearSection(int start, int end) {
    setState(() {
      final map = _currentMap;
      for (int i = start; i <= end; i++) {
        map.remove(i);
      }
    });
  }

  void _copyCurrentSetToAll() {
    final current = Map<int, String>.from(_setAnswers[_currentSet]!);
    if (current.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Set $_currentSet has no answers to copy.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      for (final s in ['ক', 'খ', 'গ', 'ঘ']) {
        if (s != _currentSet) {
          _setAnswers[s] = Map<int, String>.from(current);
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied answers from Set $_currentSet to all other sets!'),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  Future<void> _saveKey() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an exam title.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
      return;
    }

    final activeMap = _currentMap;
    if (_isClass9And10) {
      final totalInAll = _setAnswers.values.fold<int>(0, (sum, m) => sum + m.length);
      if (totalInAll == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please configure at least 1 question answer for Class 9-10.'),
            backgroundColor: Color(0xFFE11D48),
          ),
        );
        return;
      }
    } else {
      if (activeMap.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please configure at least 1 question answer.'),
            backgroundColor: Color(0xFFE11D48),
          ),
        );
        return;
      }
    }

    final int effectiveTotal = _isClass9And10
        ? (_setAnswers['ক']?.length ?? 30).clamp(1, 30)
        : activeMap.length;

    final key = AnswerKey(
      id: widget.existingKey?.id ?? 'key_${DateTime.now().millisecondsSinceEpoch}',
      examName: name,
      createdAt: widget.existingKey?.createdAt ?? DateTime.now(),
      totalQuestions: effectiveTotal,
      answers: _isClass9And10 ? (_setAnswers['ক'] ?? {}) : _answers,
      classMode: _selectedMode,
      setAnswers: _isClass9And10 ? _setAnswers : const {},
    );

    await StorageService().saveAnswerKey(key);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Answer key saved for ${_isClass9And10 ? "Class 9-10 (4 Sets)" : "Class 6-8"}!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      Navigator.pop(context, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSelected = _currentMap.length;
    // Dynamic ratio: (0/selected answer keys number) or (totalSelected/totalSelected)
    final ratioText = totalSelected == 0 ? '0 / 0' : '$totalSelected / $totalSelected';
    final progress = totalSelected == 0 ? 0.0 : totalSelected / 30.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Configure Answer Key'),
        actions: [
          // Single Clear button for the currently active tab section
          TextButton.icon(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48), size: 18),
            label: const Text(
              'Clear Section',
              style: TextStyle(
                color: Color(0xFFE11D48),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            onPressed: () {
              final idx = _tabController.index;
              final start = idx * 10 + 1;
              final end = start + 9;
              _clearSection(start, end);
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                return TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: const Color(0xFF4338CA),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4338CA).withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('1–10'),
                          const SizedBox(width: 4),
                          _buildTabBadge(_countSection(1, 10)),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('11–20'),
                          const SizedBox(width: 4),
                          _buildTabBadge(_countSection(11, 20)),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('21–30'),
                          const SizedBox(width: 4),
                          _buildTabBadge(_countSection(21, 30)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Mode Selector: Class 6-8 vs Class 9-10
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'class_6_8',
                    icon: Icon(Icons.school_outlined, size: 16),
                    label: Text('Class 6–8 (1 Key)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ButtonSegment(
                    value: 'class_9_10',
                    icon: Icon(Icons.auto_stories_outlined, size: 16),
                    label: Text('Class 9–10 (4 Sets)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                selected: {_selectedMode},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _selectedMode = newSelection.first;
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF4338CA);
                    }
                    return Colors.white;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return const Color(0xFF475569);
                  }),
                ),
              ),
            ),

            // If Class 9-10: 4 Sets Tab Strip
            if (_isClass9And10) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    ...['ক', 'খ', 'গ', 'ঘ'].map((setCode) {
                      final isSelected = _currentSet == setCode;
                      final count = _setAnswers[setCode]?.length ?? 0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _currentSet = setCode;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF4338CA) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Set $setCode',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : const Color(0xFF334155),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$count Qs',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy_all_rounded, color: Color(0xFF4338CA), size: 20),
                      tooltip: 'Copy Set $_currentSet to other sets',
                      onPressed: _copyCurrentSetToAll,
                    ),
                  ],
                ),
              ),
            ],

            // Title Input & Full Marks Status Card
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: 'Exam Title / Subject',
                            hintText: 'e.g. Physics Midterm 2026',
                            prefixIcon: const Icon(Icons.assignment_outlined, color: Color(0xFF4338CA), size: 20),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF4338CA), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Dynamic Full Marks Counter Badge (changes 0/30 to 0/selected count)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: totalSelected > 0
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: totalSelected > 0
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFFC7D2FE),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                ratioText,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: totalSelected > 0
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF3730A3),
                                ),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                totalSelected > 0 ? 'Full Marks: $totalSelected' : 'No Keys',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: totalSelected > 0
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF6366F1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        totalSelected >= 30
                            ? const Color(0xFF059669)
                            : const Color(0xFF4338CA),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Question List with Tabs
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildQuestionList(1, 10),
                  _buildQuestionList(11, 20),
                  _buildQuestionList(21, 30),
                ],
              ),
            ),

            // Bottom Bar with the Single Save Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4338CA).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _saveKey,
                    icon: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        totalSelected > 0
                            ? 'Save Answer Key ($totalSelected Qs • Marks: $totalSelected)'
                            : 'Save Answer Key',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: count > 0 ? const Color(0xFF059669) : Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildQuestionList(int start, int end) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: end - start + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final qNum = start + index;
        final selectedOpt = _currentMap[qNum];
        final isAnswered = selectedOpt != null;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isAnswered ? const Color(0xFFF8FAFC) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAnswered
                  ? const Color(0xFF818CF8)
                  : const Color(0xFFE2E8F0),
              width: isAnswered ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isAnswered
                      ? const Color(0xFFEEF2FF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: isAnswered
                      ? Border.all(color: const Color(0xFFC7D2FE))
                      : null,
                ),
                child: Text(
                  'Q$qNum',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isAnswered
                        ? const Color(0xFF4338CA)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['A', 'B', 'C', 'D'].map((opt) {
                    final isSel = selectedOpt == opt;
                    return AnswerOptionPill(
                      label: opt,
                      subLabel: OMRTemplate.toBangla(opt),
                      isSelected: isSel,
                      onTap: () => _selectAnswer(qNum, opt),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

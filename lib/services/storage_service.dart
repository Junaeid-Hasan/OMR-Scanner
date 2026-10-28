import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/answer_key.dart';
import '../models/exam_result.dart';

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final Map<String, AnswerKey> _inMemoryAnswerKeys = {};
  final List<ExamResult> _inMemoryExamResults = [];

  Directory? _storageDir;
  bool _isInitialized = false;
  bool _inMemoryOnly = false;

  bool get isInitialized => _isInitialized;

  Future<void> init({Directory? customDir, bool inMemoryOnly = false}) async {
    _inMemoryOnly = inMemoryOnly;
    if (_inMemoryOnly) {
      _isInitialized = true;
      return;
    }

    if (_isInitialized && customDir == null) return;

    if (customDir != null) {
      _storageDir = customDir;
    } else {
      final dir = Directory('.omr_local_storage');
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (_) {}
      _storageDir = dir;
    }
    await _loadFromDisk();
    _isInitialized = true;
  }

  Future<void> _loadFromDisk() async {
    if (_inMemoryOnly || _storageDir == null) return;

    try {
      if (!await _storageDir!.exists()) return;

      final keyFile = File('${_storageDir!.path}/answer_keys.json');
      if (await keyFile.exists()) {
        final content = await keyFile.readAsString();
        final List list = jsonDecode(content) as List;
        for (var item in list) {
          final key = AnswerKey.fromJson(item as Map<String, dynamic>);
          _inMemoryAnswerKeys[key.id] = key;
        }
      }

      final resultFile = File('${_storageDir!.path}/exam_results.json');
      if (await resultFile.exists()) {
        final content = await resultFile.readAsString();
        final List list = jsonDecode(content) as List;
        _inMemoryExamResults.clear();
        for (var item in list) {
          _inMemoryExamResults.add(ExamResult.fromJson(item as Map<String, dynamic>));
        }
      }

      if (_inMemoryAnswerKeys.isEmpty) {
        final defaultKey = AnswerKey(
          id: 'default_bangla_key',
          examName: 'নৈর্ব্যক্তিক অভীক্ষা (Class 6-8)',
          createdAt: DateTime.now(),
          totalQuestions: 30,
          classMode: 'class_6_8',
          answers: {
            1: 'C', 2: 'B', 3: 'D', 4: 'C', 5: 'C',
            6: 'A', 7: 'B', 8: 'D', 9: 'D', 10: 'A',
            11: 'B', 12: 'D', 13: 'B', 14: 'C', 15: 'C',
            16: 'B', 17: 'D', 18: 'A', 19: 'A', 20: 'B',
            21: 'C', 22: 'D', 23: 'C', 24: 'D', 25: 'D',
            26: 'A', 27: 'B', 28: 'C', 29: 'D', 30: 'A',
          },
        );
        _inMemoryAnswerKeys[defaultKey.id] = defaultKey;

        // Also seed default 4-set key for Class 9-10
        final setKa = {
          1: 'A', 2: 'B', 3: 'C', 4: 'D', 5: 'A',
          6: 'B', 7: 'C', 8: 'D', 9: 'A', 10: 'B',
          11: 'C', 12: 'D', 13: 'A', 14: 'B', 15: 'C',
          16: 'B', 17: 'C', 18: 'D', 19: 'A', 20: 'B',
          21: 'C', 22: 'D', 23: 'A', 24: 'B', 25: 'C',
          26: 'D', 27: 'A', 28: 'B', 29: 'C', 30: 'D',
        };
        final setKha = {
          1: 'B', 2: 'C', 3: 'D', 4: 'A', 5: 'B',
          6: 'C', 7: 'D', 8: 'A', 9: 'B', 10: 'C',
          11: 'D', 12: 'A', 13: 'B', 14: 'C', 15: 'D',
          16: 'C', 17: 'D', 18: 'A', 19: 'B', 20: 'C',
          21: 'D', 22: 'A', 23: 'B', 24: 'C', 25: 'D',
          26: 'A', 27: 'B', 28: 'C', 29: 'D', 30: 'A',
        };
        final setGa = {
          1: 'C', 2: 'D', 3: 'A', 4: 'B', 5: 'C',
          6: 'D', 7: 'A', 8: 'B', 9: 'C', 10: 'D',
          11: 'A', 12: 'B', 13: 'C', 14: 'D', 15: 'A',
          16: 'D', 17: 'A', 18: 'B', 19: 'C', 20: 'D',
          21: 'A', 22: 'B', 23: 'C', 24: 'D', 25: 'A',
          26: 'B', 27: 'C', 28: 'D', 29: 'A', 30: 'B',
        };
        final setGha = {
          1: 'D', 2: 'A', 3: 'B', 4: 'C', 5: 'D',
          6: 'A', 7: 'B', 8: 'C', 9: 'D', 10: 'A',
          11: 'B', 12: 'C', 13: 'D', 14: 'A', 15: 'B',
          16: 'A', 17: 'B', 18: 'C', 19: 'D', 20: 'A',
          21: 'B', 22: 'C', 23: 'D', 24: 'A', 25: 'B',
          26: 'C', 27: 'D', 28: 'A', 29: 'B', 30: 'C',
        };

        final default910Key = AnswerKey(
          id: 'default_class9_10_key',
          examName: 'এসএসসি নৈর্ব্যক্তিক অভীক্ষা (Class 9-10)',
          createdAt: DateTime.now(),
          totalQuestions: 30,
          classMode: 'class_9_10',
          answers: setKa,
          setAnswers: {
            'ক': setKa,
            'খ': setKha,
            'গ': setGa,
            'ঘ': setGha,
          },
        );
        _inMemoryAnswerKeys[default910Key.id] = default910Key;

        await _persistKeys();
      }
    } catch (_) {}
  }

  Future<void> saveAnswerKey(AnswerKey answerKey) async {
    _inMemoryAnswerKeys[answerKey.id] = answerKey;
    notifyListeners();
    await _persistKeys();
  }

  Future<void> deleteAnswerKey(String id) async {
    _inMemoryAnswerKeys.remove(id);
    notifyListeners();
    await _persistKeys();
  }

  List<AnswerKey> getAllAnswerKeys() {
    final list = _inMemoryAnswerKeys.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<AnswerKey> getAnswerKeysForMode(String classMode) {
    final list = _inMemoryAnswerKeys.values
        .where((k) => k.classMode == classMode)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  AnswerKey? getAnswerKey(String id) => _inMemoryAnswerKeys[id];

  Future<void> _persistKeys() async {
    if (_inMemoryOnly || _storageDir == null) return;
    try {
      final keyFile = File('${_storageDir!.path}/answer_keys.json');
      final data = _inMemoryAnswerKeys.values.map((k) => k.toJson()).toList();
      await keyFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> saveExamResult(ExamResult result) async {
    _inMemoryExamResults.insert(0, result);
    notifyListeners();
    await _persistResults();
  }

  List<ExamResult> getAllExamResults() => List.unmodifiable(_inMemoryExamResults);

  List<ExamResult> getExamResultsForMode(String classMode) {
    return _inMemoryExamResults
        .where((r) => r.classMode == classMode)
        .toList();
  }

  Future<void> _persistResults() async {
    if (_inMemoryOnly || _storageDir == null) return;
    try {
      final resultFile = File('${_storageDir!.path}/exam_results.json');
      final data = _inMemoryExamResults.map((r) => r.toJson()).toList();
      await resultFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

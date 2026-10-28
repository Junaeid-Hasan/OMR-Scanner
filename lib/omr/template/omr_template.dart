import 'dart:math';

class SheetQuad {
  final Point<double> tl;
  final Point<double> tr;
  final Point<double> br;
  final Point<double> bl;

  const SheetQuad({
    required this.tl,
    required this.tr,
    required this.br,
    required this.bl,
  });

  Point<double> mapPoint(double u, double v) {
    final topX = (1 - u) * tl.x + u * tr.x;
    final topY = (1 - u) * tl.y + u * tr.y;
    final botX = (1 - u) * bl.x + u * br.x;
    final botY = (1 - u) * bl.y + u * br.y;
    return Point<double>(
      (1 - v) * topX + v * botX,
      (1 - v) * topY + v * botY,
    );
  }

  double get avgWidth => ((tr.x - tl.x).abs() + (br.x - bl.x).abs()) / 2.0;
  double get avgHeight => ((bl.y - tl.y).abs() + (br.y - tr.y).abs()) / 2.0;
  double get aspectRatio => avgWidth / avgHeight;
}

class BubbleCoord {
  final double x;
  final double y;
  final double radius;
  final double innerRadius;

  const BubbleCoord({
    required this.x,
    required this.y,
    required this.radius,
    required this.innerRadius,
  });
}

class OMRTemplate {
  final int canonicalWidth;
  final int canonicalHeight;
  final int totalQuestions;
  final List<String> options;
  final double emptyThreshold;
  final double filledThreshold;
  final double uncertaintyMargin;
  final Map<int, Map<String, BubbleCoord>> bubbles;

  // Normalized relative offsets within table bounding box (Landscape format)
  static const double headerHeightRatio = 0.0794;
  static const List<List<double>> columnOptionXOffsets = [
    [0.0977, 0.1650, 0.2258, 0.2855], // Section 1 (Q1-10): ক, খ, গ, ঘ
    [0.4125, 0.4786, 0.5380, 0.5969], // Section 2 (Q11-20): ক, খ, গ, ঘ
    [0.7254, 0.7925, 0.8533, 0.9135], // Section 3 (Q21-30): ক, খ, গ, ঘ
  ];

  // Normalized relative Y offsets for the 10 rows (Landscape format)
  static const List<double> landscapeRowYOffsets = [
    0.2095, 0.2833, 0.3574, 0.4337, 0.5074, 0.5876, 0.6639, 0.7432, 0.8194, 0.8905,
  ];

  // Normalized relative offsets for standard portrait sheet
  static const List<List<double>> portraitColumnXOffsets = [
    [0.1333, 0.1767, 0.2200, 0.2633], // Section 1 (Q1-10)
    [0.4417, 0.4850, 0.5283, 0.5717], // Section 2 (Q11-20)
    [0.7500, 0.7933, 0.8367, 0.8800], // Section 3 (Q21-30)
  ];

  OMRTemplate({
    this.canonicalWidth = 1024,
    this.canonicalHeight = 876,
    this.totalQuestions = 30,
    this.options = const ['A', 'B', 'C', 'D'],
    this.emptyThreshold = 0.20,
    this.filledThreshold = 0.45,
    this.uncertaintyMargin = 0.15,
    Map<int, Map<String, BubbleCoord>>? bubbles,
  }) : bubbles = bubbles ?? _buildCanonicalCoordinates();

  /// Convert standard option ('A', 'B', 'C', 'D') to Bangla ('ক', 'খ', 'গ', 'ঘ')
  static String toBangla(String option) {
    switch (option.trim().toUpperCase()) {
      case 'A':
        return 'ক';
      case 'B':
        return 'খ';
      case 'C':
        return 'গ';
      case 'D':
        return 'ঘ';
      default:
        return option;
    }
  }

  /// Convert Bangla option ('ক', 'খ', 'গ', 'ঘ') to English ('A', 'B', 'C', 'D')
  static String fromBangla(String option) {
    switch (option.trim()) {
      case 'ক':
        return 'A';
      case 'খ':
        return 'B';
      case 'গ':
        return 'C';
      case 'ঘ':
        return 'D';
      default:
        return option.toUpperCase();
    }
  }

  /// Build canonical coordinates based on table bounds
  static Map<int, Map<String, BubbleCoord>> _buildCanonicalCoordinates() {
    final Map<int, Map<String, BubbleCoord>> map = {};
    const optionsList = ['A', 'B', 'C', 'D'];
    const double w = 1024.0;
    const double h = 876.0;
    const double radius = 18.0;
    const double innerRadius = 12.0;

    for (int col = 0; col < 3; col++) {
      final startQ = col * 10 + 1;
      final xOffsets = columnOptionXOffsets[col];

      for (int row = 0; row < 10; row++) {
        final q = startQ + row;
        final yc = landscapeRowYOffsets[row] * h;
        map[q] = {};

        for (int optIdx = 0; optIdx < 4; optIdx++) {
          final opt = optionsList[optIdx];
          final xc = xOffsets[optIdx] * w;
          map[q]![opt] = BubbleCoord(
            x: xc,
            y: yc,
            radius: radius,
            innerRadius: innerRadius,
          );
        }
      }
    }
    return map;
  }

  /// Calculates bubble coordinates given table bounding box corners
  static Map<int, Map<String, BubbleCoord>> getCoordinatesForTable({
    required double tableLeft,
    required double tableTop,
    required double tableRight,
    required double tableBottom,
    double? headerBottom,
  }) {
    final Map<int, Map<String, BubbleCoord>> map = {};
    final double tableWidth = tableRight - tableLeft;
    final double effectiveHeaderBottom = headerBottom ?? (tableTop + headerHeightRatio * (tableBottom - tableTop));
    final double rowHeight = (tableBottom - effectiveHeaderBottom) / 10.0;
    final double radius = tableWidth * 0.015;
    final double innerRadius = radius * 0.7;

    const optionsList = ['A', 'B', 'C', 'D'];

    for (int col = 0; col < 3; col++) {
      final startQ = col * 10 + 1;
      final offsets = columnOptionXOffsets[col];

      for (int row = 0; row < 10; row++) {
        final q = startQ + row;
        final yc = effectiveHeaderBottom + (row + 0.5) * rowHeight;
        map[q] = {};

        for (int optIdx = 0; optIdx < 4; optIdx++) {
          final opt = optionsList[optIdx];
          final xc = tableLeft + offsets[optIdx] * tableWidth;
          map[q]![opt] = BubbleCoord(
            x: xc,
            y: yc,
            radius: radius,
            innerRadius: innerRadius,
          );
        }
      }
    }

    return map;
  }

  /// Calculates bubble coordinates for a standard portrait sheet using 4-corner quad mapping
  static Map<int, Map<String, BubbleCoord>> getCoordinatesForPortraitQuad(SheetQuad quad) {
    final Map<int, Map<String, BubbleCoord>> map = {};
    const startV = 0.2727;
    const endV = 0.7964;
    const rowDv = (endV - startV) / 9.0;
    final radius = quad.avgWidth * 0.015;
    final innerRadius = radius * 0.68;

    const optionsList = ['A', 'B', 'C', 'D'];

    for (int col = 0; col < 3; col++) {
      final startQ = col * 10 + 1;
      final offsets = portraitColumnXOffsets[col];

      for (int row = 0; row < 10; row++) {
        final q = startQ + row;
        final v = startV + row * rowDv;
        map[q] = {};

        for (int optIdx = 0; optIdx < 4; optIdx++) {
          final opt = optionsList[optIdx];
          final u = offsets[optIdx];
          final pt = quad.mapPoint(u, v);
          map[q]![opt] = BubbleCoord(
            x: pt.x,
            y: pt.y,
            radius: radius,
            innerRadius: innerRadius,
          );
        }
      }
    }

    return map;
  }
}

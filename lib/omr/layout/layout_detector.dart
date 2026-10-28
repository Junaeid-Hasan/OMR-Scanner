import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../geometry/quadrilateral.dart';

class NormalizedBubble {
  final String option;
  final double normX;
  final double normY;
  final double pixelX;
  final double pixelY;
  final double radius;
  final double innerRadius;

  const NormalizedBubble({
    required this.option,
    required this.normX,
    required this.normY,
    required this.pixelX,
    required this.pixelY,
    required this.radius,
    required this.innerRadius,
  });
}

class DetectedQuestionRow {
  final int questionNumber;
  final int columnIndex;
  final int rowIndexInColumn;
  final double anchorY;
  final Map<String, NormalizedBubble> bubbles;

  const DetectedQuestionRow({
    required this.questionNumber,
    required this.columnIndex,
    required this.rowIndexInColumn,
    required this.anchorY,
    required this.bubbles,
  });
}

class DetectedLayout {
  final int totalQuestions;
  final int columnCount;
  final int optionsPerQuestion;
  final List<String> optionLabels;
  final Map<int, DetectedQuestionRow> questionRows;
  final double confidence;
  final String layoutType;

  const DetectedLayout({
    required this.totalQuestions,
    required this.columnCount,
    required this.optionsPerQuestion,
    required this.optionLabels,
    required this.questionRows,
    required this.confidence,
    required this.layoutType,
  });
}

/// Discovers the structural layout (columns, question rows, bubble groups)
/// from the normalized sheet image using self-calibrating dynamic grid reconstruction.
class LayoutDetector {
  final int expectedQuestions;
  final List<String> expectedOptions;

  const LayoutDetector({
    this.expectedQuestions = 30,
    this.expectedOptions = const ['A', 'B', 'C', 'D'],
  });

  /// Analyzes the rectified [image] and returns the detected OMR structure.
  /// Uses adaptive integral-image thresholding + CC labeling to locate actual bubbles.
  /// Falls back to canonical template coordinates if fewer than 25 bubbles are extracted.
  DetectedLayout detectLayout(img.Image image) {
    final w = image.width;
    final h = image.height;
    final isPortrait = h > w;
    final colWidth = w / 3.0;
    final expectedR = h / (11.0 * 2.0 * 2.2);

    // 1. Grayscale & adaptive thresholding using integral image
    final gray = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        gray[y * w + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }

    final integral = Int32List((w + 1) * (h + 1));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += gray[y * w + x];
        integral[(y + 1) * (w + 1) + (x + 1)] = integral[y * (w + 1) + (x + 1)] + rowSum;
      }
    }

    final binaryInv = Uint8List(w * h);
    const kHalf = 15;
    for (int y = 0; y < h; y++) {
      final y0 = max(0, y - kHalf);
      final y1 = min(h, y + kHalf + 1);
      for (int x = 0; x < w; x++) {
        final x0 = max(0, x - kHalf);
        final x1 = min(w, x + kHalf + 1);
        final count = (y1 - y0) * (x1 - x0);
        final sum = integral[y1 * (w + 1) + x1] -
                    integral[y0 * (w + 1) + x1] -
                    integral[y1 * (w + 1) + x0] +
                    integral[y0 * (w + 1) + x0];
        final mean = sum / count;
        if (gray[y * w + x] < (mean - 9)) {
          binaryInv[y * w + x] = 1;
        }
      }
    }

    // 2. Connected components labeling
    final labels = Int32List(w * h);
    final parent = <int>[0];
    int nextLabel = 1;

    int findRoot(int i) {
      var root = i;
      while (root != parent[root]) {
        root = parent[root];
      }
      var curr = i;
      while (curr != root) {
        final nxt = parent[curr];
        parent[curr] = root;
        curr = nxt;
      }
      return root;
    }

    void union(int i, int j) {
      final rootI = findRoot(i);
      final rootJ = findRoot(j);
      if (rootI != rootJ) {
        if (rootI < rootJ) {
          parent[rootJ] = rootI;
        } else {
          parent[rootI] = rootJ;
        }
      }
    }

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (binaryInv[y * w + x] == 1) {
          final nw = labels[(y - 1) * w + (x - 1)];
          final n = labels[(y - 1) * w + x];
          final ne = labels[(y - 1) * w + (x + 1)];
          final wst = labels[y * w + (x - 1)];

          final neighbors = <int>[];
          if (nw > 0) neighbors.add(nw);
          if (n > 0) neighbors.add(n);
          if (ne > 0) neighbors.add(ne);
          if (wst > 0) neighbors.add(wst);

          if (neighbors.isEmpty) {
            labels[y * w + x] = nextLabel;
            parent.add(nextLabel);
            nextLabel++;
          } else {
            int minLabel = neighbors.first;
            for (final nb in neighbors) {
              if (nb < minLabel) minLabel = nb;
            }
            labels[y * w + x] = minLabel;
            for (final nb in neighbors) {
              union(minLabel, nb);
            }
          }
        }
      }
    }

    // 3. Filter candidate bubbles
    final compBounds = <int, List<int>>{};
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final lbl = labels[y * w + x];
        if (lbl > 0) {
          final root = findRoot(lbl);
          final b = compBounds.putIfAbsent(root, () => [x, x, y, y, 0]);
          if (x < b[0]) b[0] = x;
          if (x > b[1]) b[1] = x;
          if (y < b[2]) b[2] = y;
          if (y > b[3]) b[3] = y;
          b[4]++;
        }
      }
    }

    final candidates = <Point2D>[];
    for (final b in compBounds.values) {
      final bw = b[1] - b[0] + 1;
      final bh = b[3] - b[2] + 1;
      final aspect = bw / bh.toDouble();
      if (aspect < 0.65 || aspect > 1.35) continue;

      final r = max(bw, bh) / 2.0;
      if (r < expectedR * 0.4 || r > expectedR * 2.2) continue;

      final cx = b[0] + bw / 2.0;
      final cy = b[2] + bh / 2.0;

      if (cy < h * 0.08) continue;
      final relX = (cx % colWidth) / colWidth;
      if (relX < 0.16) continue;

      candidates.add(Point2D(cx, cy));
    }

    // Deduplicate candidates within Euclidean distance < expectedR * 0.7
    final unique = <Point2D>[];
    final minDist2 = (expectedR * 0.7) * (expectedR * 0.7);
    for (final c in candidates) {
      if (!unique.any((u) => (c.x - u.x) * (c.x - u.x) + (c.y - u.y) * (c.y - u.y) < minDist2)) {
        unique.add(c);
      }
    }

    // If at least 25 candidate bubbles found, use dynamic grid reconstruction
    if (unique.length >= 25) {
      final yCoords = unique.map((p) => p.y).toList()..sort();
      final rowClusters = <List<double>>[];
      final rowThreshold = min(20.0, h / 40.0);
      for (final y in yCoords) {
        if (rowClusters.isEmpty || (y - rowClusters.last.last).abs() > rowThreshold) {
          rowClusters.add([y]);
        } else {
          rowClusters.last.add(y);
        }
      }

      final validRowClusters = rowClusters.where((c) => c.length >= 3).toList();
      List<double> rowYCenters;
      if (validRowClusters.length == 10) {
        rowYCenters = validRowClusters.map((c) => _median(c)).toList();
      } else if (validRowClusters.length > 10) {
        final top10 = List<List<double>>.from(validRowClusters)
          ..sort((a, b) => b.length.compareTo(a.length));
        final top10Sorted = top10.take(10).toList()
          ..sort((a, b) => _median(a).compareTo(_median(b)));
        rowYCenters = top10Sorted.map((c) => _median(c)).toList();
      } else {
        final minY = yCoords.isNotEmpty ? yCoords.first : (0.20 * h);
        final maxY = yCoords.isNotEmpty ? yCoords.last : (0.85 * h);
        rowYCenters = _linspace(minY, maxY, 10);
      }

      final questionRows = <int, DetectedQuestionRow>{};
      final radius = expectedR;
      final innerRadius = radius * 0.75;

      for (int col = 0; col < 3; col++) {
        final xMinBound = col * colWidth + 0.16 * colWidth;
        final xMaxBound = (col + 1) * colWidth;
        final colPts = unique
            .where((p) => p.x >= xMinBound && p.x <= xMaxBound)
            .map((p) => p.x)
            .toList()
          ..sort();

        final optClusters = <List<double>>[];
        final optThreshold = min(20.0, colWidth / 16.0);
        for (final x in colPts) {
          if (optClusters.isEmpty || (x - optClusters.last.last).abs() > optThreshold) {
            optClusters.add([x]);
          } else {
            optClusters.last.add(x);
          }
        }

        final validOptClusters = optClusters.where((c) => c.length >= 3).toList();
        List<double> colXCenters;
        if (validOptClusters.length == 4) {
          colXCenters = validOptClusters.map((c) => _median(c)).toList();
        } else if (optClusters.length == 4) {
          colXCenters = optClusters.map((c) => _median(c)).toList();
        } else if (validOptClusters.length > 4) {
          final top4 = List<List<double>>.from(validOptClusters)
            ..sort((a, b) => b.length.compareTo(a.length));
          final top4Sorted = top4.take(4).toList()
            ..sort((a, b) => _median(a).compareTo(_median(b)));
          colXCenters = top4Sorted.map((c) => _median(c)).toList();
        } else {
          final colStart = xMinBound + (colWidth * 0.08);
          final colEnd = xMaxBound - (colWidth * 0.05);
          colXCenters = _linspace(colStart, colEnd, 4);
        }

        for (int r = 0; r < 10; r++) {
          final q = col * 10 + r + 1;
          final cy = rowYCenters[r];
          final bubbles = <String, NormalizedBubble>{};

          for (int optIdx = 0; optIdx < 4; optIdx++) {
            final opt = expectedOptions[optIdx];
            final cx = colXCenters[optIdx];
            bubbles[opt] = NormalizedBubble(
              option: opt,
              normX: cx / w,
              normY: cy / h,
              pixelX: cx,
              pixelY: cy,
              radius: radius,
              innerRadius: innerRadius,
            );
          }

          questionRows[q] = DetectedQuestionRow(
            questionNumber: q,
            columnIndex: col,
            rowIndexInColumn: r,
            anchorY: cy,
            bubbles: bubbles,
          );
        }
      }

      return DetectedLayout(
        totalQuestions: 30,
        columnCount: 3,
        optionsPerQuestion: 4,
        optionLabels: expectedOptions,
        questionRows: questionRows,
        confidence: 0.99,
        layoutType: 'dynamic_reconstructed_grid',
      );
    }

    // Canonical Fallback
    final List<double> rowYNorm;
    final List<List<double>> colXNorm;
    final double radius;

    if (isPortrait) {
      rowYNorm = [0.2625, 0.3232, 0.3839, 0.4447, 0.5054, 0.5661, 0.6268, 0.6875, 0.7483, 0.8090];
      colXNorm = [
        [0.1114, 0.1574, 0.2034, 0.2485],
        [0.4377, 0.4836, 0.5296, 0.5756],
        [0.7648, 0.8108, 0.8568, 0.9027],
      ];
      radius = (h / 1536.0) * 23.0;
    } else {
      rowYNorm = [
        139.0 / 1120.0,
        240.0 / 1120.0,
        341.0 / 1120.0,
        446.0 / 1120.0,
        547.0 / 1120.0,
        656.0 / 1120.0,
        760.0 / 1120.0,
        868.0 / 1120.0,
        972.0 / 1120.0,
        1069.0 / 1120.0,
      ];
      colXNorm = [
        [142.0 / 1536.0, 250.0 / 1536.0, 348.0 / 1536.0, 446.0 / 1536.0],
        [652.0 / 1536.0, 758.0 / 1536.0, 853.0 / 1536.0, 950.0 / 1536.0],
        [1156.0 / 1536.0, 1262.0 / 1536.0, 1360.0 / 1536.0, 1458.0 / 1536.0],
      ];
      radius = (w / 1536.0) * 23.0;
    }

    final innerRadius = radius * 0.75;
    final questionRows = <int, DetectedQuestionRow>{};

    for (int col = 0; col < 3; col++) {
      final startQ = col * 10 + 1;
      for (int r = 0; r < 10; r++) {
        final q = startQ + r;
        final cy = rowYNorm[r] * h;
        final bubbles = <String, NormalizedBubble>{};

        for (int optIdx = 0; optIdx < 4; optIdx++) {
          final opt = expectedOptions[optIdx];
          final cx = colXNorm[col][optIdx] * w;

          bubbles[opt] = NormalizedBubble(
            option: opt,
            normX: cx / w,
            normY: cy / h,
            pixelX: cx,
            pixelY: cy,
            radius: radius,
            innerRadius: innerRadius,
          );
        }

        questionRows[q] = DetectedQuestionRow(
          questionNumber: q,
          columnIndex: col,
          rowIndexInColumn: r,
          anchorY: cy,
          bubbles: bubbles,
        );
      }
    }

    return DetectedLayout(
      totalQuestions: 30,
      columnCount: 3,
      optionsPerQuestion: 4,
      optionLabels: expectedOptions,
      questionRows: questionRows,
      confidence: 0.95,
      layoutType: isPortrait ? 'canonical_portrait_grid' : 'canonical_bengali_grid',
    );
  }

  static double _median(List<double> list) {
    final sorted = List<double>.from(list)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  static List<double> _linspace(double start, double end, int count) {
    if (count <= 1) return [start];
    final step = (end - start) / (count - 1);
    return List.generate(count, (i) => start + i * step);
  }
}


import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/detected_answer.dart';
import '../../models/scan_result.dart';
import '../geometry/homography.dart';
import '../geometry/quadrilateral.dart';
import 'micro_box_detector.dart';
import 'sheet_detector.dart';


class Class910DetectionResult {
  final img.Image croppedImage;
  final Map<int, DetectedAnswer> answers;
  final String? rollNumber;
  final String? setCode;
  final String? registrationNumber;
  final String? subjectCode;
  final Uint8List annotatedImageBytes;
  final String? annotatedImagePath;
  final double confidence;

  const Class910DetectionResult({
    required this.croppedImage,
    required this.answers,
    this.rollNumber,
    this.setCode,
    this.registrationNumber,
    this.subjectCode,
    required this.annotatedImageBytes,
    this.annotatedImagePath,
    required this.confidence,
  });
}

class Class910Detector {
  static const int canonicalSheetWidth = 1200;
  static const int canonicalSheetHeight = 1600;
  static const int canonicalGridWidth = 1200;
  static const int canonicalGridHeight = 936;
  static const int targetWidth = 1200;

  final MicroBoxDetector microBoxDetector;

  const Class910Detector({
    this.microBoxDetector = const MicroBoxDetector(),
  });

  /// Retained for backward-compatibility with unit test assertions on table-cropping.
  img.Image cropOmrGrid(img.Image inputImage) {
    final int h = inputImage.height;
    final int w = inputImage.width;
    final double aspect = h / w;

    if (aspect < 1.0) {
      if (w == targetWidth && (h >= 920 && h <= 950)) {
        return inputImage;
      }
      return img.copyResize(inputImage, width: targetWidth, height: canonicalGridHeight);
    }

    final gray = Uint8List(w * h);
    final hist = Int32List(256);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = inputImage.getPixel(x, y);
        final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        gray[y * w + x] = l;
        hist[l]++;
      }
    }

    final total = w * h;
    double sum = 0;
    for (int t = 0; t < 256; t++) {
      sum += t * hist[t];
    }
    double sumB = 0;
    int wB = 0;
    double varMax = 0;
    int otsuThresh = 128;
    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final int wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final double mB = sumB / wB;
      final double mF = (sum - sumB) / wF;
      final double varBetween = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (varBetween > varMax) {
        varMax = varBetween;
        otsuThresh = t;
      }
    }

    final yTopStart = (0.23 * h).round();
    final yTopEnd = (0.30 * h).round();
    int bestY1 = (0.262 * h).round();
    int maxTopRowDark = 0;
    final xMidStart = (0.10 * w).round();
    final xMidEnd = (0.60 * w).round();

    for (int y = yTopStart; y < yTopEnd; y++) {
      int darkCount = 0;
      for (int x = xMidStart; x < xMidEnd; x++) {
        if (gray[y * w + x] <= otsuThresh) darkCount++;
      }
      if (darkCount > maxTopRowDark) {
        maxTopRowDark = darkCount;
        bestY1 = y;
      }
    }

    final yBotStart = (0.73 * h).round();
    final yBotEnd = (0.80 * h).round();
    int bestY2 = (0.760 * h).round();
    int maxBotRowDark = 0;

    for (int y = yBotStart; y < yBotEnd; y++) {
      int darkCount = 0;
      for (int x = xMidStart; x < xMidEnd; x++) {
        if (gray[y * w + x] <= otsuThresh) darkCount++;
      }
      if (darkCount > maxBotRowDark) {
        maxBotRowDark = darkCount;
        bestY2 = y;
      }
    }

    final tableH = bestY2 - bestY1;

    int bestX1 = (0.060 * w).round();
    final xLeftStart = (0.03 * w).round();
    final xLeftEnd = (0.10 * w).round();
    for (int x = xLeftStart; x < xLeftEnd; x++) {
      int colDark = 0;
      for (int y = bestY1; y < bestY2; y += 2) {
        if (gray[y * w + x] <= otsuThresh) colDark++;
      }
      if (colDark >= 0.30 * (tableH / 2)) {
        bestX1 = x;
        if (x + 1 < w) {
          int nextDark = 0;
          for (int y = bestY1; y < bestY2; y += 2) {
            if (gray[y * w + (x + 1)] <= otsuThresh) nextDark++;
          }
          if (nextDark > colDark) bestX1 = x + 1;
        }
        break;
      }
    }

    final xRightStart = (0.86 * w).round();
    final xRightEnd = (0.92 * w).round();
    int bestX2 = (0.880 * w).round();
    int maxRightColDark = 0;
    for (int x = xRightStart; x < xRightEnd; x++) {
      int colDark = 0;
      for (int y = bestY1; y < bestY2; y += 2) {
        if (gray[y * w + x] <= otsuThresh) colDark++;
      }
      if (colDark > maxRightColDark) {
        maxRightColDark = colDark;
        bestX2 = x;
      }
    }

    final cropW = max(10, bestX2 - bestX1);
    final cropH = max(10, bestY2 - bestY1);
    final cropped = img.copyCrop(inputImage, x: bestX1, y: bestY1, width: cropW, height: cropH);
    return img.copyResize(cropped, width: targetWidth, height: canonicalGridHeight);
  }

  Future<ScanResult> processSheet(
    String imagePath,
    Uint8List rawBytes, {
    Quadrilateral? detectedQuad,
  }) async {
    var rawImage = img.decodeImage(rawBytes);
    if (rawImage == null) {
      return const ScanResult(
        status: ScanStatus.failed,
        message: 'Could not decode image for Class 9-10 OMR.',
        detectedAnswers: {},
        sheetDetectionConfidence: 0.0,
        classMode: 'class_9_10',
      );
    }
    rawImage = img.bakeOrientation(rawImage);

    final double rawAspect = rawImage.height / rawImage.width.toDouble();
    final bool isPreCroppedGrid = rawAspect < 1.0;

    if (isPreCroppedGrid) {
      return _processCroppedGrid(rawImage, imagePath, detectedQuad: detectedQuad);
    } else {
      return _processFullSheet(rawImage, imagePath, detectedQuad: detectedQuad);
    }
  }

  Future<ScanResult> _processCroppedGrid(
    img.Image inputImage,
    String imagePath, {
    Quadrilateral? detectedQuad,
  }) async {
    final cropped = (inputImage.width == canonicalGridWidth && inputImage.height == canonicalGridHeight)
        ? inputImage
        : ((inputImage.width == 1200)
            ? inputImage
            : img.copyResize(inputImage, width: 1200, height: (1200 * (inputImage.height / inputImage.width)).round()));
    final W = cropped.width;
    final H = cropped.height;

    final gray = Uint8List(W * H);
    final hist = Int32List(256);
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final p = cropped.getPixel(x, y);
        final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        gray[y * W + x] = l;
        hist[l]++;
      }
    }
    final total = W * H;
    double sum = 0;
    for (int t = 0; t < 256; t++) {
      sum += t * hist[t];
    }
    double sumB = 0;
    int wB = 0;
    double varMax = 0;
    int otsuThresh = 128;
    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final int wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final double mB = sumB / wB;
      final double mF = (sum - sumB) / wF;
      final double varBetween = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (varBetween > varMax) {
        varMax = varBetween;
        otsuThresh = t;
      }
    }

    final int topCheckY1 = (0.02 * H).round();
    final int topCheckY2 = (0.05 * H).round();
    final int topCheckX1 = (0.03 * W).round();
    final int topCheckX2 = (0.08 * W).round();
    double topCheckLumSum = 0;
    int topCheckCount = 0;
    for (int y = topCheckY1; y < topCheckY2; y++) {
      for (int x = topCheckX1; x < topCheckX2; x++) {
        topCheckLumSum += gray[y * W + x];
        topCheckCount++;
      }
    }
    final double topMeanLum = topCheckCount > 0 ? (topCheckLumSum / topCheckCount) : 255.0;
    final bool hasHeader = topMeanLum > 175.0;

    final List<double> q1ColsXNorm = hasHeader
        ? const [0.0608, 0.1058, 0.1508, 0.1958]
        : const [0.0323, 0.0796, 0.1269, 0.1742];
    final List<double> q2ColsXNorm = hasHeader
        ? const [0.3108, 0.3558, 0.4008, 0.4458]
        : const [0.2882, 0.3355, 0.3828, 0.4301];
    final List<double> rollColsXNorm = hasHeader
        ? const [0.5067, 0.5392, 0.5717, 0.6033, 0.6358, 0.6683]
        : const [0.4903, 0.5237, 0.5570, 0.5903, 0.6237, 0.6570];
    final double setColXNorm = hasHeader ? 0.7600 : 0.7548;
    final List<double> regColsXNorm = hasHeader
        ? const [0.5079, 0.5404, 0.5729, 0.6054, 0.6379, 0.6704, 0.7029, 0.7354, 0.7679, 0.8004]
        : List.generate(10, (i) => 0.5032 + i * 0.03345);
    final List<double> subColsXNorm = hasHeader
        ? const [0.8517, 0.8900, 0.9283]
        : const [0.8731, 0.9075, 0.9548];

    final List<double> qRowsYNorm = hasHeader
        ? List.generate(15, (i) => (108.0 + i * (907.0 - 108.0) / 14.0) / 936.0)
        : List.generate(15, (i) => 0.0302 + i * (0.9505 - 0.0302) / 14.0);
    final List<double> rollRowsYNorm = hasHeader
        ? List.generate(10, (i) => (104.0 + i * (446.0 - 104.0) / 9.0) / 936.0)
        : List.generate(10, (i) => 0.0220 + i * (0.4341 - 0.0220) / 9.0);
    final List<double> setRowsYNorm = hasHeader
        ? List.generate(4, (i) => (120.0 + i * (276.0 - 120.0) / 3.0) / 936.0)
        : List.generate(4, (i) => 0.0357 + i * (0.2500 - 0.0357) / 3.0);
    final List<double> regRowsYNorm = hasHeader
        ? List.generate(10, (i) => (590.0 + i * (910.0 - 590.0) / 9.0) / 936.0)
        : List.generate(10, (i) => 0.5824 + i * (0.9698 - 0.5824) / 9.0);

    (double fillRatio, double meanLum, double snappedX, double snappedY) evalBubbleMetrics(
      double cx,
      double cy, {
      int radius = 11,
    }) {
      double bestX = cx;
      double bestY = cy;

      final int searchR = max(3, (radius * 0.35).round());
      double minLum = 255.0;
      for (int dy = -searchR; dy <= searchR; dy++) {
        for (int dx = -searchR; dx <= searchR; dx++) {
          final px = (cx + dx).round();
          final py = (cy + dy).round();
          if (px >= 0 && px < W && py >= 0 && py < H) {
            final l = gray[py * W + px];
            if (l < minLum) {
              minLum = l.toDouble();
              bestX = px.toDouble();
              bestY = py.toDouble();
            }
          }
        }
      }

      final sampleR = max(4, (radius * 0.70).round());
      final r2 = sampleR * sampleR;
      int dark = 0;
      int totalPx = 0;
      double sumLum = 0.0;
      final ix = bestX.round();
      final iy = bestY.round();

      for (int dy = -sampleR; dy <= sampleR; dy++) {
        for (int dx = -sampleR; dx <= sampleR; dx++) {
          if (dx * dx + dy * dy <= r2) {
            final px = ix + dx;
            final py = iy + dy;
            if (px >= 0 && px < W && py >= 0 && py < H) {
              totalPx++;
              final l = gray[py * W + px];
              sumLum += l;
              if (l <= otsuThresh) {
                dark++;
              }
            }
          }
        }
      }

      final fill = totalPx > 0 ? (dark / totalPx) : 0.0;
      final mean = totalPx > 0 ? (sumLum / totalPx) : 255.0;
      return (fill, mean, bestX, bestY);
    }

    final annotated = img.Image.from(cropped);
    final yellowBox = img.ColorRgb8(255, 220, 0);
    final circleGreen = img.ColorRgb8(0, 220, 0);
    final dotRed = img.ColorRgb8(220, 30, 30);
    final filledHighlight = img.ColorRgb8(0, 230, 50);

    void drawBox(double yminP, double xminP, double ymaxP, double xmaxP) {
      final x1 = (xminP * W).round();
      final y1 = (yminP * H).round();
      final x2 = (xmaxP * W).round();
      final y2 = (ymaxP * H).round();
      img.drawRect(annotated, x1: x1, y1: y1, x2: x2, y2: y2, color: yellowBox, thickness: 2);
    }

    void drawBubbleMark(double cx, double cy, {bool isFilled = false, int r = 11}) {
      final ix = cx.round();
      final iy = cy.round();
      img.drawCircle(annotated, x: ix, y: iy, radius: r, color: isFilled ? filledHighlight : circleGreen);
      if (isFilled) {
        img.drawCircle(annotated, x: ix, y: iy, radius: r - 1, color: filledHighlight);
        img.drawCircle(annotated, x: ix, y: iy, radius: r - 2, color: filledHighlight);
      }
      img.drawCircle(annotated, x: ix, y: iy, radius: 2, color: dotRed);
    }

    drawBox(
      max(0.005, qRowsYNorm.first - 0.020),
      max(0.005, q1ColsXNorm.first - 0.015),
      min(0.995, qRowsYNorm.last + 0.020),
      min(0.995, q1ColsXNorm.last + 0.015),
    );
    drawBox(
      max(0.005, qRowsYNorm.first - 0.020),
      max(0.005, q2ColsXNorm.first - 0.015),
      min(0.995, qRowsYNorm.last + 0.020),
      min(0.995, q2ColsXNorm.last + 0.015),
    );
    drawBox(
      max(0.005, rollRowsYNorm.first - 0.018),
      max(0.005, rollColsXNorm.first - 0.015),
      min(0.995, rollRowsYNorm.last + 0.018),
      min(0.995, rollColsXNorm.last + 0.015),
    );
    drawBox(
      max(0.005, setRowsYNorm.first - 0.020),
      max(0.005, setColXNorm - 0.025),
      min(0.995, setRowsYNorm.last + 0.020),
      min(0.995, setColXNorm + 0.025),
    );
    drawBox(
      max(0.005, regRowsYNorm.first - 0.018),
      max(0.005, regColsXNorm.first - 0.015),
      min(0.995, regRowsYNorm.last + 0.018),
      min(0.995, regColsXNorm.last + 0.015),
    );
    drawBox(
      max(0.005, regRowsYNorm.first - 0.018),
      max(0.005, subColsXNorm.first - 0.015),
      min(0.995, regRowsYNorm.last + 0.018),
      min(0.995, subColsXNorm.last + 0.015),
    );

    final bubbleRadius = max(7, (11.0 * (W / 1200.0)).round());

    final setX = setColXNorm * W;
    final setYList = setRowsYNorm.map((y) => y * H).toList();
    final setBanglaLabels = ['ক', 'খ', 'গ', 'ঘ'];
    final setMetrics = setYList.map((y) => evalBubbleMetrics(setX, y, radius: bubbleRadius)).toList();

    int bestSetIdx = 0;
    int secondSetIdx = 1;
    double maxSetScore = setMetrics[0].$1;
    double secondSetScore = 0.0;
    for (int i = 1; i < setMetrics.length; i++) {
      if (setMetrics[i].$1 > maxSetScore) {
        secondSetScore = maxSetScore;
        secondSetIdx = bestSetIdx;
        maxSetScore = setMetrics[i].$1;
        bestSetIdx = i;
      } else if (setMetrics[i].$1 > secondSetScore) {
        secondSetScore = setMetrics[i].$1;
        secondSetIdx = i;
      }
    }

    final topSetMean = setMetrics[bestSetIdx].$2;
    final secondSetMean = setMetrics[secondSetIdx].$2;
    final bool isSetFilled = (topSetMean < 162.0 && (secondSetMean - topSetMean) >= 10.0) ||
        (topSetMean < 160.0 && maxSetScore >= 0.40 && (maxSetScore - secondSetScore) >= 0.12);
    final String? detectedSetBangla = isSetFilled ? setBanglaLabels[bestSetIdx] : null;

    for (int i = 0; i < 4; i++) {
      drawBubbleMark(setMetrics[i].$3, setMetrics[i].$4, isFilled: (isSetFilled && i == bestSetIdx), r: bubbleRadius);
    }

    final rollColsX = rollColsXNorm.map((x) => x * W).toList();
    final rollRowsY = rollRowsYNorm.map((y) => y * H).toList();

    final rollDigits = <String>[];
    for (int col = 0; col < 6; col++) {
      final cx = rollColsX[col];
      int bestDigit = 0;
      double topScore = 0.0;
      double secondScore = 0.0;
      double bestMean = 255.0;
      double secondMean = 255.0;
      final List<(double, double, double, double)> colMetrics = [];

      for (int row = 0; row < 10; row++) {
        final cy = rollRowsY[row];
        final m = evalBubbleMetrics(cx, cy, radius: bubbleRadius);
        colMetrics.add(m);
        if (m.$1 > topScore) {
          secondScore = topScore;
          secondMean = bestMean;
          topScore = m.$1;
          bestMean = m.$2;
          bestDigit = row;
        } else if (m.$1 > secondScore) {
          secondScore = m.$1;
          secondMean = m.$2;
        }
      }

      final isFilled = (bestMean < 162.0 && (secondMean - bestMean) >= 10.0) ||
          (bestMean < 160.0 && topScore >= 0.40 && (topScore - secondScore) >= 0.12);
      rollDigits.add(isFilled ? bestDigit.toString() : '');

      for (int row = 0; row < 10; row++) {
        final m = colMetrics[row];
        drawBubbleMark(m.$3, m.$4, isFilled: isFilled && row == bestDigit, r: bubbleRadius);
      }
    }
    final detectedRoll = rollDigits.every((d) => d.isEmpty) ? null : rollDigits.join();

    final subColsX = subColsXNorm.map((x) => x * W).toList();
    final subRowsY = regRowsYNorm.map((y) => y * H).toList();

    final subDigits = <String>[];
    final s1 = evalBubbleMetrics(subColsX[0], subRowsY[1], radius: bubbleRadius);
    final s2 = evalBubbleMetrics(subColsX[0], subRowsY[2], radius: bubbleRadius);
    final bool s1Filled = (s1.$2 < 162.0 && (s2.$2 - s1.$2) >= 10.0) ||
        (s1.$2 < 160.0 && s1.$1 >= 0.40 && (s1.$1 - s2.$1) >= 0.12);
    final bool s2Filled = (s2.$2 < 162.0 && (s1.$2 - s2.$2) >= 10.0) ||
        (s2.$2 < 160.0 && s2.$1 >= 0.40 && (s2.$1 - s1.$1) >= 0.12);

    if (s1Filled) {
      subDigits.add('1');
    } else if (s2Filled) {
      subDigits.add('2');
    } else {
      subDigits.add('');
    }
    drawBubbleMark(s1.$3, s1.$4, isFilled: s1Filled, r: bubbleRadius);
    drawBubbleMark(s2.$3, s2.$4, isFilled: s2Filled, r: bubbleRadius);

    for (int col = 1; col < 3; col++) {
      final cx = subColsX[col];
      int bestDigit = 0;
      double topScore = 0.0;
      double secondScore = 0.0;
      double bestMean = 255.0;
      double secondMean = 255.0;
      final List<(double, double, double, double)> colMetrics = [];

      for (int row = 0; row < 10; row++) {
        final cy = subRowsY[row];
        final m = evalBubbleMetrics(cx, cy, radius: bubbleRadius);
        colMetrics.add(m);
        if (m.$1 > topScore) {
          secondScore = topScore;
          secondMean = bestMean;
          topScore = m.$1;
          bestMean = m.$2;
          bestDigit = row;
        } else if (m.$1 > secondScore) {
          secondScore = m.$1;
          secondMean = m.$2;
        }
      }
      final isFilled = (bestMean < 162.0 && (secondMean - bestMean) >= 10.0) ||
          (bestMean < 160.0 && topScore >= 0.40 && (topScore - secondScore) >= 0.12);
      subDigits.add(isFilled ? bestDigit.toString() : '');
      for (int row = 0; row < 10; row++) {
        final m = colMetrics[row];
        drawBubbleMark(m.$3, m.$4, isFilled: isFilled && row == bestDigit, r: bubbleRadius);
      }
    }
    final detectedSubject = subDigits.every((d) => d.isEmpty) ? null : subDigits.join();

    final regColsX = regColsXNorm.map((x) => x * W).toList();
    final regRowsY = regRowsYNorm.map((y) => y * H).toList();

    final regDigits = <String>[];
    for (int col = 0; col < 10; col++) {
      final cx = regColsX[col];
      int bestDigit = 0;
      double topScore = 0.0;
      double secondScore = 0.0;
      double bestMean = 255.0;
      double secondMean = 255.0;
      final List<(double, double, double, double)> colMetrics = [];

      for (int row = 0; row < 10; row++) {
        final cy = regRowsY[row];
        final m = evalBubbleMetrics(cx, cy, radius: bubbleRadius);
        colMetrics.add(m);
        if (m.$1 > topScore) {
          secondScore = topScore;
          secondMean = bestMean;
          topScore = m.$1;
          bestMean = m.$2;
          bestDigit = row;
        } else if (m.$1 > secondScore) {
          secondScore = m.$1;
          secondMean = m.$2;
        }
      }
      final isFilled = (bestMean < 162.0 && (secondMean - bestMean) >= 10.0) ||
          (bestMean < 160.0 && topScore >= 0.40 && (topScore - secondScore) >= 0.12);
      regDigits.add(isFilled ? bestDigit.toString() : '');
      for (int row = 0; row < 10; row++) {
        final m = colMetrics[row];
        drawBubbleMark(m.$3, m.$4, isFilled: isFilled && row == bestDigit, r: bubbleRadius);
      }
    }
    final detectedReg = regDigits.every((d) => d.isEmpty) ? null : regDigits.join();

    final detectedAnswers = <int, DetectedAnswer>{};
    const options = ['A', 'B', 'C', 'D'];

    final qRowsY = qRowsYNorm.map((y) => y * H).toList();
    final q1ColsX = q1ColsXNorm.map((x) => x * W).toList();
    final q2ColsX = q2ColsXNorm.map((x) => x * W).toList();

    for (int qIdx = 0; qIdx < 15; qIdx++) {
      final qNum = qIdx + 1;
      final cy = qRowsY[qIdx];
      final Map<String, double> scores = {};
      final Map<String, double> means = {};
      final List<(double, double, double, double)> optMetrics = [];

      for (int opt = 0; opt < 4; opt++) {
        final cx = q1ColsX[opt];
        final m = evalBubbleMetrics(cx, cy, radius: bubbleRadius);
        optMetrics.add(m);
        scores[options[opt]] = double.parse(m.$1.clamp(0.0, 1.0).toStringAsFixed(3));
        means[options[opt]] = m.$2;
      }

      final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted[0];
      final second = sorted[1];
      final topMean = means[top.key] ?? 255.0;
      final secondMean = means[second.key] ?? 255.0;

      final isFilled = (topMean < 162.0 && (secondMean - topMean) >= 10.0) ||
          (topMean < 160.0 && top.value >= 0.40 && (top.value - second.value) >= 0.12);
      final isMultiple = topMean < 160.0 &&
          secondMean < 160.0 &&
          top.value >= 0.38 &&
          second.value >= 0.38 &&
          (topMean - secondMean).abs() < 8.0;

      for (int opt = 0; opt < 4; opt++) {
        final m = optMetrics[opt];
        final filled = (isFilled && top.key == options[opt]) ||
            (isMultiple && (top.key == options[opt] || second.key == options[opt]));
        drawBubbleMark(m.$3, m.$4, isFilled: filled, r: bubbleRadius);
      }

      if (isFilled) {
        detectedAnswers[qNum] = DetectedAnswer(
          questionNumber: qNum,
          selectedOptions: [top.key],
          classification: AnswerClassification.single,
          confidence: min(0.99, max(0.85, top.value)),
          bubbleScores: scores,
          primaryAnswer: top.key,
        );
      } else if (isMultiple) {
        detectedAnswers[qNum] = DetectedAnswer(
          questionNumber: qNum,
          selectedOptions: [top.key, second.key],
          classification: AnswerClassification.multiple,
          confidence: 0.85,
          bubbleScores: scores,
        );
      } else {
        detectedAnswers[qNum] = DetectedAnswer(
          questionNumber: qNum,
          selectedOptions: const [],
          classification: AnswerClassification.blank,
          confidence: 0.95,
          bubbleScores: scores,
        );
      }
    }

    for (int qIdx = 0; qIdx < 15; qIdx++) {
      final qNum = qIdx + 16;
      final cy = qRowsY[qIdx];
      final Map<String, double> scores = {};
      final Map<String, double> means = {};
      final List<(double, double, double, double)> optMetrics = [];

      for (int opt = 0; opt < 4; opt++) {
        final cx = q2ColsX[opt];
        final m = evalBubbleMetrics(cx, cy, radius: bubbleRadius);
        optMetrics.add(m);
        scores[options[opt]] = double.parse(m.$1.clamp(0.0, 1.0).toStringAsFixed(3));
        means[options[opt]] = m.$2;
      }

      final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted[0];
      final second = sorted[1];
      final topMean = means[top.key] ?? 255.0;
      final secondMean = means[second.key] ?? 255.0;

      final isFilled = (topMean < 162.0 && (secondMean - topMean) >= 10.0) ||
          (topMean < 160.0 && top.value >= 0.40 && (top.value - second.value) >= 0.12);
      final isMultiple = topMean < 160.0 &&
          secondMean < 160.0 &&
          top.value >= 0.38 &&
          second.value >= 0.38 &&
          (topMean - secondMean).abs() < 8.0;

      for (int opt = 0; opt < 4; opt++) {
        final m = optMetrics[opt];
        final filled = (isFilled && top.key == options[opt]) ||
            (isMultiple && (top.key == options[opt] || second.key == options[opt]));
        drawBubbleMark(m.$3, m.$4, isFilled: filled, r: bubbleRadius);
      }
      if (isFilled) {
        detectedAnswers[qNum] = DetectedAnswer(
          questionNumber: qNum,
          selectedOptions: [top.key],
          classification: AnswerClassification.single,
          confidence: min(0.99, max(0.85, top.value)),
          bubbleScores: scores,
          primaryAnswer: top.key,
        );
      } else if (isMultiple) {
        detectedAnswers[qNum] = DetectedAnswer(
          questionNumber: qNum,
          selectedOptions: [top.key, second.key],
          classification: AnswerClassification.multiple,
          confidence: 0.85,
          bubbleScores: scores,
        );
      } else {
        detectedAnswers[qNum] = DetectedAnswer(
          questionNumber: qNum,
          selectedOptions: const [],
          classification: AnswerClassification.blank,
          confidence: 0.95,
          bubbleScores: scores,
        );
      }
    }

    final annotatedBytes = Uint8List.fromList(img.encodeJpg(annotated, quality: 90));
    final rectifiedBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 90));

    String? annotatedPath;
    try {
      final tempDir = Directory('${Directory.systemTemp.path}/omr_annotated');
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final filename = 'class9_10_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(annotatedBytes);
      annotatedPath = file.path;
    } catch (_) {}

    final int uncertainCount = detectedAnswers.values.where((a) => a.classification == AnswerClassification.uncertain).length;
    final int multipleCount = detectedAnswers.values.where((a) => a.classification == AnswerClassification.multiple).length;

    double overallConfidence = 0.98;
    String alignmentQuality = 'Good';

    if (uncertainCount > 3 || multipleCount > 4) {
      overallConfidence = 0.68;
      alignmentQuality = 'Review Needed';
    } else if (uncertainCount > 0 || multipleCount > 0) {
      overallConfidence = 0.84;
      alignmentQuality = 'Fair';
    } else {
      overallConfidence = 0.98;
      alignmentQuality = 'Good';
    }

    return ScanResult(
      status: ScanStatus.success,
      message: 'Class 9-10 OMR sheet scanned successfully.',
      detectedAnswers: detectedAnswers,
      sheetDetectionConfidence: overallConfidence,
      alignmentQuality: alignmentQuality,
      imagePath: imagePath,
      annotatedImagePath: annotatedPath,
      annotatedImageBytes: annotatedBytes,
      rectifiedImageBytes: rectifiedBytes,
      rollNumber: detectedRoll,
      setCode: detectedSetBangla,
      registrationNumber: detectedReg,
      subjectCode: detectedSubject,
      classMode: 'class_9_10',
    );
  }

  /// Auto-detects the horizontal red divider line separating the top header/handwritten boxes from the bubble grid.
  /// Uses weighted centroid of the top-3 scoring rows for robustness against outlier lines.
  double _findInternalHDivider(img.Image warped, double minRatio, double maxRatio, double defaultRatio) {
    final w = warped.width;
    final h = warped.height;
    final yStart = (minRatio * h).round().clamp(2, h - 3);
    final yEnd = (maxRatio * h).round().clamp(2, h - 3);
    final xStart = (0.06 * w).round();
    final xEnd = (0.94 * w).round();

    // Collect all row scores
    final scores = <(int, int)>[]; // (y, score)
    for (int y = yStart; y <= yEnd; y++) {
      int score = 0;
      for (int x = xStart; x <= xEnd; x += 2) {
        final p = warped.getPixel(x, y);
        final diff = p.r.toInt() - ((p.g.toInt() * 3 + p.b.toInt()) >> 2);
        if (diff > 8) score += diff;
      }
      scores.add((y, score));
    }

    scores.sort((a, b) => b.$2.compareTo(a.$2));

    // Weighted centroid of top-3 candidates
    final topN = scores.take(3).toList();
    final totalScore = topN.fold<int>(0, (s, e) => s + e.$2);
    if (totalScore < (xEnd - xStart) * 2) {
      return defaultRatio * h;
    }

    double weightedY = 0;
    for (final entry in topN) {
      weightedY += entry.$1 * entry.$2;
    }
    return weightedY / totalScore;
  }

  Future<ScanResult> _processFullSheet(
    img.Image rawImage,
    String imagePath, {
    Quadrilateral? detectedQuad,
  }) async {
    // Stage 1: Safe White-Paper Page Rectification
    img.Image sheetCanvas;
    final totalRawArea = (rawImage.width * rawImage.height).toDouble();

    if (detectedQuad != null &&
        detectedQuad.isValid() &&
        (detectedQuad.area / totalRawArea) >= 0.45) {
      sheetCanvas = HomographyMatrix.warpPerspective(
        rawImage,
        detectedQuad,
        canonicalSheetWidth,
        canonicalSheetHeight,
      );
    } else {
      final sheetRes = const SheetDetector().detectSheet(rawImage);
      if (!sheetRes.isCropped && sheetRes.isReliable) {
        sheetCanvas = HomographyMatrix.warpPerspective(
          rawImage,
          sheetRes.quad,
          canonicalSheetWidth,
          canonicalSheetHeight,
        );
      } else {
        sheetCanvas = img.copyResize(
          rawImage,
          width: canonicalSheetWidth,
          height: canonicalSheetHeight,
        );
      }
    }

    // Stage 2, 3, 4: Red/Magenta Isolation, Landmark-Locked 6-Box Detection & Micro-Homography
    final boxResult = microBoxDetector.detectBoxes(sheetCanvas);
    final boxes = boxResult.allBoxes;

    final annotated = img.Image.from(sheetCanvas);
    final yellowBox = img.ColorRgb8(255, 220, 0);
    final circleGreen = img.ColorRgb8(0, 220, 0);
    final dotRed = img.ColorRgb8(220, 30, 30);
    final filledHighlight = img.ColorRgb8(0, 230, 50);

    void drawMicroBoxQuad(Quadrilateral q) {
      final pts = q.points;
      for (int i = 0; i < 4; i++) {
        final p1 = pts[i];
        final p2 = pts[(i + 1) % 4];
        img.drawLine(
          annotated,
          x1: p1.x.round(),
          y1: p1.y.round(),
          x2: p2.x.round(),
          y2: p2.y.round(),
          color: yellowBox,
          thickness: 3,
        );
      }
    }

    for (final box in boxes) {
      drawMicroBoxQuad(box.sheetQuad);
    }

    void drawBubbleMark(double cx, double cy, {bool isFilled = false, int r = 11}) {
      final ix = cx.round();
      final iy = cy.round();
      img.drawCircle(annotated, x: ix, y: iy, radius: r, color: isFilled ? filledHighlight : circleGreen);
      if (isFilled) {
        img.drawCircle(annotated, x: ix, y: iy, radius: r - 1, color: filledHighlight);
        img.drawCircle(annotated, x: ix, y: iy, radius: r - 2, color: filledHighlight);
      }
      img.drawCircle(annotated, x: ix, y: iy, radius: 2, color: dotRed);
    }

    // Stage 5 Helper: Evaluate bubble on Red Channel with center-of-mass ink snapping & local paper contrast
    (double darknessScore, double meanRed, double sheetX, double sheetY) evalMicroBubble(
      MicroBox box,
      double u,
      double v, {
      int radius = 16,
      int snapU = 18,
      int snapV = 22,
    }) {
      final bw = box.warpedImage.width;
      final bh = box.warpedImage.height;

      // 1. Estimate local paper background brightness on Red channel around the bubble ring
      double bgSum = 0;
      int bgCount = 0;
      final outerR = radius + 6;
      for (int dv = -outerR; dv <= outerR; dv += 3) {
        for (int du = -outerR; du <= outerR; du += 3) {
          final dist2 = du * du + dv * dv;
          if (dist2 >= radius * radius && dist2 <= outerR * outerR) {
            final pu = (u + du).round();
            final pv = (v + dv).round();
            if (pu >= 0 && pu < bw && pv >= 0 && pv < bh) {
              bgSum += box.warpedImage.getPixel(pu, pv).r.toInt();
              bgCount++;
            }
          }
        }
      }
      final double localBgRed = bgCount > 0 ? max(180.0, bgSum / bgCount) : 210.0;

      // 2. Snap towards dark ink centroid within search window
      double sumWeightedU = 0;
      double sumWeightedV = 0;
      double sumWeight = 0;
      for (int dv = -snapV; dv <= snapV; dv += 2) {
        for (int du = -snapU; du <= snapU; du += 2) {
          final pu = (u + du).round();
          final pv = (v + dv).round();
          if (pu >= 0 && pu < bw && pv >= 0 && pv < bh) {
            final rVal = box.warpedImage.getPixel(pu, pv).r.toInt();
            final drop = max(0.0, localBgRed - rVal - 22.0);
            if (drop > 0) {
              sumWeightedU += pu * drop;
              sumWeightedV += pv * drop;
              sumWeight += drop;
            }
          }
        }
      }

      final double bestU = sumWeight > 20.0 ? (sumWeightedU / sumWeight) : u;
      final double bestV = sumWeight > 20.0 ? (sumWeightedV / sumWeight) : v;

      // 3. Measure core darkness relative to local paper background
      final coreR = max(7, (radius * 0.72).round());
      final r2 = coreR * coreR;
      int darkPixels = 0;
      int totalPixels = 0;
      double sumRed = 0.0;
      final darkThresh = max(140.0, localBgRed * 0.76);

      for (int dv = -coreR; dv <= coreR; dv++) {
        for (int du = -coreR; du <= coreR; du++) {
          if (du * du + dv * dv <= r2) {
            final pu = (bestU + du).round();
            final pv = (bestV + dv).round();
            if (pu >= 0 && pu < bw && pv >= 0 && pv < bh) {
              final rVal = box.warpedImage.getPixel(pu, pv).r.toInt();
              sumRed += rVal;
              if (rVal < darkThresh) darkPixels++;
              totalPixels++;
            }
          }
        }
      }

      final fillRatio = totalPixels > 0 ? (darkPixels / totalPixels.toDouble()) : 0.0;
      final meanRed = totalPixels > 0 ? (sumRed / totalPixels.toDouble()) : 255.0;
      final contrastDrop = max(0.0, (localBgRed - meanRed) / max(1.0, localBgRed));
      final darknessScore = (fillRatio * 0.65 + contrastDrop * 0.35).clamp(0.0, 1.0);

      final sheetPt = box.projectToSheet(bestU, bestV);
      return (darknessScore, meanRed, sheetPt.x, sheetPt.y);
    }

    // --- A. Evaluate Set Code (boxResult.set: 150x500) ---
    final setLetters = ['ক', 'খ', 'গ', 'ঘ'];
    final setTopY = _findInternalHDivider(boxResult.set.warpedImage, 0.20, 0.45, 0.310);
    final setGridH = (boxResult.set.targetHeight - 6.0) - setTopY;
    final setRowStep = setGridH / 4.0;

    // Full-width sweep (u=15..135, step=8) to find the bubble regardless of
    // horizontal positioning errors from imperfect uSetL/uSetR detection.
    final setMetrics = List.generate(4, (r) {
      final v = setTopY + (r + 0.5) * setRowStep;
      (double, double, double, double) bestM = (0.0, 255.0, 0.0, v);
      for (double u = 15.0; u <= 135.0; u += 8.0) {
        final m = evalMicroBubble(boxResult.set, u, v, radius: 14);
        if (m.$1 > bestM.$1) bestM = m;
      }
      return bestM;
    });

    final sortedSet = List.generate(4, (i) => i)..sort((a, b) => setMetrics[b].$1.compareTo(setMetrics[a].$1));
    final topSet = sortedSet[0];
    final secondSet = sortedSet[1];
    // Criterion 1: darkness score — lowered threshold for real-world scans
    final bool setFilledByScore = setMetrics[topSet].$1 >= 0.12 && (setMetrics[topSet].$1 - setMetrics[secondSet].$1) >= 0.04;
    // Criterion 2: meanRed comparison — filled bubble has lower red channel than blank bubbles
    final bool setFilledByMean = setMetrics[topSet].$2 < 180.0 &&
        (setMetrics[secondSet].$2 - setMetrics[topSet].$2) >= 12.0;
    final bool setFilled = setFilledByScore || setFilledByMean;
    final String? detectedSetBangla = setFilled ? setLetters[topSet] : null;

    for (int i = 0; i < 4; i++) {
      drawBubbleMark(setMetrics[i].$3, setMetrics[i].$4, isFilled: setFilled && i == topSet, r: 12);
    }

    // --- B. Evaluate Roll Number (boxResult.roll: 600x1000) ---
    final rollTopY = _findInternalHDivider(boxResult.roll.warpedImage, 0.16, 0.26, 0.212);
    final rollGridH = (boxResult.roll.targetHeight - 6.0) - rollTopY;
    final rollRowStep = rollGridH / 10.0;
    final rollColStep = boxResult.roll.targetWidth / 6.0;

    final rollDigits = <String>[];
    for (int c = 0; c < 6; c++) {
      final u = (c + 0.5) * rollColStep;
      final colM = List.generate(
        10,
        (r) => evalMicroBubble(boxResult.roll, u, rollTopY + (r + 0.5) * rollRowStep, radius: 15),
      );
      final sorted = List.generate(10, (i) => i)..sort((a, b) => colM[b].$1.compareTo(colM[a].$1));
      final top = sorted[0];
      final second = sorted[1];
      final isFilled = colM[top].$1 >= 0.24 && (colM[top].$1 - colM[second].$1) >= 0.08;
      rollDigits.add(isFilled ? top.toString() : '');
      for (int r = 0; r < 10; r++) {
        drawBubbleMark(colM[r].$3, colM[r].$4, isFilled: isFilled && r == top, r: 10);
      }
    }
    final detectedRoll = rollDigits.every((d) => d.isEmpty) ? null : rollDigits.join();

    // --- C. Evaluate Registration Number (boxResult.reg: 1000x1000) ---
    final regTopY = _findInternalHDivider(boxResult.reg.warpedImage, 0.16, 0.26, 0.212);
    final regGridH = (boxResult.reg.targetHeight - 6.0) - regTopY;
    final regRowStep = regGridH / 10.0;
    final regColStep = boxResult.reg.targetWidth / 10.0;

    final regDigits = <String>[];
    for (int c = 0; c < 10; c++) {
      final u = (c + 0.5) * regColStep;
      final colM = List.generate(
        10,
        (r) => evalMicroBubble(boxResult.reg, u, regTopY + (r + 0.5) * regRowStep, radius: 15),
      );
      final sorted = List.generate(10, (i) => i)..sort((a, b) => colM[b].$1.compareTo(colM[a].$1));
      final top = sorted[0];
      final second = sorted[1];
      final isFilled = colM[top].$1 >= 0.24 && (colM[top].$1 - colM[second].$1) >= 0.08;
      regDigits.add(isFilled ? top.toString() : '');
      for (int r = 0; r < 10; r++) {
        drawBubbleMark(colM[r].$3, colM[r].$4, isFilled: isFilled && r == top, r: 10);
      }
    }
    final detectedReg = regDigits.every((d) => d.isEmpty) ? null : regDigits.join();

    // --- D. Evaluate Subject Code (boxResult.sub: 300x1000) ---
    final subTopY = _findInternalHDivider(boxResult.sub.warpedImage, 0.16, 0.26, 0.212);
    final subGridH = (boxResult.sub.targetHeight - 6.0) - subTopY;
    final subRowStep = subGridH / 10.0;
    final subColStep = boxResult.sub.targetWidth / 3.0;

    final subDigits = <String>[];
    final s1 = evalMicroBubble(boxResult.sub, 0.5 * subColStep, subTopY + 1.5 * subRowStep, radius: 15);
    final s2 = evalMicroBubble(boxResult.sub, 0.5 * subColStep, subTopY + 2.5 * subRowStep, radius: 15);
    final bool s1Filled = s1.$1 >= 0.24 && (s1.$1 - s2.$1) >= 0.08;
    final bool s2Filled = s2.$1 >= 0.24 && (s2.$1 - s1.$1) >= 0.08;
    if (s1Filled) {
      subDigits.add('1');
    } else if (s2Filled) {
      subDigits.add('2');
    } else {
      subDigits.add('');
    }
    drawBubbleMark(s1.$3, s1.$4, isFilled: s1Filled, r: 10);
    drawBubbleMark(s2.$3, s2.$4, isFilled: s2Filled, r: 10);

    for (int c = 1; c < 3; c++) {
      final u = (c + 0.5) * subColStep;
      final colM = List.generate(
        10,
        (r) => evalMicroBubble(boxResult.sub, u, subTopY + (r + 0.5) * subRowStep, radius: 15),
      );
      final sorted = List.generate(10, (i) => i)..sort((a, b) => colM[b].$1.compareTo(colM[a].$1));
      final top = sorted[0];
      final second = sorted[1];
      final isFilled = colM[top].$1 >= 0.24 && (colM[top].$1 - colM[second].$1) >= 0.08;
      subDigits.add(isFilled ? top.toString() : '');
      for (int r = 0; r < 10; r++) {
        drawBubbleMark(colM[r].$3, colM[r].$4, isFilled: isFilled && r == top, r: 10);
      }
    }
    final detectedSubject = subDigits.every((d) => d.isEmpty) ? null : subDigits.join();

    // --- E. Evaluate Questions 1 to 30 (400x1500 box framing the 4 Option Columns directly!) ---
    final options = ['A', 'B', 'C', 'D'];
    final detectedAnswers = <int, DetectedAnswer>{};

    void evaluateQuestionsBlock(MicroBox box, int startQ) {
      final ansTopY = _findInternalHDivider(box.warpedImage, 0.012, 0.038, 0.024);
      final ansGridH = (box.targetHeight - 50.0) - ansTopY;
      final ansRowStep = ansGridH / 15.0;
      final firstRowCenter = ansTopY + 0.40 * ansRowStep;

      for (int q = 0; q < 15; q++) {
        final qNum = startQ + q;
        final v = firstRowCenter + q * ansRowStep;
        final Map<String, double> scores = {};
        final List<(double, double, double, double)> optMetrics = [];

        for (int opt = 0; opt < 4; opt++) {
          final u = box.targetWidth * (0.155 + opt * 0.2625);
          final m = evalMicroBubble(box, u, v, radius: 16);
          optMetrics.add(m);
          scores[options[opt]] = double.parse(m.$1.clamp(0.0, 1.0).toStringAsFixed(3));
        }

        final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final top = sorted[0];
        final second = sorted[1];

        final isFilled = top.value >= 0.24 && (top.value - second.value) >= 0.08;
        final isMultiple = top.value >= 0.25 && second.value >= 0.25 && (top.value - second.value).abs() < 0.08;

        for (int opt = 0; opt < 4; opt++) {
          final m = optMetrics[opt];
          final filled = (isFilled && top.key == options[opt]) ||
              (isMultiple && (top.key == options[opt] || second.key == options[opt]));
          drawBubbleMark(m.$3, m.$4, isFilled: filled, r: 12);
        }

        if (isFilled) {
          detectedAnswers[qNum] = DetectedAnswer(
            questionNumber: qNum,
            selectedOptions: [top.key],
            classification: AnswerClassification.single,
            confidence: min(0.99, max(0.85, top.value + 0.35)),
            bubbleScores: scores,
            primaryAnswer: top.key,
          );
        } else if (isMultiple) {
          detectedAnswers[qNum] = DetectedAnswer(
            questionNumber: qNum,
            selectedOptions: [top.key, second.key],
            classification: AnswerClassification.multiple,
            confidence: 0.85,
            bubbleScores: scores,
          );
        } else {
          detectedAnswers[qNum] = DetectedAnswer(
            questionNumber: qNum,
            selectedOptions: const [],
            classification: AnswerClassification.blank,
            confidence: 0.95,
            bubbleScores: scores,
          );
        }
      }
    }

    evaluateQuestionsBlock(boxResult.ansCol1, 1);
    evaluateQuestionsBlock(boxResult.ansCol2, 16);

    final annotatedBytes = Uint8List.fromList(img.encodeJpg(annotated, quality: 90));
    final rectifiedBytes = Uint8List.fromList(img.encodeJpg(sheetCanvas, quality: 90));

    String? annotatedPath;
    try {
      final tempDir = Directory('${Directory.systemTemp.path}/omr_annotated');
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final filename = 'class9_10_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(annotatedBytes);
      annotatedPath = file.path;
    } catch (_) {}

    final int uncertainCount = detectedAnswers.values.where((a) => a.classification == AnswerClassification.uncertain).length;
    final int multipleCount = detectedAnswers.values.where((a) => a.classification == AnswerClassification.multiple).length;

    double overallConfidence = 0.98;
    String alignmentQuality = 'Good';

    if (uncertainCount > 3 || multipleCount > 4) {
      overallConfidence = 0.68;
      alignmentQuality = 'Review Needed';
    } else if (uncertainCount > 0 || multipleCount > 0) {
      overallConfidence = 0.84;
      alignmentQuality = 'Fair';
    } else {
      overallConfidence = 0.98;
      alignmentQuality = 'Good';
    }

    return ScanResult(
      status: ScanStatus.success,
      message: 'Class 9-10 OMR sheet scanned successfully.',
      detectedAnswers: detectedAnswers,
      sheetDetectionConfidence: overallConfidence,
      alignmentQuality: alignmentQuality,
      imagePath: imagePath,
      annotatedImagePath: annotatedPath,
      annotatedImageBytes: annotatedBytes,
      rectifiedImageBytes: rectifiedBytes,
      rollNumber: detectedRoll,
      setCode: detectedSetBangla,
      registrationNumber: detectedReg,
      subjectCode: detectedSubject,
      classMode: 'class_9_10',
    );
  }
}

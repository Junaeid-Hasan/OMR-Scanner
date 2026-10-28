import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../geometry/homography.dart';
import '../geometry/quadrilateral.dart';

class MicroBox {
  final String id;
  final Quadrilateral sheetQuad;
  final int targetWidth;
  final int targetHeight;
  final HomographyMatrix homography;
  final img.Image warpedImage;

  const MicroBox({
    required this.id,
    required this.sheetQuad,
    required this.targetWidth,
    required this.targetHeight,
    required this.homography,
    required this.warpedImage,
  });

  Point2D projectToSheet(double u, double v) {
    return homography.map(u, v);
  }
}

class MicroBoxDetectionResult {
  final MicroBox ansCol1;
  final MicroBox ansCol2;
  final MicroBox roll;
  final MicroBox reg;
  final MicroBox set;
  final MicroBox sub;

  const MicroBoxDetectionResult({
    required this.ansCol1,
    required this.ansCol2,
    required this.roll,
    required this.reg,
    required this.set,
    required this.sub,
  });

  List<MicroBox> get allBoxes => [ansCol1, ansCol2, roll, reg, set, sub];
}

class MicroBoxDetector {
  const MicroBoxDetector();

  static const int ansWidth = 400;
  static const int ansHeight = 1500;

  static const int rollWidth = 600;
  static const int rollHeight = 1000;

  static const int regWidth = 1000;
  static const int regHeight = 1000;

  static const int setWidth = 150;
  static const int setHeight = 500;

  static const int subWidth = 300;
  static const int subHeight = 1000;

  MicroBoxDetectionResult detectBoxes(img.Image sheetImage) {
    final w = sheetImage.width;
    final h = sheetImage.height;
    final total = w * h;

    // 1. Isolate Red/Pink ink intensity across the sheet
    final redness = Uint8List(total);
    int sumRed = 0;
    int countRed = 0;

    for (int y = (0.15 * h).round(); y < (0.86 * h).round(); y++) {
      final row = y * w;
      for (int x = (0.03 * w).round(); x < (0.95 * w).round(); x++) {
        final p = sheetImage.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final diff = r - ((g * 3 + b) >> 2);
        if (r > 85 && diff > 8) {
          final val = diff.clamp(0, 255);
          redness[row + x] = val;
          sumRed += val;
          countRed++;
        }
      }
    }

    final meanRed = countRed > 0 ? (sumRed / countRed) : 14.0;
    final redThresh = max(9, min(22, (meanRed * 0.78).round()));

    final redMask = Uint8List(total);
    for (int i = 0; i < total; i++) {
      if (redness[i] >= redThresh) redMask[i] = 1;
    }

    // 2. Identity transformation (coordinates in sheet canvas space)
    Point2D toTableSpace(double x, double y) => Point2D(x, y);

    // 3. Project red pixels into tilt-aligned coordinate space
    final alignedRed = Uint8List(total);
    for (int y = (0.15 * h).round(); y < (0.86 * h).round(); y++) {
      for (int x = (0.03 * w).round(); x < (0.95 * w).round(); x++) {
        if (redMask[y * w + x] == 1) {
          final pt = toTableSpace(x.toDouble(), y.toDouble());
          final u = pt.x.round();
          final v = pt.y.round();
          if (u >= 0 && u < w && v >= 0 && v < h) {
            alignedRed[v * w + u] = redness[y * w + x];
          }
        }
      }
    }

    // 4. Compute 1D Horizontal & Vertical Redness Profiles to lock onto the exact OMR Table Envelope
    // Find vTop (top border of the OMR boxes) and vBot (bottom border above "বিঃ দ্রঃ")
    int findStrongestHLine(int vMin, int vMax, int uStart, int uEnd, int fallbackV) {
      int bestV = fallbackV;
      int maxEnergy = 0;
      final rMin = vMin.clamp(4, h - 5);
      final rMax = vMax.clamp(4, h - 5);
      final cMin = uStart.clamp(4, w - 5);
      final cMax = uEnd.clamp(4, w - 5);

      for (int v = rMin; v <= rMax; v++) {
        int energy = 0;
        int count = 0;
        for (int dv = -1; dv <= 1; dv++) {
          final row = (v + dv) * w;
          for (int u = cMin; u <= cMax; u++) {
            final val = alignedRed[row + u];
            if (val > 0) {
              energy += val;
              count++;
            }
          }
        }
        // Require horizontal line coverage (> 18% of span) — lowered from 30% for real-world scans with faded ink
        if (count > (cMax - cMin) * 0.18 && energy > maxEnergy) {
          maxEnergy = energy;
          bestV = v;
        }
      }
      return bestV;
    }

    // In Class 9-10 sheet, the solid red header box ("বিষয় কোড") at middle-right anchors the layout.
    // Search within u: 0.68*w .. 0.82*w so we don't accidentally lock onto "বোর্ড" on the far right!
    int bestSubHeaderV = (0.505 * h).round();
    int maxSubBlockScore = 0;

    for (int v = (0.44 * h).round(); v <= (0.58 * h).round(); v += 2) {
      for (int u = (0.68 * w).round(); u <= (0.82 * w).round(); u += 3) {
        int blockScore = 0;
        for (int dv = 0; dv < 20; dv += 2) {
          final row = (v + dv) * w;
          for (int du = -24; du <= 24; du += 2) {
            if (v + dv < h && u + du >= 0 && u + du < w) {
              blockScore += alignedRed[row + (u + du)];
            }
          }
        }
        if (blockScore > maxSubBlockScore) {
          maxSubBlockScore = blockScore;
          bestSubHeaderV = v;
        }
      }
    }

    // Use the solid red "বিষয় কোড" header to anchor vMid, and find vTop & vBot accurately!
    final int vMid = findStrongestHLine(
      bestSubHeaderV - 12,
      bestSubHeaderV + 8,
      (0.45 * w).round(),
      (0.88 * w).round(),
      bestSubHeaderV,
    );

    final int vBot = findStrongestHLine(
      vMid + (0.22 * h).round(),
      min(h - 10, vMid + (0.34 * h).round()),
      (0.06 * w).round(),
      (0.85 * w).round(),
      vMid + (0.272 * h).round(),
    );

    final int bottomHalfH = max(120, vBot - vMid);
    final int expectedTopV = (vMid - bottomHalfH * 0.805).round();
    final int vTop = findStrongestHLine(
      expectedTopV - 35,
      expectedTopV + 35,
      (0.06 * w).round(),
      (0.70 * w).round(),
      expectedTopV,
    );

    final int tableH = max(240, vBot - vTop);
    final int vRollBot = findStrongestHLine(
      vMid - 40,
      vMid + 5,
      (0.40 * w).round(),
      (0.72 * w).round(),
      vMid - (tableH * 0.015).round(),
    );

    // Set code has only 4 bubbles (ক, খ, গ, ঘ) ending around 30% of table height:
    final int expSetBot = vTop + (tableH * 0.30).round();
    final int vSetBot = findStrongestHLine(
      expSetBot - 25,
      expSetBot + 25,
      (0.60 * w).round(),
      (0.78 * w).round(),
      expSetBot,
    );

    // 5. Find Vertical Lines using Comb-Filter / Multi-Line matching
    int findVLine(int uMin, int uMax, int v1, int v2, int fallbackU) {
      int bestU = fallbackU;
      int maxScore = 0;
      final cMin = uMin.clamp(4, w - 5);
      final cMax = uMax.clamp(4, w - 5);
      final r1 = v1.clamp(4, h - 5);
      final r2 = v2.clamp(4, h - 5);

      for (int u = cMin; u <= cMax; u++) {
        int score = 0;
        for (int du = -1; du <= 1; du++) {
          final col = u + du;
          for (int v = r1; v <= r2; v += 2) {
            score += alignedRed[v * w + col];
          }
        }
        if (score > maxScore) {
          maxScore = score;
          bestU = u;
        }
      }
      return maxScore > ((r2 - r1) ~/ 2) * 3 ? bestU : fallbackU;
    }

    // The central spine of the entire OMR table is the major continuous vertical divider
    // separating Answer Column 2 from Roll Number & Registration Number!
    // It runs the FULL HEIGHT of the table from vTop to vBot (around u ~ 0.48*w .. 0.52*w):
    final int estSpineU = (0.495 * w).round();
    final int uRollL = findVLine(
      (0.44 * w).round(),
      (0.54 * w).round(),
      vTop,
      vBot,
      estSpineU,
    );

    // In the official sheet, Registration has 10 columns below vMid, width ~ 0.388 * tableH:
    final int expRegW = (tableH * 0.388).round();
    final int expRegR = uRollL + expRegW;
    final int uRegR = findVLine(expRegR - 20, expRegR + 20, vMid, vBot, expRegR);
    final int regActualW = max(180, uRegR - uRollL);
    final double colUnit = regActualW / 10.0; // Exact column width of 1 bubble column

    // 1. Roll Number (6 columns, top half):
    final int expRollR = uRollL + (colUnit * 6.0).round();
    final int uRollR = findVLine(expRollR - 14, expRollR + 14, vTop, vRollBot, expRollR);

    // 2. Set Code (1 narrow bubble column adjacent to Roll):
    final int uSetL = uRollR;
    final int expSetW = (colUnit * 2.6).round();
    final int uSetR = findVLine(uSetL + (expSetW * 0.75).round(), uSetL + (expSetW * 1.25).round(), vTop, vSetBot, uSetL + expSetW);

    // 3. Registration Number (10 columns, bottom half):
    // Already defined by uRollL and uRegR!

    // 4. Subject Code (3 columns, bottom half, directly adjacent to Registration):
    final int uSubL = uRegR;
    final int expSubW = (colUnit * 3.2).round();
    final int uSubR = findVLine(uSubL + (expSubW * 0.75).round(), uSubL + (expSubW * 1.25).round(), vMid, vBot, uSubL + expSubW);

    // 5. AnsCol2 options (4 option columns ক, খ, গ, ঘ):
    // Right border is directly adjacent to Roll spine uRollL:
    final int uAns2R = uRollL;
    final int expAns2OptW = (colUnit * 5.2).round();
    final int estAns2OptL = uAns2R - expAns2OptW;
    final int uAns2OptL = findVLine(estAns2OptL - 14, estAns2OptL + 14, vTop, vBot, estAns2OptL);

    // 6. AnsCol1 options (4 option columns ক, খ, গ, ঘ):
    // Separated from AnsCol2 options by question number column (~3.6 colUnits):
    final int expAns1R = estAns2OptL - (colUnit * 3.6).round();
    final int uAns1R = findVLine(expAns1R - 14, expAns1R + 14, vTop, vBot, expAns1R);

    final int expAns1OptW = (colUnit * 5.3).round();
    final int estAns1OptL = uAns1R - expAns1OptW;
    final int uAns1OptL = findVLine(estAns1OptL - 14, estAns1OptL + 14, vTop, vBot, estAns1OptL);

    // Measure slant of the columns (top vs bottom shift)
    int ans1TopX = (uAns1OptL).clamp(50, w - 50);
    int ans1TopScore = 0;
    for (int x = uAns1OptL - 25; x <= uAns1OptL + 25; x++) {
      int score = 0;
      for (int y = vTop + 15; y <= vTop + 65; y += 2) {
        if (x >= 0 && x < w && y >= 0 && y < h) score += redness[y * w + x];
      }
      if (score > ans1TopScore) {
        ans1TopScore = score;
        ans1TopX = x;
      }
    }

    int ans1BotX = ans1TopX;
    int ans1BotScore = 0;
    for (int x = ans1TopX - 55; x <= ans1TopX + 25; x++) {
      int score = 0;
      for (int y = vBot - 65; y <= vBot - 15; y += 2) {
        if (x >= 0 && x < w && y >= 0 && y < h) score += redness[y * w + x];
      }
      if (score > ans1BotScore) {
        ans1BotScore = score;
        ans1BotX = x;
      }
    }

    final double slantDy = (vBot - 40.0) - (vTop + 40.0);
    final double tableSlant = slantDy > 100 ? ((ans1BotX - ans1TopX) / slantDy).clamp(-0.15, 0.15) : 0.0;

    MicroBox createAlignedBox(
      String id,
      int u1,
      int v1,
      int u2,
      int v2,
      int targetW,
      int targetH,
    ) {
      final shift1 = (v1 - vTop) * tableSlant;
      final shift2 = (v2 - vTop) * tableSlant;
      final tl = Point2D(u1.toDouble() + shift1, v1.toDouble());
      final tr = Point2D(u2.toDouble() + shift1, v1.toDouble());
      final br = Point2D(u2.toDouble() + shift2, v2.toDouble());
      final bl = Point2D(u1.toDouble() + shift2, v2.toDouble());

      final quad = Quadrilateral(tl: tl, tr: tr, br: br, bl: bl);
      final warped = HomographyMatrix.warpPerspective(sheetImage, quad, targetW, targetH);

      final dstQuad = Quadrilateral(
        tl: const Point2D(0.0, 0.0),
        tr: Point2D(targetW - 1.0, 0.0),
        br: Point2D(targetW - 1.0, targetH - 1.0),
        bl: Point2D(0.0, targetH - 1.0),
      );

      final homography = HomographyMatrix.findHomography(dstQuad, quad) ??
          HomographyMatrix([
            quad.topWidth / targetW, 0.0, quad.tl.x,
            0.0, quad.leftHeight / targetH, quad.tl.y,
            0.0, 0.0, 1.0,
          ]);

      return MicroBox(
        id: id,
        sheetQuad: quad,
        targetWidth: targetW,
        targetHeight: targetH,
        homography: homography,
        warpedImage: warped,
      );
    }

    // Apply 3px inward margin so warped images exclude red border lines that confuse bubble evaluation
    const int m = 3;
    return MicroBoxDetectionResult(
      ansCol1: createAlignedBox('ansCol1', uAns1OptL + m, vTop + m, uAns1R - m, vBot - m, ansWidth, ansHeight),
      ansCol2: createAlignedBox('ansCol2', uAns2OptL + m, vTop + m, uAns2R - m, vBot - m, ansWidth, ansHeight),
      roll:    createAlignedBox('roll',    uRollL + m,    vTop + m, uRollR - m, vRollBot - m, rollWidth, rollHeight),
      reg:     createAlignedBox('reg',     uRollL + m,    vMid + m, uRegR - m,  vBot - m, regWidth, regHeight),
      set:     createAlignedBox('set',     uSetL + m,     vTop + m, uSetR - m,  vSetBot - m, setWidth, setHeight),
      sub:     createAlignedBox('sub',     uSubL + m,     vMid + m, uSubR - m,  vBot - m, subWidth, subHeight),
    );
  }
}

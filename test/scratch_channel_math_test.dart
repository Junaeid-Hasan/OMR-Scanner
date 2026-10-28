import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:omr_scanner/omr/detection/sheet_detector.dart';
import 'package:omr_scanner/omr/geometry/quadrilateral.dart';


void main() {
  test('test column separation by clearing column gaps', () {
    for (final path in [
      'assets/test_images/bangla_omr_class9_10_sample.jpg',
      'assets/test_images/class_9_10_raw_camera_scan.jpg',
      'assets/test_images/class_9_10_marked_user_scan.png',
    ]) {

      print('=== Testing $path ===');
      final bytes = File(path).readAsBytesSync();
      final raw = img.decodeImage(bytes)!;
      final scale = raw.width / 1200.0;




      final h = (raw.height / scale).round();
      final image = img.copyResize(raw, width: 1200, height: h);
      final w = image.width;
      print('Resized to: ${w}x$h');

      // Check why ansCol1 broke between y=590 and 890 at x=250..350
      print('=== Inspecting ansCol1 in $path (x=250..350, y=590..890) ===');
      for (int y = 590; y <= 890; y += 30) {
        int cntRed = 0;
        int maxD = 0;
        for (int x = 250; x <= 350; x++) {
          final p = image.getPixel(x, y);
          final d = p.r.toInt() - p.g.toInt();
          if (d > maxD) maxD = d;
          if (d >= 16 && p.r > 100) cntRed++;
        }
        print('  y=$y: max R-G = $maxD, cnt(red) = $cntRed / 101');
      }




      // Fix 3: Direct Channel Arithmetic: cv.subtract(R_channel, G_channel)
      final diffMap = Uint8List(w * h);
      final binMask = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          final diff = (p.r.toInt() - p.g.toInt()).clamp(0, 255);
          diffMap[y * w + x] = diff;
          if (diff >= 16 && p.r > 100) {
            binMask[y * w + x] = 255;
          }
        }
      }
      // Check gap between y=740 and y=820 at x=600..700 (between Roll and Reg)

      print('=== Checking gap between Roll and Reg (x=600..700, y=740..820) ===');
      for (int y = 740; y <= 830; y += 10) {
        int cnt = 0;
        for (int x = 600; x <= 700; x++) {
          if (binMask[y * w + x] == 255) cnt++;
        }
        print('  y=$y: red count in [600..700] = $cnt');
      }

      // Check gap between AnsCol2 and Roll (x=540..590, y=500..700)
      print('=== Checking gap between AnsCol2 and Roll (x=540..590, y=500..700) ===');
      for (int x = 540; x <= 590; x += 5) {
        int cnt = 0;
        for (int y = 500; y <= 700; y++) {
          if (binMask[y * w + x] == 255) cnt++;
        }
        print('  x=$x: red count in [500..700] = $cnt');
      }

      // Check gap above bottom banner (y=1160..1200)
      print('=== Checking bottom border and banner (y=1160..1210, x=370..550) ===');
      for (int y = 1160; y <= 1210 && y < h; y += 5) {

        int cnt = 0;
        for (int x = 370; x <= 550; x++) {
          if (binMask[y * w + x] == 255) cnt++;
        }
        print('  y=$y: red count in [370..550] = $cnt');
      }

      final vLines = Uint8List(w * h);
      for (int x = 0; x < w; x++) {
        int s = 0;
        for (int y = 0; y < h; y++) {
          if (binMask[y * w + x] == 255) {
            s++;
            if (s >= 15) {
              for (int k = 0; k < s; k++) vLines[(y - k) * w + x] = 255;
            }
          } else {
            s = 0;
          }
        }
      }


      // 2. Horizontal line streaks (length >= 15) in binMask
      final hLines = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        int s = 0;
        for (int x = 0; x < w; x++) {
          if (binMask[y * w + x] == 255) {
            s++;
            if (s >= 15) {
              for (int k = 0; k < s; k++) hLines[y * w + (x - k)] = 255;
            }
          } else {
            s = 0;
          }
        }
      }

      // Vertical line projection along X
      final vLineProj = Int32List(w);
      for (int x = 0; x < w; x++) {
        int cnt = 0;
        for (int y = 0; y < h; y++) {
          if (vLines[y * w + x] == 255) cnt++;
        }
        vLineProj[x] = cnt;
      }
      print('=== Vertical line column projection ===');
      for (int x = 0; x < w; x += 25) {
        if (vLineProj[x] > 10) {
          print('  x=$x: ${vLineProj[x]}');
        }
      }




      // 5x5 Morphological Close on binMask
      final dilated = Uint8List(w * h);
      for (int y = 2; y < h - 2; y++) {
        for (int x = 2; x < w - 2; x++) {
          bool any = false;
          for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
              if (binMask[(y + dy) * w + (x + dx)] == 255) {
                any = true;
                break;
              }
            }
            if (any) break;
          }
          if (any) dilated[y * w + x] = 255;
        }
      }
      final closed = Uint8List(w * h);
      for (int y = 2; y < h - 2; y++) {
        for (int x = 2; x < w - 2; x++) {
          bool all = true;
          for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
              if (dilated[(y + dy) * w + (x + dx)] == 0) {
                all = false;
                break;
              }
            }
            if (!all) break;
          }
          if (all) closed[y * w + x] = 255;
        }
      }

      // Clear column gaps:

      // Column gap 1: between AnsCol1 and AnsCol2 (valley in x in [0.22*w .. 0.35*w])
      // Column gap 2: between AnsCol2 and Roll/Reg (valley in x in [0.42*w .. 0.52*w])
      // Column gap 3: between Reg and Sub (valley in x in [0.65*w .. 0.75*w])
      // Horizontal gap between Roll and Reg (valley in y in [0.45*h .. 0.58*h])
      // Horizontal gap below bottom of boxes (valley in y in [0.70*h .. 0.85*h])
      
      // We can find the local minima (valleys) in vLineProj!
      // Let's print the valleys in vLineProj between x in [250..400], [500..650], [750..900]
      int findValleyX(int x1, int x2) {
        int minX = x1, minVal = 999999;
        for (int x = x1; x <= x2; x++) {
          if (vLineProj[x] < minVal) {
            minVal = vLineProj[x];
            minX = x;
          }
        }
        return minX;
      }

      final vAnsGap = findValleyX((0.25 * w).round(), (0.35 * w).round());
      final vRollGap = findValleyX((0.44 * w).round(), (0.50 * w).round());
      final vSubGap = findValleyX((0.66 * w).round(), (0.75 * w).round());
      print('Valleys found: vAnsGap=$vAnsGap (val=${vLineProj[vAnsGap]}), vRollGap=$vRollGap (val=${vLineProj[vRollGap]}), vSubGap=$vSubGap (val=${vLineProj[vSubGap]})');

      // Clear thin 5px vertical stripe at each gap to cleanly separate columns
      final separated = Uint8List.fromList(closed);
      for (final gx in [vAnsGap, vRollGap, vSubGap]) {
        for (int dx = -3; dx <= 3; dx++) {
          final x = gx + dx;
          if (x >= 0 && x < w) {
            for (int y = 0; y < h; y++) separated[y * w + x] = 0;
          }
        }
      }

      // Horizontal line projection
      final hLineProj = Int32List(h);
      for (int y = 0; y < h; y++) {
        int cnt = 0;
        for (int x = 0; x < w; x++) {
          if (hLines[y * w + x] == 255) cnt++;
        }
        hLineProj[y] = cnt;
      }
      int findValleyY(int y1, int y2) {
        int minY = y1, minVal = 999999;
        for (int y = y1; y <= y2; y++) {
          if (hLineProj[y] < minVal) {
            minVal = hLineProj[y];
            minY = y;
          }
        }
        return minY;
      }
      final hMidGap = findValleyY((0.48 * h).round(), (0.56 * h).round());
      final hBotGap = findValleyY((0.72 * h).round(), (0.80 * h).round());
      print('Horizontal valleys: hMidGap=$hMidGap (val=${hLineProj[hMidGap]}), hBotGap=$hBotGap (val=${hLineProj[hBotGap]})');

      // Clear thin horizontal stripe at mid gap (only for x > vRollGap) and bottom gap (for all x)
      for (int dy = -3; dy <= 3; dy++) {
        final y = hMidGap + dy;
        if (y >= 0 && y < h) {
          for (int x = vRollGap; x < w; x++) separated[y * w + x] = 0;
        }
      }
      for (int dy = -3; dy <= 3; dy++) {
        final y = hBotGap + dy;
        if (y >= 0 && y < h) {
          for (int x = 0; x < w; x++) separated[y * w + x] = 0;
        }
      }



      final vProj = Int32List(w);
      for (int x = 0; x < w; x++) {
        int cnt = 0;
        for (int y = 0; y < h; y++) {
          final p = image.getPixel(x, y);
          if ((p.r.toInt() - p.g.toInt()) > 20 && p.r > 100) cnt++;
        }
        vProj[x] = cnt;
      }



      // Find horizontal projection
      final hProj = Int32List(h);
      for (int y = 0; y < h; y++) {
        int cnt = 0;
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          if ((p.r.toInt() - p.g.toInt()) > 20 && p.r > 100) cnt++;
        }
        hProj[y] = cnt;
      }

      print('=== Projections for $path ===');
      // Find regions where vProj > 100
      int segStart = -1;
      for (int x = 0; x < w; x++) {
        if (vProj[x] > 40 && segStart == -1) {
          segStart = x;
        } else if (vProj[x] <= 40 && segStart != -1) {
          if (x - segStart > 20) {
            print('  Vertical segment (X): [$segStart, $x], width=${x - segStart}');
          }
          segStart = -1;
        }
      }
      if (segStart != -1 && w - segStart > 20) {
        print('  Vertical segment (X): [$segStart, $w], width=${w - segStart}');
      }

      // Horizontal segments
      int yStart = -1;
      for (int y = 0; y < h; y++) {
        if (hProj[y] > 40 && yStart == -1) {
          yStart = y;
        } else if (hProj[y] <= 40 && yStart != -1) {
          if (y - yStart > 20) {
            print('  Horizontal segment (Y): [$yStart, $y], height=${y - yStart}');
          }
          yStart = -1;
        }
      }


      // Step 3: Find connected components on closed
      final labels = Int32List(w * h);
      final parent = <int>[0];
      int nextLabel = 1;
      int findRoot(int i) {
        var root = i;
        while (root != parent[root]) root = parent[root];
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
          if (rootI < rootJ) parent[rootJ] = rootI;
          else parent[rootI] = rootJ;
        }
      }
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (separated[y * w + x] == 255) {

            final nw = labels[(y - 1) * w + (x - 1)];
            final n = labels[(y - 1) * w + x];
            final ne = labels[(y - 1) * w + (x + 1)];
            final wst = labels[y * w + (x - 1)];
            final nb = <int>[];
            if (nw > 0) nb.add(nw);
            if (n > 0) nb.add(n);
            if (ne > 0) nb.add(ne);
            if (wst > 0) nb.add(wst);
            if (nb.isEmpty) {
              labels[y * w + x] = nextLabel;
              parent.add(nextLabel);
              nextLabel++;
            } else {
              int m = nb.first;
              for (final v in nb) if (v < m) m = v;
              labels[y * w + x] = m;
              for (final v in nb) union(m, v);
            }
          }
        }
      }

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

      // Clear any component touching the outer frame boundary (bed background)
      final borderLabels = <int>{};

      for (int x = 0; x < w; x++) {
        if (labels[0 * w + x] > 0) borderLabels.add(findRoot(labels[0 * w + x]));
        if (labels[(h - 1) * w + x] > 0) borderLabels.add(findRoot(labels[(h - 1) * w + x]));
      }
      for (int y = 0; y < h; y++) {
        if (labels[y * w + 0] > 0) borderLabels.add(findRoot(labels[y * w + 0]));
        if (labels[y * w + (w - 1)] > 0) borderLabels.add(findRoot(labels[y * w + (w - 1)]));
      }
      print('Border labels to suppress: $borderLabels');

      final candidates = <List<int>>[];
      final totalArea = (w * h).toDouble();
      for (final entry in compBounds.entries) {
        if (borderLabels.contains(entry.key)) continue;
        final b = entry.value;
        final bw = b[1] - b[0] + 1;
        final bh = b[3] - b[2] + 1;
        final area = bw * bh;
        final areaRatio = area / totalArea;
        // Area between 0.8% and 40%
        if (areaRatio >= 0.008 && areaRatio <= 0.40) {
          candidates.add([...b, area]);
        }
      }

      // Test 6 box extraction according to Fix 4:
      print('=== Geometric 6-box classification for $path ===');
      // Filter candidates inside table region (y in [0.20*h .. 0.85*h])
      final validCandidates = candidates.where((c) {
        final cy = (c[2] + c[3]) / 2.0;
        final cx = (c[0] + c[1]) / 2.0;
        return cy >= (0.18 * h) && cy <= (0.85 * h) && cx >= (0.05 * w) && cx <= (0.95 * w);
      }).toList();

      // 1. Two leftmost tall boxes (Height > Width * 1.6)
      final tallBoxes = validCandidates.where((c) {
        final bw = c[1] - c[0] + 1;
        final bh = c[3] - c[2] + 1;
        return (bh / bw) >= 1.6 && c[0] < (0.55 * w);
      }).toList()..sort((a, b) => a[0].compareTo(b[0]));

      print('Tall boxes found: ${tallBoxes.length}');
      // 6-box quad resolution
      Quadrilateral quadFromBounds(int x1, int y1, int x2, int y2) {
        return Quadrilateral(
          tl: Point2D(x1.toDouble(), y1.toDouble()),
          tr: Point2D(x2.toDouble(), y1.toDouble()),
          br: Point2D(x2.toDouble(), y2.toDouble()),
          bl: Point2D(x1.toDouble(), y2.toDouble()),
        );
      }

      Quadrilateral? quadAns1, quadAns2, quadRoll, quadSet, quadReg, quadSub;

      if (tallBoxes.length >= 2) {
        final a1 = tallBoxes[0];
        final a2 = tallBoxes[1];
        quadAns1 = quadFromBounds(a1[0], a1[2], a1[1], a1[3]);
        quadAns2 = quadFromBounds(a2[0], a2[2], a2[1], a2[3]);

        final rightBoxes = validCandidates.where((c) {
          final cx = (c[0] + c[1]) / 2.0;
          return cx > (a2[1] - 20);
        }).toList();

        final midY = (a2[2] + a2[3]) / 2.0;
        final topCandidates = rightBoxes.where((c) => ((c[2] + c[3]) / 2.0) < midY).toList()
          ..sort((a, b) => ((b[1] - b[0] + 1) * (b[3] - b[2] + 1)).compareTo((a[1] - a[0] + 1) * (a[3] - a[2] + 1)));
        final botCandidates = rightBoxes.where((c) => ((c[2] + c[3]) / 2.0) >= midY).toList()
          ..sort((a, b) => ((b[1] - b[0] + 1) * (b[3] - b[2] + 1)).compareTo((a[1] - a[0] + 1) * (a[3] - a[2] + 1)));

        if (topCandidates.isNotEmpty) {

          final t = topCandidates.first;
          final tw = t[1] - t[0] + 1;
          final th = t[3] - t[2] + 1;
          // Split Roll (6/7) and Set (1/7)
          final splitX = t[0] + (tw * 6 / 7.0).round();
          quadRoll = quadFromBounds(t[0], t[2], splitX, t[3]);
          quadSet = quadFromBounds(splitX, t[2], t[1], t[2] + (th * 0.55).round());
        }

        if (botCandidates.isNotEmpty) {
          final b = botCandidates.first;
          final bw = b[1] - b[0] + 1;
          // Split Reg (10/13) and Sub (3/13)
          final splitX = b[0] + (bw * 10 / 13.0).round();
          quadReg = quadFromBounds(b[0], b[2], splitX, b[3]);
          quadSub = quadFromBounds(splitX, b[2], b[1], b[3]);
        }
      }

      print('Resolved Quads for $path:');
      print('  ans1: $quadAns1');
      print('  ans2: $quadAns2');
      print('  roll: $quadRoll');
      print('  set:  $quadSet');
      print('  reg:  $quadReg');
      print('  sub:  $quadSub');



      int maxDiff = 0;
      int maxR = 0;

      int maxG = 0;
      int maxB = 0;
      int maxX = 0;
      int maxY = 0;
      final diffHist = Int32List(256);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          final diff = (p.r.toInt() - p.g.toInt()).clamp(0, 255);
          diffHist[diff]++;
          if (diff > maxDiff) {
            maxDiff = diff;
            maxR = p.r.toInt();
            maxG = p.g.toInt();
            maxB = p.b.toInt();
            maxX = x;
            maxY = y;
          }
        }
      }
      print('Max R-G diff = $maxDiff at ($maxX, $maxY), R=$maxR, G=$maxG, B=$maxB');
      for (int y = 0; y < h; y += 100) {
        int cnt30 = 0;
        int cnt50 = 0;
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          final diff = p.r.toInt() - p.g.toInt();
          if (diff >= 30) cnt30++;
          if (diff >= 50) cnt50++;
        }
        print('  y=$y: cnt(diff>=30)=$cnt30, cnt(diff>=50)=$cnt50');
      }



    }
  });
}

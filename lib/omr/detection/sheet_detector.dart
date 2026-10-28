import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../geometry/quadrilateral.dart';

class SheetDetectionResult {
  final Quadrilateral quad;
  final double confidence;
  final bool isCropped;
  final String message;

  const SheetDetectionResult({
    required this.quad,
    required this.confidence,
    required this.isCropped,
    required this.message,
  });

  bool get isReliable => confidence >= 0.65 && quad.isValid();
}

class SheetDetector {
  final double minAreaRatio;

  const SheetDetector({this.minAreaRatio = 0.35});

  SheetDetectionResult detectSheet(img.Image image) {
    final w = image.width;
    final h = image.height;
    final totalArea = (w * h).toDouble();

    final fullFrameQuad = Quadrilateral(
      tl: const Point2D(0, 0),
      tr: Point2D(w.toDouble() - 1, 0),
      br: Point2D(w.toDouble() - 1, h.toDouble() - 1),
      bl: Point2D(0, h.toDouble() - 1),
    );

    if (w < 100 || h < 100) {
      return SheetDetectionResult(
        quad: fullFrameQuad,
        confidence: 0.10,
        isCropped: true,
        message: 'Image is too small',
      );
    }

    final paperQuad = _detectPaperSheetQuad(image);
    if (paperQuad != null) {
      final areaRatio = paperQuad.area / totalArea;
      if (paperQuad.isConvex() && paperQuad.isValid() && areaRatio >= 0.35 && areaRatio <= 0.97) {
        return SheetDetectionResult(
          quad: paperQuad,
          confidence: 0.95,
          isCropped: false,
          message: 'White paper sheet detected and rectified',
        );
      }
    }

    return SheetDetectionResult(
      quad: fullFrameQuad,
      confidence: 0.85,
      isCropped: true,
      message: 'Using full frame',
    );
  }

  Quadrilateral? _detectPaperSheetQuad(img.Image raw) {
    const targetW = 360;
    final scale = raw.width / targetW.toDouble();
    final targetH = (raw.height / scale).round();
    final small = img.copyResize(raw, width: targetW, height: targetH);

    final w = small.width;
    final h = small.height;
    final total = w * h;

    final centerLums = <int>[];
    for (int y = (h * 0.25).round(); y < (h * 0.75).round(); y += 3) {
      for (int x = (w * 0.25).round(); x < (w * 0.75).round(); x += 3) {
        final p = small.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        centerLums.add(lum);
      }
    }
    centerLums.sort();
    final paperRefLum = centerLums.isNotEmpty ? centerLums[(centerLums.length * 0.75).floor()] : 200;

    final rawMask = Uint8List(total);
    final minPaperLum = max(115, (paperRefLum * 0.72).round());

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
        final maxC = max(r, max(g, b));
        final minC = min(r, min(g, b));
        final sat = maxC - minC;

        if (lum >= minPaperLum && sat < 55) {
          rawMask[y * w + x] = 1;
        }
      }
    }

    final closed = _morphClose(rawMask, w, h, radius: 3);

    final visited = Uint8List(total);
    final queue = Int32List(total);
    int head = 0, tail = 0;

    for (int y = (h * 0.40).round(); y <= (h * 0.60).round(); y += 4) {
      for (int x = (w * 0.40).round(); x <= (w * 0.60).round(); x += 4) {
        final idx = y * w + x;
        if (closed[idx] == 1 && visited[idx] == 0) {
          visited[idx] = 1;
          queue[tail++] = idx;
        }
      }
    }

    if (tail == 0) return null;

    final boundaryPts = <Point2D>[];
    int touchBorderCount = 0;

    while (head < tail) {
      final curr = queue[head++];
      final cy = curr ~/ w;
      final cx = curr % w;

      if (cx <= 2 || cx >= w - 3 || cy <= 2 || cy >= h - 3) {
        touchBorderCount++;
      }

      bool isEdge = cx <= 1 || cx >= w - 2 || cy <= 1 || cy >= h - 2 ||
          closed[curr - 1] == 0 || closed[curr + 1] == 0 ||
          closed[curr - w] == 0 || closed[curr + w] == 0;
      if (isEdge) {
        boundaryPts.add(Point2D(cx.toDouble(), cy.toDouble()));
      }

      if (cx > 1 && closed[curr - 1] == 1 && visited[curr - 1] == 0) {
        visited[curr - 1] = 1;
        queue[tail++] = curr - 1;
      }
      if (cx < w - 2 && closed[curr + 1] == 1 && visited[curr + 1] == 0) {
        visited[curr + 1] = 1;
        queue[tail++] = curr + 1;
      }
      if (cy > 1 && closed[curr - w] == 1 && visited[curr - w] == 0) {
        visited[curr - w] = 1;
        queue[tail++] = curr - w;
      }
      if (cy < h - 2 && closed[curr + w] == 1 && visited[curr + w] == 0) {
        visited[curr + w] = 1;
        queue[tail++] = curr + w;
      }
    }

    if (tail > total * 0.90 && touchBorderCount > (w + h) * 1.2) {
      return null;
    }

    if (boundaryPts.length < 30) return null;

    final hull = _convexHull(boundaryPts);
    if (hull.length < 4) return null;

    final corners = _findBestQuadCorners(hull);
    final scaled = corners.map((p) => Point2D(p.x * scale, p.y * scale)).toList();
    return Quadrilateral.orderPoints(scaled);
  }

  Uint8List _morphClose(Uint8List src, int w, int h, {int radius = 3}) {
    final dilated = Uint8List(w * h);
    final closed = Uint8List(w * h);

    for (int y = radius; y < h - radius; y++) {
      for (int x = radius; x < w - radius; x++) {
        if (src[y * w + x] == 1) {
          for (int dy = -radius; dy <= radius; dy++) {
            final row = (y + dy) * w;
            for (int dx = -radius; dx <= radius; dx++) {
              dilated[row + (x + dx)] = 1;
            }
          }
        }
      }
    }
    for (int y = radius; y < h - radius; y++) {
      for (int x = radius; x < w - radius; x++) {
        bool allOne = true;
        for (int dy = -radius; dy <= radius && allOne; dy++) {
          final row = (y + dy) * w;
          for (int dx = -radius; dx <= radius && allOne; dx++) {
            if (dilated[row + (x + dx)] == 0) allOne = false;
          }
        }
        if (allOne) closed[y * w + x] = 1;
      }
    }
    return closed;
  }

  List<Point2D> _convexHull(List<Point2D> pts) {
    if (pts.length <= 3) return pts;
    final sorted = List<Point2D>.from(pts)
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

    double cross(Point2D o, Point2D a, Point2D b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

    final lower = <Point2D>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Point2D>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  List<Point2D> _findBestQuadCorners(List<Point2D> hull) {
    if (hull.length <= 4) return hull;

    List<Point2D> pts = hull;
    if (pts.length > 28) {
      final step = pts.length / 28.0;
      pts = List.generate(28, (i) => pts[(i * step).floor() % pts.length]);
    }

    final n = pts.length;
    double maxArea = -1.0;
    int bA = 0, bB = 1, bC = 2, bD = 3;

    for (int a = 0; a < n - 3; a++) {
      for (int b = a + 1; b < n - 2; b++) {
        for (int c = b + 1; c < n - 1; c++) {
          for (int d = c + 1; d < n; d++) {
            final pA = pts[a], pB = pts[b], pC = pts[c], pD = pts[d];
            final area = 0.5 *
                ((pA.x * pB.y - pB.x * pA.y) +
                 (pB.x * pC.y - pC.x * pB.y) +
                 (pC.x * pD.y - pD.x * pC.y) +
                 (pD.x * pA.y - pA.x * pD.y)).abs();

            if (area > maxArea) {
              maxArea = area;
              bA = a; bB = b; bC = c; bD = d;
            }
          }
        }
      }
    }

    return [pts[bA], pts[bB], pts[bC], pts[bD]];
  }
}

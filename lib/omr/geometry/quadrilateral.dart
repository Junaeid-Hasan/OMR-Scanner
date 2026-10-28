import 'dart:math';

class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);
  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);
  Point2D operator *(double scalar) => Point2D(x * scalar, y * scalar);
  Point2D operator /(double scalar) => Point2D(x / scalar, y / scalar);

  double distanceTo(Point2D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return sqrt(dx * dx + dy * dy);
  }

  double crossProduct(Point2D other) => x * other.y - y * other.x;
  double dotProduct(Point2D other) => x * other.x + y * other.y;

  Point<double> toMathPoint() => Point<double>(x, y);

  @override
  String toString() => 'Point2D(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class Quadrilateral {
  final Point2D tl;
  final Point2D tr;
  final Point2D br;
  final Point2D bl;

  const Quadrilateral({
    required this.tl,
    required this.tr,
    required this.br,
    required this.bl,
  });

  List<Point2D> get points => [tl, tr, br, bl];

  double get topWidth => tl.distanceTo(tr);
  double get bottomWidth => bl.distanceTo(br);
  double get leftHeight => tl.distanceTo(bl);
  double get rightHeight => tr.distanceTo(br);

  /// Target rectified dimensions based on Euclidean norms (Resolution-agnostic)
  int get targetMaxWidth => max(topWidth, bottomWidth).round();
  int get targetMaxHeight => max(leftHeight, rightHeight).round();

  double get avgWidth => (topWidth + bottomWidth) / 2.0;
  double get avgHeight => (leftHeight + rightHeight) / 2.0;
  double get aspectRatio => avgHeight > 0 ? (avgWidth / avgHeight) : 1.0;

  /// Orders 4 corner points strictly in topological clockwise order: [TL, TR, BR, BL].
  /// Uses centroid polar angle sorting and top-left distance minimization
  /// to guarantee corners never cross, twist, or invert under perspective distortion.
  static Quadrilateral orderPoints(List<Point2D> points) {
    if (points.length != 4) {
      throw ArgumentError('Exactly 4 points are required to construct a Quadrilateral');
    }

    // 1. Calculate centroid
    final cx = (points[0].x + points[1].x + points[2].x + points[3].x) / 4.0;
    final cy = (points[0].y + points[1].y + points[2].y + points[3].y) / 4.0;

    // 2. Sort points by angle around centroid in clockwise order.
    // In screen coordinates (x right, y down), atan2(y - cy, x - cx)
    // increases clockwise as angle advances from -pi (left) to -pi/2 (top) to 0 (right) to +pi/2 (bottom).
    final sorted = List<Point2D>.from(points)
      ..sort((a, b) {
        final angleA = atan2(a.y - cy, a.x - cx);
        final angleB = atan2(b.y - cy, b.x - cx);
        return angleA.compareTo(angleB);
      });

    // 3. Find the top-left anchor: the point with minimum (x + y)
    int tlIndex = 0;
    double minSum = double.infinity;
    for (int i = 0; i < 4; i++) {
      final s = sorted[i].x + sorted[i].y;
      if (s < minSum) {
        minSum = s;
        tlIndex = i;
      }
    }

    // 4. Assign [TL, TR, BR, BL] cyclically in clockwise order starting from TL
    final tl = sorted[tlIndex];
    final tr = sorted[(tlIndex + 1) % 4];
    final br = sorted[(tlIndex + 2) % 4];
    final bl = sorted[(tlIndex + 3) % 4];

    return Quadrilateral(tl: tl, tr: tr, br: br, bl: bl);
  }

  /// Calculates the area of the polygon using the Shoelace formula
  double get area {
    final pts = points;
    double sum1 = 0;
    double sum2 = 0;
    for (int i = 0; i < 4; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 4];
      sum1 += p1.x * p2.y;
      sum2 += p1.y * p2.x;
    }
    return (0.5 * (sum1 - sum2)).abs();
  }

  /// Verifies if the quadrilateral is strictly convex
  bool isConvex() {
    final pts = points;
    bool? positive;
    for (int i = 0; i < 4; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 4];
      final p3 = pts[(i + 2) % 4];
      final edge1 = p2 - p1;
      final edge2 = p3 - p2;
      final cross = edge1.crossProduct(edge2);
      if (cross.abs() < 1e-5) continue;
      final isPos = cross > 0;
      if (positive == null) {
        positive = isPos;
      } else if (positive != isPos) {
        return false;
      }
    }
    return positive != null;
  }

  /// Validates whether the quadrilateral represents a plausible physical document
  bool isValid({
    double minArea = 1000.0,
    double maxOppositeRatio = 2.8,
    double minAspect = 0.45,
    double maxAspect = 2.2,
  }) {
    if (!isConvex()) return false;
    if (area < minArea) return false;

    final minW = min(topWidth, bottomWidth);
    final maxW = max(topWidth, bottomWidth);
    if (minW <= 10.0 || (maxW / minW) > maxOppositeRatio) return false;

    final minH = min(leftHeight, rightHeight);
    final maxH = max(leftHeight, rightHeight);
    if (minH <= 10.0 || (maxH / minH) > maxOppositeRatio) return false;

    if (aspectRatio < minAspect || aspectRatio > maxAspect) return false;

    return true;
  }

  /// Bilinear interpolation of normalized coordinates (u in [0, 1], v in [0, 1])
  Point2D mapBilinear(double u, double v) {
    final top = tl * (1.0 - u) + tr * u;
    final bot = bl * (1.0 - u) + br * u;
    return top * (1.0 - v) + bot * v;
  }

  /// Scale all points by a factor (e.g. from downscaled detection space to full-resolution space)
  Quadrilateral scale(double factor) {
    return Quadrilateral(
      tl: tl * factor,
      tr: tr * factor,
      br: br * factor,
      bl: bl * factor,
    );
  }

  @override
  String toString() => 'Quadrilateral(TL: $tl, TR: $tr, BR: $br, BL: $bl, Area: ${area.round()}, Aspect: ${aspectRatio.toStringAsFixed(2)})';
}

import 'package:image/image.dart' as img;
import 'quadrilateral.dart';

/// 3x3 Projective Homography Matrix for perspective correction and geometric warping.
class HomographyMatrix {
  final List<double> m; // 9 elements: row-major [h00, h01, h02, h10, h11, h12, h20, h21, h22]

  const HomographyMatrix(this.m);

  /// Map destination (canonical) point (u, v) back to source image coordinate (x, y)
  Point2D map(double u, double v) {
    final denom = m[6] * u + m[7] * v + m[8];
    if (denom.abs() < 1e-9) return Point2D(0, 0);
    final x = (m[0] * u + m[1] * v + m[2]) / denom;
    final y = (m[3] * u + m[4] * v + m[5]) / denom;
    return Point2D(x, y);
  }

  /// Solves the 3x3 Projective Homography mapping destination points [dstQuad] to source points [srcQuad].
  /// That is: for any (u, v) in canonical dstQuad space, homography.map(u, v) gives (x, y) in srcQuad space.
  static HomographyMatrix? findHomography(Quadrilateral dstQuad, Quadrilateral srcQuad) {
    final dst = dstQuad.points;
    final src = srcQuad.points;

    // 8x8 matrix A and 8-element vector B
    final a = List.generate(8, (_) => List<double>.filled(8, 0.0));
    final b = List<double>.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final u = dst[i].x;
      final v = dst[i].y;
      final x = src[i].x;
      final y = src[i].y;

      final row1 = i * 2;
      final row2 = row1 + 1;

      // Equation for x: u*h00 + v*h01 + h02 - u*x*h20 - v*x*h21 = x
      a[row1][0] = u;
      a[row1][1] = v;
      a[row1][2] = 1.0;
      a[row1][3] = 0.0;
      a[row1][4] = 0.0;
      a[row1][5] = 0.0;
      a[row1][6] = -u * x;
      a[row1][7] = -v * x;
      b[row1] = x;

      // Equation for y: u*h10 + v*h11 + h12 - u*y*h20 - v*y*h21 = y
      a[row2][0] = 0.0;
      a[row2][1] = 0.0;
      a[row2][2] = 0.0;
      a[row2][3] = u;
      a[row2][4] = v;
      a[row2][5] = 1.0;
      a[row2][6] = -u * y;
      a[row2][7] = -v * y;
      b[row2] = y;
    }

    // Solve Ah = b via Gaussian elimination with partial pivoting
    final h = _solveLinearSystem(a, b);
    if (h == null) return null;

    return HomographyMatrix([
      h[0], h[1], h[2],
      h[3], h[4], h[5],
      h[6], h[7], 1.0,
    ]);
  }

  static List<double>? _solveLinearSystem(List<List<double>> a, List<double> b) {
    const n = 8;
    for (int i = 0; i < n; i++) {
      // Find pivot
      int maxRow = i;
      double maxVal = a[i][i].abs();
      for (int k = i + 1; k < n; k++) {
        if (a[k][i].abs() > maxVal) {
          maxVal = a[k][i].abs();
          maxRow = k;
        }
      }

      if (maxVal < 1e-12) return null; // Singular matrix

      // Swap rows
      if (maxRow != i) {
        final tempA = a[i];
        a[i] = a[maxRow];
        a[maxRow] = tempA;

        final tempB = b[i];
        b[i] = b[maxRow];
        b[maxRow] = tempB;
      }

      // Eliminate below
      for (int k = i + 1; k < n; k++) {
        final factor = a[k][i] / a[i][i];
        for (int j = i; j < n; j++) {
          a[k][j] -= factor * a[i][j];
        }
        b[k] -= factor * b[i];
      }
    }

    // Back substitution
    final x = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = b[i];
      for (int j = i + 1; j < n; j++) {
        sum -= a[i][j] * x[j];
      }
      x[i] = sum / a[i][i];
    }

    return x;
  }

  /// Warps [source] image into canonical dimensions ([targetWidth] x [targetHeight])
  /// using bilinear backward pixel interpolation.
  static img.Image warpPerspective(
    img.Image source,
    Quadrilateral srcCorners,
    int targetWidth,
    int targetHeight,
  ) {
    final dstQuad = Quadrilateral(
      tl: const Point2D(0.0, 0.0),
      tr: Point2D(targetWidth - 1.0, 0.0),
      br: Point2D(targetWidth - 1.0, targetHeight - 1.0),
      bl: Point2D(0.0, targetHeight - 1.0),
    );

    final homography = findHomography(dstQuad, srcCorners);
    final output = img.Image(width: targetWidth, height: targetHeight);

    final sw = source.width;
    final sh = source.height;

    for (int v = 0; v < targetHeight; v++) {
      for (int u = 0; u < targetWidth; u++) {
        final pt = homography != null
            ? homography.map(u.toDouble(), v.toDouble())
            : srcCorners.mapBilinear(u / (targetWidth - 1.0), v / (targetHeight - 1.0));

        final sx = pt.x;
        final sy = pt.y;

        if (sx >= 0 && sx < sw - 1 && sy >= 0 && sy < sh - 1) {
          // Bilinear interpolation
          final x0 = sx.floor();
          final y0 = sy.floor();
          final x1 = x0 + 1;
          final y1 = y0 + 1;

          final dx = sx - x0;
          final dy = sy - y0;

          final p00 = source.getPixel(x0, y0);
          final p10 = source.getPixel(x1, y0);
          final p01 = source.getPixel(x0, y1);
          final p11 = source.getPixel(x1, y1);

          final r = (1 - dx) * (1 - dy) * p00.r +
              dx * (1 - dy) * p10.r +
              (1 - dx) * dy * p01.r +
              dx * dy * p11.r;

          final g = (1 - dx) * (1 - dy) * p00.g +
              dx * (1 - dy) * p10.g +
              (1 - dx) * dy * p01.g +
              dx * dy * p11.g;

          final b = (1 - dx) * (1 - dy) * p00.b +
              dx * (1 - dy) * p10.b +
              (1 - dx) * dy * p01.b +
              dx * dy * p11.b;

          output.setPixelRgb(u, v, r.round(), g.round(), b.round());
        } else if (sx >= 0 && sx < sw && sy >= 0 && sy < sh) {
          final p = source.getPixel(sx.round(), sy.round());
          output.setPixelRgb(u, v, p.r.toInt(), p.g.toInt(), p.b.toInt());
        } else {
          output.setPixelRgb(u, v, 255, 255, 255);
        }
      }
    }

    return output;
  }
}

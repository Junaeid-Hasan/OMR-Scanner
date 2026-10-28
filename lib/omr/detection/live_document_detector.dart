import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../geometry/quadrilateral.dart';

/// Detection result produced for a single camera frame or image.
class LiveDetectionResult {
  /// Normalized quadrilateral corners [tl, tr, br, bl] in [0.0, 1.0] portrait preview coordinates.
  final Quadrilateral? normalizedQuad;

  /// Detection confidence in [0.0, 1.0].
  final double confidence;

  /// Measure of edge variance; low values indicate motion blur or out-of-focus camera.
  final double blurScore;

  /// Whether the frame is considered too blurry for stable recognition.
  final bool isBlurry;

  /// Whether the detected quadrilateral satisfies all geometric and contrast criteria.
  final bool isReliable;

  /// Human-readable status message for user guidance.
  final String message;

  /// Time spent analyzing the frame in milliseconds.
  final int processingTimeMs;

  const LiveDetectionResult({
    this.normalizedQuad,
    required this.confidence,
    required this.blurScore,
    required this.isBlurry,
    required this.isReliable,
    required this.message,
    required this.processingTimeMs,
  });

  factory LiveDetectionResult.searching({
    double blurScore = 0.0,
    bool isBlurry = false,
    String message = 'Searching for document...',
    int processingTimeMs = 0,
  }) {
    return LiveDetectionResult(
      normalizedQuad: null,
      confidence: 0.0,
      blurScore: blurScore,
      isBlurry: isBlurry,
      isReliable: false,
      message: message,
      processingTimeMs: processingTimeMs,
    );
  }
}

/// Ultra-fast, resolution-independent live document detector for real-time camera streams.
///
/// Designed to execute in under 15-25ms on modern mobile processors:
/// 1. Directly consumes Y-plane luminance from [CameraImage] (or BGRA on iOS)
/// 2. Downsamples and applies sensor rotation into portrait orientation
/// 3. Computes gradient blur metric for motion stability check
/// 4. Executes optimized Canny edge detection & morphological closing
/// 5. Identifies document boundaries via convex hull and quad corner approximation
/// 6. Performs geometric plausibility validation and returns normalized [0, 1] coordinates
class LiveDocumentDetector {
  /// Target exam sheet mode ('class_6_8' or 'class_9_10') to enforce exact document aspect ratios.
  final String classMode;

  /// Minimum area ratio of document relative to entire camera frame.
  final double minAreaRatio;

  /// Maximum area ratio of document relative to camera frame (avoids full-frame false-positives).
  final double maxAreaRatio;

  /// Minimum blur score to consider a frame sharp enough for capture.
  final double blurThreshold;

  /// Target width for the downsampled working frame in pixels.
  final int targetWorkingWidth;

const LiveDocumentDetector({
    this.classMode = 'class_6_8',
    this.minAreaRatio = 0.40, // <-- 0.05 থেকে 0.40 করুন যাতে ছোট বক্সকে পুরো পাতা না ভাবে!
    this.maxAreaRatio = 0.95,
    this.blurThreshold = 8.0,
    this.targetWorkingWidth = 360,
  });

  /// Analyzes a live [CameraImage] from [CameraController.startImageStream].
  LiveDetectionResult detectFromCameraImage(CameraImage cameraImage, int sensorOrientation) {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Extract downsampled portrait grayscale buffer
      final downsampled = _extractDownsampledPortraitGray(cameraImage, sensorOrientation);
      if (downsampled == null) {
        return LiveDetectionResult.searching(
          message: 'Unsupported camera pixel format',
          processingTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      final w = downsampled.width;
      final h = downsampled.height;
      final gray = downsampled.data;

      // 2. Compute blur & sharpness score
      final blurScore = _computeSharpnessScore(gray, w, h);
      final isBlurry = blurScore < blurThreshold;

      // 3. Detect candidate document contour and corners
      final rawQuad = _findDocumentQuad(gray, w, h);

      if (rawQuad == null) {
        final message = isBlurry ? 'Camera moving, hold steady...' : 'Searching for document...';
        return LiveDetectionResult.searching(
          blurScore: blurScore,
          isBlurry: isBlurry,
          message: message,
          processingTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      // 4. Validate quadrilateral geometry
      final validation = _validateGeometry(rawQuad, w, h);
      if (!validation.isValid) {
        return LiveDetectionResult.searching(
          blurScore: blurScore,
          isBlurry: isBlurry,
          message: validation.message,
          processingTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      // 5. Normalize coordinates to [0.0, 1.0]
      final normQuad = Quadrilateral(
        tl: Point2D(rawQuad.tl.x / w, rawQuad.tl.y / h),
        tr: Point2D(rawQuad.tr.x / w, rawQuad.tr.y / h),
        br: Point2D(rawQuad.br.x / w, rawQuad.br.y / h),
        bl: Point2D(rawQuad.bl.x / w, rawQuad.bl.y / h),
      );

      final isReliable = !isBlurry && validation.confidence >= 0.70;
      final statusMessage = isBlurry
          ? 'Hold steady...'
          : (isReliable ? 'Document detected' : 'Align sheet inside view');

      return LiveDetectionResult(
        normalizedQuad: normQuad,
        confidence: validation.confidence,
        blurScore: blurScore,
        isBlurry: isBlurry,
        isReliable: isReliable,
        message: statusMessage,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      return LiveDetectionResult.searching(
        message: 'Detection error: $e',
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Analyzes a decoded [img.Image] directly (useful for tests or gallery images).
  LiveDetectionResult detectFromImage(img.Image image) {
    final stopwatch = Stopwatch()..start();

    final targetW = min(image.width, 600);
    final scale = image.width / targetW.toDouble();
    final targetH = (image.height / scale).round();
    final small = img.copyResize(image, width: targetW, height: targetH);

    final w = small.width;
    final h = small.height;
    final gray = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        gray[y * w + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }

    final blurScore = _computeSharpnessScore(gray, w, h);
    final rawQuad = _findDocumentQuad(gray, w, h);

    if (rawQuad == null) {
      return LiveDetectionResult.searching(
        blurScore: blurScore,
        isBlurry: blurScore < blurThreshold,
        message: 'No document detected',
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    }

    final validation = _validateGeometry(rawQuad, w, h);
    if (!validation.isValid) {
      return LiveDetectionResult.searching(
        blurScore: blurScore,
        isBlurry: blurScore < blurThreshold,
        message: validation.message,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    }

    final normQuad = Quadrilateral(
      tl: Point2D(rawQuad.tl.x / w, rawQuad.tl.y / h),
      tr: Point2D(rawQuad.tr.x / w, rawQuad.tr.y / h),
      br: Point2D(rawQuad.br.x / w, rawQuad.br.y / h),
      bl: Point2D(rawQuad.bl.x / w, rawQuad.bl.y / h),
    );

    return LiveDetectionResult(
      normalizedQuad: normQuad,
      confidence: validation.confidence,
      blurScore: blurScore,
      isBlurry: blurScore < blurThreshold,
      isReliable: validation.confidence >= 0.70,
      message: 'Document detected',
      processingTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Fast luminance extraction and sensor rotation into portrait orientation.
  _DownsampledBuffer? _extractDownsampledPortraitGray(CameraImage image, int sensorOrientation) {
    final srcW = image.width;
    final srcH = image.height;

    // Determine orientation layout
    final isRotated = sensorOrientation == 90 || sensorOrientation == 270;
    final portraitW = isRotated ? srcH : srcW;
    final portraitH = isRotated ? srcW : srcH;

    final step = max(1, (portraitW / 320).ceil());
    final outW = portraitW ~/ step;
    final outH = portraitH ~/ step;
    final out = Uint8List(outW * outH);

    // Support Android YUV420 & NV21 (Plane 0 is direct Y luminance)
    if (image.format.group == ImageFormatGroup.yuv420 || image.format.group == ImageFormatGroup.nv21 || image.planes.isNotEmpty) {
      final yPlane = image.planes[0];
      final yBytes = yPlane.bytes;
      final stride = yPlane.bytesPerRow;

      if (sensorOrientation == 90) {
        // Android typical back camera: 90 deg clockwise
        // (x_src, y_src) -> (srcH - 1 - y_src, x_src)
        for (int oy = 0; oy < outH; oy++) {
          final srcX = oy * step;
          if (srcX >= srcW) continue;
          for (int ox = 0; ox < outW; ox++) {
            final srcY = (outW - 1 - ox) * step;
            if (srcY >= srcH) continue;
            out[oy * outW + ox] = yBytes[srcY * stride + srcX];
          }
        }
      } else if (sensorOrientation == 270) {
        // 270 deg
        for (int oy = 0; oy < outH; oy++) {
          final srcX = (outH - 1 - oy) * step;
          if (srcX >= srcW) continue;
          for (int ox = 0; ox < outW; ox++) {
            final srcY = ox * step;
            if (srcY >= srcH) continue;
            out[oy * outW + ox] = yBytes[srcY * stride + srcX];
          }
        }
      } else {
        // 0 deg
        for (int oy = 0; oy < outH; oy++) {
          final srcY = oy * step;
          if (srcY >= srcH) continue;
          for (int ox = 0; ox < outW; ox++) {
            final srcX = ox * step;
            if (srcX >= srcW) continue;
            out[oy * outW + ox] = yBytes[srcY * stride + srcX];
          }
        }
      }
      return _DownsampledBuffer(width: outW, height: outH, data: out);
    }

    // Support iOS BGRA8888
    if (image.format.group == ImageFormatGroup.bgra8888 && image.planes.isNotEmpty) {
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final stride = plane.bytesPerRow;

      for (int oy = 0; oy < outH; oy++) {
        final srcY = oy * step;
        if (srcY >= srcH) continue;
        for (int ox = 0; ox < outW; ox++) {
          final srcX = ox * step;
          if (srcX >= srcW) continue;
          final idx = srcY * stride + srcX * 4;
          if (idx + 2 < bytes.length) {
            final b = bytes[idx];
            final g = bytes[idx + 1];
            final r = bytes[idx + 2];
            out[oy * outW + ox] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
          }
        }
      }
      return _DownsampledBuffer(width: outW, height: outH, data: out);
    }

    return null;
  }

  /// Computes gradient variance to estimate image sharpness.
  double _computeSharpnessScore(Uint8List gray, int w, int h) {
    double sumGrad = 0;
    double sumSqGrad = 0;
    int count = 0;

    // Sample with step 2 for ultra-fast execution (< 1ms)
    for (int y = 2; y < h - 2; y += 2) {
      for (int x = 2; x < w - 2; x += 2) {
        final gx = (gray[y * w + (x + 1)] - gray[y * w + (x - 1)]).abs();
        final gy = (gray[(y + 1) * w + x] - gray[(y - 1) * w + x]).abs();
        final g = (gx + gy).toDouble();
        sumGrad += g;
        sumSqGrad += g * g;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sumGrad / count;
    final variance = (sumSqGrad / count) - (mean * mean);
    return max(0.0, variance);
  }

  /// Finds the 4 corners of the prominent document boundary.
  Quadrilateral? _findDocumentQuad(Uint8List gray, int w, int h) {
    // 1. Ultra-fast Canny edge detection
    final edges = _canny(gray, w, h, lowThresh: 15, highThresh: 45);

    // 2. Clear outer boundary border pixels (avoids false screen edge connections)
    const margin = 4;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (x < margin || x >= w - margin || y < margin || y >= h - margin) {
          edges[y * w + x] = 0;
        }
      }
    }

    // 3. Morphological close (3x3) to bridge broken sheet lines
    final closed = _morphClose(edges, w, h);

    // 4. Connected component analysis and convex hull quad approximation
    return _extractBestQuadrilateral(closed, w, h);
  }

  Uint8List _canny(Uint8List rawGray, int w, int h, {required double lowThresh, required double highThresh}) {
    final temp = Uint8List(w * h);
    final blurred = Uint8List(w * h);

    // 1. Separable 1D Gaussian horizontal pass [1, 4, 6, 4, 1] / 16 (bit-shifted)
    for (int y = 0; y < h; y++) {
      final row = y * w;
      for (int x = 2; x < w - 2; x++) {
        temp[row + x] = (rawGray[row + (x - 2)] +
                (rawGray[row + (x - 1)] << 2) +
                rawGray[row + x] * 6 +
                (rawGray[row + (x + 1)] << 2) +
                rawGray[row + (x + 2)]) >>
            4;
      }
      temp[row] = rawGray[row];
      temp[row + 1] = rawGray[row + 1];
      temp[row + w - 2] = rawGray[row + w - 2];
      temp[row + w - 1] = rawGray[row + w - 1];
    }

    // 2. Separable 1D Gaussian vertical pass [1, 4, 6, 4, 1] / 16 (bit-shifted)
    for (int x = 0; x < w; x++) {
      for (int y = 2; y < h - 2; y++) {
        blurred[y * w + x] = (temp[(y - 2) * w + x] +
                (temp[(y - 1) * w + x] << 2) +
                temp[y * w + x] * 6 +
                (temp[(y + 1) * w + x] << 2) +
                temp[(y + 2) * w + x]) >>
            4;
      }
      blurred[x] = temp[x];
      blurred[w + x] = temp[w + x];
      blurred[(h - 2) * w + x] = temp[(h - 2) * w + x];
      blurred[(h - 1) * w + x] = temp[(h - 1) * w + x];
    }

    // 3. Sobel gradients with fast ratio direction quantization (no atan2 overhead)
    final mag = Float32List(w * h);
    final dir = Uint8List(w * h);

    for (int y = 1; y < h - 1; y++) {
      final yPrev = (y - 1) * w;
      final yCurr = y * w;
      final yNext = (y + 1) * w;

      for (int x = 1; x < w - 1; x++) {
        final p00 = blurred[yPrev + (x - 1)];
        final p01 = blurred[yPrev + x];
        final p02 = blurred[yPrev + (x + 1)];
        final p10 = blurred[yCurr + (x - 1)];
        final p12 = blurred[yCurr + (x + 1)];
        final p20 = blurred[yNext + (x - 1)];
        final p21 = blurred[yNext + x];
        final p22 = blurred[yNext + (x + 1)];

        final gx = (p02 + (p12 << 1) + p22) - (p00 + (p10 << 1) + p20);
        final gy = (p20 + (p21 << 1) + p22) - (p00 + (p01 << 1) + p02);

        final absGx = gx.abs();
        final absGy = gy.abs();
        mag[yCurr + x] = sqrt((gx * gx + gy * gy).toDouble());

        // Fast angle binning into [0, 1, 2, 3] avoiding costly atan2 calls
        if (absGy > 2.4142 * absGx) {
          dir[yCurr + x] = 2; // Vertical gradient (horizontal edge)
        } else if (absGy > 0.4142 * absGx) {
          dir[yCurr + x] = ((gx > 0 && gy > 0) || (gx < 0 && gy < 0)) ? 1 : 3;
        } else {
          dir[yCurr + x] = 0; // Horizontal gradient (vertical edge)
        }
      }
    }

    // 4. Non-maximum suppression
    final nms = Float32List(w * h);
    for (int y = 2; y < h - 2; y++) {
      final yOffset = y * w;
      for (int x = 2; x < w - 2; x++) {
        final m = mag[yOffset + x];
        if (m < lowThresh) continue;

        double m1 = 0, m2 = 0;
        switch (dir[yOffset + x]) {
          case 0:
            m1 = mag[yOffset + (x - 1)];
            m2 = mag[yOffset + (x + 1)];
            break;
          case 1:
            m1 = mag[(y - 1) * w + (x + 1)];
            m2 = mag[(y + 1) * w + (x - 1)];
            break;
          case 2:
            m1 = mag[(y - 1) * w + x];
            m2 = mag[(y + 1) * w + x];
            break;
          case 3:
            m1 = mag[(y - 1) * w + (x - 1)];
            m2 = mag[(y + 1) * w + (x + 1)];
            break;
        }

        if (m >= m1 && m >= m2) {
          nms[yOffset + x] = m;
        }
      }
    }

    // 5. Hysteresis thresholding
    final edges = Uint8List(w * h);
    final stack = <int>[];

    for (int y = 2; y < h - 2; y++) {
      final yOffset = y * w;
      for (int x = 2; x < w - 2; x++) {
        final idx = yOffset + x;
        if (nms[idx] >= highThresh && edges[idx] == 0) {
          edges[idx] = 1;
          stack.add(idx);

          while (stack.isNotEmpty) {
            final curr = stack.removeLast();
            final cy = curr ~/ w;
            final cx = curr % w;

            for (int dy = -1; dy <= 1; dy++) {
              final nRow = (cy + dy) * w;
              for (int dx = -1; dx <= 1; dx++) {
                final nIdx = nRow + (cx + dx);
                if (cy + dy >= 0 && cy + dy < h && cx + dx >= 0 && cx + dx < w) {
                  if (edges[nIdx] == 0 && nms[nIdx] >= lowThresh) {
                    edges[nIdx] = 1;
                    stack.add(nIdx);
                  }
                }
              }
            }
          }
        }
      }
    }

    return edges;
  }

  Uint8List _morphClose(Uint8List src, int w, int h) {
    final dilated = Uint8List(w * h);
    final closed = Uint8List(w * h);

    // Dilate (3x3)
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (src[y * w + x] == 1) {
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              dilated[(y + dy) * w + (x + dx)] = 1;
            }
          }
        }
      }
    }

    // Erode (3x3)
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        bool allOne = true;
        for (int dy = -1; dy <= 1 && allOne; dy++) {
          for (int dx = -1; dx <= 1 && allOne; dx++) {
            if (dilated[(y + dy) * w + (x + dx)] == 0) {
              allOne = false;
            }
          }
        }
        if (allOne) {
          closed[y * w + x] = 1;
        }
      }
    }

    return closed;
  }

  Quadrilateral? _extractBestQuadrilateral(Uint8List edges, int w, int h) {
    // Two-pass connected component labeling with disjoint set union
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
        if (edges[y * w + x] == 1) {
          final nw = labels[(y - 1) * w + (x - 1)];
          final n = labels[(y - 1) * w + x];
          final ne = labels[(y - 1) * w + (x + 1)];
          final wst = labels[y * w + (x - 1)];

          int minLabel = 0;
          if (nw > 0) minLabel = nw;
          if (n > 0 && (minLabel == 0 || n < minLabel)) minLabel = n;
          if (ne > 0 && (minLabel == 0 || ne < minLabel)) minLabel = ne;
          if (wst > 0 && (minLabel == 0 || wst < minLabel)) minLabel = wst;

          if (minLabel == 0) {
            labels[y * w + x] = nextLabel;
            parent.add(nextLabel);
            nextLabel++;
          } else {
            labels[y * w + x] = minLabel;
            if (nw > 0) union(minLabel, nw);
            if (n > 0) union(minLabel, n);
            if (ne > 0) union(minLabel, ne);
            if (wst > 0) union(minLabel, wst);
          }
        }
      }
    }

    final components = <int, List<Point2D>>{};
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final lbl = labels[y * w + x];
        if (lbl > 0) {
          final root = findRoot(lbl);
          components.putIfAbsent(root, () => []).add(Point2D(x.toDouble(), y.toDouble()));
        }
      }
    }

    final sortedComponents = components.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final comp in sortedComponents.take(6)) {
      double minX = w.toDouble(), maxX = 0, minY = h.toDouble(), maxY = 0;
      for (final p in comp) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }

      final bw = maxX - minX;
      final bh = maxY - minY;
      if (bw < w * 0.50 || bh < h * 0.50) continue; // 

      final hull = _convexHull(comp);
      if (hull.length < 4) continue;

      final corners = _findBestQuadCorners(hull);
      final candidate = Quadrilateral.orderPoints(corners);
      if (!candidate.isConvex()) continue;

      final minW = min(candidate.topWidth, candidate.bottomWidth);
      final maxW = max(candidate.topWidth, candidate.bottomWidth);
      if (minW <= 12 || (maxW / minW) > 2.4) continue;

      final minH = min(candidate.leftHeight, candidate.rightHeight);
      final maxH = max(candidate.leftHeight, candidate.rightHeight);
      if (minH <= 12 || (maxH / minH) > 2.4) continue;

      final qw = candidate.targetMaxWidth;
      final qh = candidate.targetMaxHeight;
      final ar = qw / qh;
      final isValidRatio = (ar >= 0.40 && ar <= 1.10) || (ar >= 0.90 && ar <= 2.30);
      if (!isValidRatio) continue;

      return candidate;
    }

    return null;
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

  /// Inscribes a maximum-area quadrilateral in the convex hull vertices.
  /// Mathematically selects the 4 true physical corners of a document invariant to tilt and perspective distortion.
  List<Point2D> _findBestQuadCorners(List<Point2D> hull) {
    if (hull.length <= 4) return hull;

    List<Point2D> pts = hull;
    if (pts.length > 12) {
      final step = pts.length / 12.0;
      pts = List.generate(12, (i) => pts[(i * step).floor() % pts.length]);
    }

    final n = pts.length;
    double maxArea = -1.0;
    int bA = 0, bB = 1, bC = 2, bD = 3;

    for (int a = 0; a < n - 3; a++) {
      for (int b = a + 1; b < n - 2; b++) {
        for (int c = b + 1; c < n - 1; c++) {
          for (int d = c + 1; d < n; d++) {
            final pA = pts[a];
            final pB = pts[b];
            final pC = pts[c];
            final pD = pts[d];

            final area = 0.5 *
                ((pA.x * pB.y - pB.x * pA.y) +
                 (pB.x * pC.y - pC.x * pB.y) +
                 (pC.x * pD.y - pD.x * pC.y) +
                 (pD.x * pA.y - pA.x * pD.y)).abs();

            if (area > maxArea) {
              maxArea = area;
              bA = a;
              bB = b;
              bC = c;
              bD = d;
            }
          }
        }
      }
    }

    return [pts[bA], pts[bB], pts[bC], pts[bD]];
  }

  _ValidationResult _validateGeometry(Quadrilateral quad, int w, int h) {
    final totalArea = (w * h).toDouble();
    final areaRatio = quad.area / totalArea;

    if (!quad.isConvex()) {
      return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Invalid shape');
    }

    if (areaRatio < minAreaRatio) {
      return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Move closer to the document');
    }

    if (areaRatio > maxAreaRatio) {
      return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Move back slightly');
    }

    // Check opposite side ratios
    final minW = min(quad.topWidth, quad.bottomWidth);
    final maxW = max(quad.topWidth, quad.bottomWidth);
    if (minW <= 5 || (maxW / minW) > 2.5) {
      return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Tilt camera forward');
    }

    final minH = min(quad.leftHeight, quad.rightHeight);
    final maxH = max(quad.leftHeight, quad.rightHeight);
    if (minH <= 5 || (maxH / minH) > 2.5) {
      return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Tilt camera forward');
    }

    // Check corner angles
    final points = quad.points;
    for (int i = 0; i < 4; i++) {
      final pPrev = points[(i + 3) % 4];
      final pCurr = points[i];
      final pNext = points[(i + 1) % 4];

      final v1 = pPrev - pCurr;
      final v2 = pNext - pCurr;
      final dot = v1.dotProduct(v2);
      final l1 = v1.distanceTo(const Point2D(0, 0));
      final l2 = v2.distanceTo(const Point2D(0, 0));
      if (l1 < 1e-4 || l2 < 1e-4) return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Invalid corners');

      final cosAngle = (dot / (l1 * l2)).clamp(-1.0, 1.0);
      final angleDeg = acos(cosAngle) * 180.0 / pi;
      if (angleDeg < 45.0 || angleDeg > 135.0) {
        return const _ValidationResult(isValid: false, confidence: 0.0, message: 'Align sheet rectangle');
      }
    }

    final aspect = quad.aspectRatio;

    // Class 9-10 aspect ratio validation:
    // Full sheet: 1024 / 792 = 1.2929 (portrait H/W, or W/H = 0.7734)
    // Table grid: 924 / 1200 = 0.7700 (or W/H = 1.2987)
    // Permissive range to accommodate phone perspective tilt and angles:
    if (classMode == 'class_9_10') {
      final isMatching910 = (aspect >= 0.55 && aspect <= 0.95) || (aspect >= 1.05 && aspect <= 1.70);
      if (!isMatching910) {
        return const _ValidationResult(
          isValid: false,
          confidence: 0.20,
          message: 'Align Class 9-10 sheet in frame',
        );
      }
    }

    // Compute confidence based on area fill and rectangularity
    final aspectScore = (aspect >= 0.60 && aspect <= 0.85) || (aspect >= 1.25 && aspect <= 1.55) ? 1.0 : 0.75;
    final areaScore = min(1.0, areaRatio / 0.40);
    final confidence = min(0.99, max(0.65, 0.50 + 0.30 * areaScore + 0.20 * aspectScore));

    return _ValidationResult(isValid: true, confidence: confidence, message: 'Document detected');
  }
}

class _DownsampledBuffer {
  final int width;
  final int height;
  final Uint8List data;

  const _DownsampledBuffer({
    required this.width,
    required this.height,
    required this.data,
  });
}

class _ValidationResult {
  final bool isValid;
  final double confidence;
  final String message;

  const _ValidationResult({
    required this.isValid,
    required this.confidence,
    required this.message,
  });
}

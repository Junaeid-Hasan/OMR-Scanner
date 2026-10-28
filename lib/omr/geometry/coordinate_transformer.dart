import 'dart:ui' show Offset, Size;
import 'quadrilateral.dart';

/// Utilities for transforming coordinates between camera frame space,
/// normalized unit space [0, 1], preview screen space, and captured photo space.
class CoordinateTransformer {
  const CoordinateTransformer();

  /// Converts a [Quadrilateral] in pixel coordinates of a source box of size [srcWidth] x [srcHeight]
  /// into a normalized [Quadrilateral] where all coordinates are in the range [0.0, 1.0].
  static Quadrilateral normalizeQuad(Quadrilateral quad, double srcWidth, double srcHeight) {
    if (srcWidth <= 0 || srcHeight <= 0) return quad;
    return Quadrilateral(
      tl: Point2D(quad.tl.x / srcWidth, quad.tl.y / srcHeight),
      tr: Point2D(quad.tr.x / srcWidth, quad.tr.y / srcHeight),
      br: Point2D(quad.br.x / srcWidth, quad.br.y / srcHeight),
      bl: Point2D(quad.bl.x / srcWidth, quad.bl.y / srcHeight),
    );
  }

  /// Denormalizes a [Quadrilateral] in [0.0, 1.0] coordinates to absolute pixel coordinates
  /// on a target canvas of size [targetWidth] x [targetHeight].
  static Quadrilateral denormalizeQuad(Quadrilateral quad, double targetWidth, double targetHeight) {
    return Quadrilateral(
      tl: Point2D(quad.tl.x * targetWidth, quad.tl.y * targetHeight),
      tr: Point2D(quad.tr.x * targetWidth, quad.tr.y * targetHeight),
      br: Point2D(quad.br.x * targetWidth, quad.br.y * targetHeight),
      bl: Point2D(quad.bl.x * targetWidth, quad.bl.y * targetHeight),
    );
  }

  /// Clamps all corners of [quad] within [0.0, 1.0].
  static Quadrilateral clampNormalized(Quadrilateral quad) {
    double clamp01(double v) => v.clamp(0.0, 1.0);
    return Quadrilateral(
      tl: Point2D(clamp01(quad.tl.x), clamp01(quad.tl.y)),
      tr: Point2D(clamp01(quad.tr.x), clamp01(quad.tr.y)),
      br: Point2D(clamp01(quad.br.x), clamp01(quad.br.y)),
      bl: Point2D(clamp01(quad.bl.x), clamp01(quad.bl.y)),
    );
  }

  /// Converts a [Point2D] into a Flutter [Offset].
  static Offset pointToOffset(Point2D p) => Offset(p.x, p.y);

  /// Converts a normalized [Quadrilateral] into a list of 4 Flutter [Offset]s scaled to [viewSize].
  static List<Offset> quadToScreenOffsets(Quadrilateral normalizedQuad, Size viewSize) {
    final w = viewSize.width;
    final h = viewSize.height;
    return [
      Offset(normalizedQuad.tl.x * w, normalizedQuad.tl.y * h),
      Offset(normalizedQuad.tr.x * w, normalizedQuad.tr.y * h),
      Offset(normalizedQuad.br.x * w, normalizedQuad.br.y * h),
      Offset(normalizedQuad.bl.x * w, normalizedQuad.bl.y * h),
    ];
  }
}

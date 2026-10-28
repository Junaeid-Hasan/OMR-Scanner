import 'package:flutter/material.dart';
import '../omr/detection/stability_tracker.dart';
import '../omr/geometry/coordinate_transformer.dart';
import '../omr/geometry/quadrilateral.dart';

/// CamScanner-style live document detection overlay.
///
/// Draws:
/// 1. A darkened translucent scrim outside the detected document polygon
/// 2. Four corner brackets and connecting quadrilateral outline
/// 3. State-reactive color transitions (searching -> detected -> steady -> capturing)
/// 4. Actionable status chip with auto-capture countdown progress
class LiveScanOverlay extends StatelessWidget {
  final Quadrilateral? normalizedQuad;
  final LiveTrackingState trackingState;
  final String statusMessage;
  final double stabilityProgress;
  final bool isCapturing;

  const LiveScanOverlay({
    super.key,
    required this.normalizedQuad,
    required this.trackingState,
    required this.statusMessage,
    required this.stabilityProgress,
    this.isCapturing = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Live Boundary & Scrim Custom Painter
            CustomPaint(
              size: size,
              painter: _LiveScanOverlayPainter(
                normalizedQuad: normalizedQuad,
                trackingState: trackingState,
                stabilityProgress: stabilityProgress,
              ),
            ),

            // 2. Top Status Badge Pill
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Center(
                child: _buildStatusPill(),
              ),
            ),

            // 3. Shutter flash effect during active capture
            if (isCapturing)
              Container(
                color: Colors.white.withValues(alpha: 0.65),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatusPill() {
    Color accentColor;
    IconData iconData;

    switch (trackingState) {
      case LiveTrackingState.searching:
        accentColor = const Color(0xFFFBBF24); // Warm amber
        iconData = Icons.crop_free_rounded;
        break;
      case LiveTrackingState.detected:
        accentColor = const Color(0xFF2DD4BF); // Vibrant cyan/teal
        iconData = Icons.filter_center_focus_rounded;
        break;
      case LiveTrackingState.steady:
      case LiveTrackingState.readyToCapture:
        accentColor = const Color(0xFF10B981); // Emerald green
        iconData = Icons.check_circle_outline_rounded;
        break;
      case LiveTrackingState.capturing:
        accentColor = Colors.white;
        iconData = Icons.camera_alt_rounded;
        break;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.65), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trackingState == LiveTrackingState.steady && stabilityProgress > 0)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: stabilityProgress,
                strokeWidth: 2.5,
                color: accentColor,
                backgroundColor: Colors.white24,
              ),
            )
          else
            Icon(iconData, color: accentColor, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              statusMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveScanOverlayPainter extends CustomPainter {
  final Quadrilateral? normalizedQuad;
  final LiveTrackingState trackingState;
  final double stabilityProgress;

  _LiveScanOverlayPainter({
    required this.normalizedQuad,
    required this.trackingState,
    required this.stabilityProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (normalizedQuad == null || trackingState == LiveTrackingState.searching) {
      // Clean full-screen camera view without any restricting square frame
      return;
    }

    _paintDetectedQuadrilateral(canvas, size, normalizedQuad!);
  }

  /// Draws the tracked live quadrilateral polygon, boundary lines, and corner pins
  void _paintDetectedQuadrilateral(Canvas canvas, Size size, Quadrilateral quad) {
    final offsets = CoordinateTransformer.quadToScreenOffsets(quad, size);
    final tl = offsets[0];
    final tr = offsets[1];
    final br = offsets[2];
    final bl = offsets[3];

    // Document polygon path
    final docPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    // 2. Select theme colors based on state
    Color outlineColor;
    Color cornerColor;
    double strokeWidth;

    if (trackingState == LiveTrackingState.steady || trackingState == LiveTrackingState.readyToCapture) {
      outlineColor = const Color(0xFF10B981); // Emerald green
      cornerColor = const Color(0xFF34D399); // Mint highlight
      strokeWidth = 3.5;
    } else {
      outlineColor = const Color(0xFF2DD4BF); // Vibrant cyan
      cornerColor = Colors.white;
      strokeWidth = 2.5;
    }

    // 3. Document interior subtle highlight tint
    final tintPaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawPath(docPath, tintPaint);

    // 4. Polygon connecting boundary outline
    final linePaint = Paint()
      ..color = outlineColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(docPath, linePaint);

    // 5. Four Corner Anchor Pins (CamScanner circular handles)
    final pinOuterPaint = Paint()
      ..color = cornerColor
      ..style = PaintingStyle.fill;

    final pinInnerPaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.fill;

    for (final pt in offsets) {
      // Outer ring
      canvas.drawCircle(pt, 7.0, pinOuterPaint);
      // Inner dot
      canvas.drawCircle(pt, 3.5, pinInnerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveScanOverlayPainter oldDelegate) {
    return oldDelegate.normalizedQuad != normalizedQuad ||
        oldDelegate.trackingState != trackingState ||
        oldDelegate.stabilityProgress != stabilityProgress;
  }
}

import 'package:flutter/material.dart';

class ScanOverlay extends StatelessWidget {
  final bool isSheetDetected;

  const ScanOverlay({super.key, this.isSheetDetected = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Standard A4 aspect ratio 1.38
        final targetW = w * 0.85;
        final targetH = targetW * 1.38;

        final left = (w - targetW) / 2;
        final top = (h - targetH) / 2;
        final rect = Rect.fromLTWH(left, top, targetW, targetH);

        return CustomPaint(
          size: Size(w, h),
          painter: _ScanOverlayPainter(
            frameRect: rect,
            isDetected: isSheetDetected,
          ),
        );
      },
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final Rect frameRect;
  final bool isDetected;

  _ScanOverlayPainter({required this.frameRect, required this.isDetected});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dark semi-transparent scrim outside alignment frame
    final scrimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.60)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, scrimPaint);

    // 2. Subtle frame bounding line
    final frameBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(16)), frameBorderPaint);

    // 3. Highlighted corner bracket guides
    final cornerColor = isDetected ? const Color(0xFF10B981) : Colors.white;
    final strokePaint = Paint()
      ..color = cornerColor
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const cornerLen = 32.0;

    // Top-Left
    canvas.drawLine(frameRect.topLeft + const Offset(4, 0), frameRect.topLeft + const Offset(cornerLen, 0), strokePaint);
    canvas.drawLine(frameRect.topLeft + const Offset(0, 4), frameRect.topLeft + const Offset(0, cornerLen), strokePaint);

    // Top-Right
    canvas.drawLine(frameRect.topRight - const Offset(4, 0), frameRect.topRight - const Offset(cornerLen, 0), strokePaint);
    canvas.drawLine(frameRect.topRight + const Offset(0, 4), frameRect.topRight + const Offset(0, cornerLen), strokePaint);

    // Bottom-Left
    canvas.drawLine(frameRect.bottomLeft + const Offset(4, 0), frameRect.bottomLeft + const Offset(cornerLen, 0), strokePaint);
    canvas.drawLine(frameRect.bottomLeft - const Offset(0, 4), frameRect.bottomLeft - const Offset(0, cornerLen), strokePaint);

    // Bottom-Right
    canvas.drawLine(frameRect.bottomRight - const Offset(4, 0), frameRect.bottomRight - const Offset(cornerLen, 0), strokePaint);
    canvas.drawLine(frameRect.bottomRight - const Offset(0, 4), frameRect.bottomRight - const Offset(0, cornerLen), strokePaint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return oldDelegate.isDetected != isDetected || oldDelegate.frameRect != frameRect;
  }
}

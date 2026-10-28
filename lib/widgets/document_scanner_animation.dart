import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

class DocumentScanningAnimation extends StatefulWidget {
  final String? imagePath;
  final String? rollNumber;
  final String? examTitle;

  const DocumentScanningAnimation({
    super.key,
    this.imagePath,
    this.rollNumber,
    this.examTitle,
  });

  @override
  State<DocumentScanningAnimation> createState() => _DocumentScanningAnimationState();
}

class _DocumentScanningAnimationState extends State<DocumentScanningAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _beamController;
  late Animation<double> _beamAnimation;
  int _messageIndex = 0;
  Timer? _messageTimer;

  final List<String> _statusMessages = [
    'Aligning OMR Sheet Corners...',
    'Rectifying Perspective & Lighting...',
    'Analyzing Bubble Fill Densities...',
    'Extracting Student Responses...',
  ];

  @override
  void initState() {
    super.initState();
    _beamController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _beamAnimation = CurvedAnimation(
      parent: _beamController,
      curve: Curves.easeInOut,
    );

    _messageTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _statusMessages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _beamController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValidImage = widget.imagePath != null &&
        File(widget.imagePath!).existsSync() &&
        widget.imagePath!.isNotEmpty;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF334155), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scanner Frame with Laser
            SizedBox(
              height: 220,
              width: 170,
              child: Stack(
                children: [
                  // Document background
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF475569), width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasValidImage
                        ? Opacity(
                            opacity: 0.5,
                            child: Image.file(
                              File(widget.imagePath!),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          )
                        : _buildMockOMRSheet(),
                  ),

                  // Scanner Corner Reticles
                  const Positioned(
                    top: 6,
                    left: 6,
                    child: _CornerBracket(isTop: true, isLeft: true),
                  ),
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: _CornerBracket(isTop: true, isLeft: false),
                  ),
                  const Positioned(
                    bottom: 6,
                    left: 6,
                    child: _CornerBracket(isTop: false, isLeft: true),
                  ),
                  const Positioned(
                    bottom: 6,
                    right: 6,
                    child: _CornerBracket(isTop: false, isLeft: false),
                  ),

                  // Animated Sweeping Laser Beam
                  AnimatedBuilder(
                    animation: _beamAnimation,
                    builder: (context, child) {
                      final topPos = _beamAnimation.value * 200.0;
                      return Positioned(
                        top: topPos,
                        left: 2,
                        right: 2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Upward laser glow
                            Container(
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFF2DD4BF).withValues(alpha: 0.35),
                                  ],
                                ),
                              ),
                            ),
                            // Laser line
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: const Color(0xFF5EEAD4),
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2DD4BF).withValues(alpha: 0.9),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.6),
                                    blurRadius: 14,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                            // Downward laser glow
                            Container(
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(0xFF2DD4BF).withValues(alpha: 0.35),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Roll Number & Exam Pill (if available)
            if (widget.rollNumber != null && widget.rollNumber!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF312E81),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, color: Color(0xFFA5B4FC), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Roll: ${widget.rollNumber}',
                      style: const TextStyle(
                        color: Color(0xFFE0E7FF),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Dynamic Status Message
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _statusMessages[_messageIndex],
                key: ValueKey<int>(_messageIndex),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt_rounded, color: Color(0xFF2DD4BF), size: 14),
                SizedBox(width: 4),
                Text(
                  'Pure On-Device Computer Vision',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMockOMRSheet() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 6,
            width: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF64748B),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 8,
              ),
              itemCount: 28,
              itemBuilder: (context, index) {
                final isFilled = (index * 7) % 5 == 0;
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? const Color(0xFF475569) : Colors.transparent,
                    border: Border.all(
                      color: isFilled ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                      width: 1.2,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerBracket extends StatelessWidget {
  final bool isTop;
  final bool isLeft;

  const _CornerBracket({required this.isTop, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    const size = 14.0;
    const thickness = 2.5;
    const color = Color(0xFF2DD4BF);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BracketPainter(
          isTop: isTop,
          isLeft: isLeft,
          thickness: thickness,
          color: color,
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;
  final double thickness;
  final Color color;

  _BracketPainter({
    required this.isTop,
    required this.isLeft,
    required this.thickness,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final x = isLeft ? 0.0 : size.width;
    final y = isTop ? 0.0 : size.height;
    final dx = isLeft ? size.width : 0.0;
    final dy = isTop ? size.height : 0.0;

    path.moveTo(dx, y);
    path.lineTo(x, y);
    path.lineTo(x, dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

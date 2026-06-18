import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/app_haptics.dart';

class SpeedConsolePanel extends StatefulWidget {
  final double speedKmph;
  final bool hazardEnabled;
  final bool leftArrowActive;
  final bool rightArrowActive;
  final bool controlsEnabled;
  final VoidCallback onHazardTap;
  final VoidCallback onLeftArrowTap;
  final VoidCallback onRightArrowTap;
  final bool liteMode;

  const SpeedConsolePanel({
    super.key,
    required this.speedKmph,
    required this.hazardEnabled,
    required this.leftArrowActive,
    required this.rightArrowActive,
    required this.controlsEnabled,
    required this.onHazardTap,
    required this.onLeftArrowTap,
    required this.onRightArrowTap,
    this.liteMode = false,
  });

  @override
  State<SpeedConsolePanel> createState() => _SpeedConsolePanelState();
}

class _SpeedConsolePanelState extends State<SpeedConsolePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;

  bool get _hasActiveArrow => widget.leftArrowActive || widget.rightArrowActive;

  bool get _shouldAnimateArrows => _hasActiveArrow && !widget.liteMode;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _syncBlinkController();
  }

  @override
  void didUpdateWidget(covariant SpeedConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.leftArrowActive != widget.leftArrowActive ||
        oldWidget.rightArrowActive != widget.rightArrowActive ||
        oldWidget.liteMode != widget.liteMode) {
      _syncBlinkController();
    }
  }

  void _syncBlinkController() {
    if (_shouldAnimateArrows) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat();
      }
    } else {
      _blinkController.stop();
      _blinkController.value = 0;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _handleLeftArrowTap() {
    AppHaptics.selectionClick();
    widget.onLeftArrowTap();
  }

  void _handleRightArrowTap() {
    AppHaptics.selectionClick();
    widget.onRightArrowTap();
  }

  void _handleHazardTap() {
    AppHaptics.mediumImpact();
    widget.onHazardTap();
  }

  Widget _buildPanelContent(bool blinkOn) {
    return CustomPaint(
      foregroundPainter: DashboardPanelBorderPainter(),
      child: Container(
        height: 145,
        decoration: BoxDecoration(
          color: widget.liteMode
              ? const Color(0xFF121212)
              : const Color(0xFF151515).withValues(alpha: 0.12),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.controlsEnabled ? _handleLeftArrowTap : null,
                  child: Center(
                    child: _IndicatorIcon(
                      icon: Icons.arrow_back,
                      isActive: widget.leftArrowActive,
                      isVisible: widget.leftArrowActive && blinkOn,
                      liteMode: widget.liteMode,
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleHazardTap,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.speedKmph.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -14),
                        child: const Text(
                          "km/h",
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.controlsEnabled ? _handleRightArrowTap : null,
                  child: Center(
                    child: _IndicatorIcon(
                      icon: Icons.arrow_forward,
                      isActive: widget.rightArrowActive,
                      isVisible: widget.rightArrowActive && blinkOn,
                      liteMode: widget.liteMode,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hazardTapHandler = _handleHazardTap;

    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, child) {
        final blinkOn =
            widget.liteMode ||
            !_hasActiveArrow ||
            _blinkController.value < 0.55;

        return SizedBox(
          height: 150,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: ClipPath(
                  clipper: DashboardPanelClipper(),
                  child: Container(
                    height: 132,
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipPath(
                  clipper: DashboardPanelClipper(),
                  child: widget.liteMode
                      ? _buildPanelContent(blinkOn)
                      : BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: _buildPanelContent(blinkOn),
                        ),
                ),
              ),
              Positioned(
                bottom: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: hazardTapHandler,
                  child: _HazardIcon(
                    isActive: widget.hazardEnabled,
                    liteMode: widget.liteMode,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IndicatorIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isVisible;
  final bool liteMode;

  const _IndicatorIcon({
    required this.icon,
    required this.isActive,
    required this.isVisible,
    required this.liteMode,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft = icon == Icons.arrow_back;

    return SizedBox(
      width: 48,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isVisible && !liteMode)
            CustomPaint(
              size: const Size(40, 34),
              painter: _LongArrowPainter(
                isLeft: isLeft,
                color: Colors.greenAccent.withValues(alpha: 0.34),
                strokeWidth: 12,
                blurRadius: 16,
              ),
            ),
          if (isVisible && !liteMode)
            CustomPaint(
              size: const Size(40, 34),
              painter: _LongArrowPainter(
                isLeft: isLeft,
                color: Colors.greenAccent.withValues(alpha: 0.60),
                strokeWidth: 7,
                blurRadius: 7,
              ),
            ),
          CustomPaint(
            size: const Size(40, 34),
            painter: _LongArrowPainter(
              isLeft: isLeft,
              color: isVisible ? Colors.greenAccent : Colors.white24,
              strokeWidth: isActive ? 4.5 : 3.4,
              blurRadius: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LongArrowPainter extends CustomPainter {
  final bool isLeft;
  final Color color;
  final double strokeWidth;
  final double blurRadius;

  const _LongArrowPainter({
    required this.isLeft,
    required this.color,
    required this.strokeWidth,
    required this.blurRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (blurRadius > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);
    }

    final path = Path();

    if (isLeft) {
      final tip = Offset(size.width * 0.12, centerY);
      final tailEnd = Offset(size.width * 0.88, centerY);
      final headTop = Offset(size.width * 0.36, size.height * 0.24);
      final headBottom = Offset(size.width * 0.36, size.height * 0.76);

      path.moveTo(tailEnd.dx, tailEnd.dy);
      path.lineTo(tip.dx, tip.dy);

      path.moveTo(tip.dx, tip.dy);
      path.lineTo(headTop.dx, headTop.dy);

      path.moveTo(tip.dx, tip.dy);
      path.lineTo(headBottom.dx, headBottom.dy);
    } else {
      final tip = Offset(size.width * 0.88, centerY);
      final tailEnd = Offset(size.width * 0.12, centerY);
      final headTop = Offset(size.width * 0.64, size.height * 0.24);
      final headBottom = Offset(size.width * 0.64, size.height * 0.76);

      path.moveTo(tailEnd.dx, tailEnd.dy);
      path.lineTo(tip.dx, tip.dy);

      path.moveTo(tip.dx, tip.dy);
      path.lineTo(headTop.dx, headTop.dy);

      path.moveTo(tip.dx, tip.dy);
      path.lineTo(headBottom.dx, headBottom.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LongArrowPainter oldDelegate) {
    return oldDelegate.isLeft != isLeft ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.blurRadius != blurRadius;
  }
}

class _HazardIcon extends StatelessWidget {
  final bool isActive;
  final bool liteMode;

  const _HazardIcon({required this.isActive, required this.liteMode});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isActive && !liteMode)
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent.withValues(alpha: 0.30),
              size: 54,
              shadows: [
                Shadow(
                  color: Colors.redAccent.withValues(alpha: 0.55),
                  blurRadius: 26,
                ),
              ],
            ),
          if (isActive && !liteMode)
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent.withValues(alpha: 0.58),
              size: 42,
              shadows: [
                Shadow(
                  color: Colors.redAccent.withValues(alpha: 0.70),
                  blurRadius: 16,
                ),
              ],
            ),
          Icon(
            Icons.warning_amber_rounded,
            color: isActive ? Colors.redAccent : Colors.white24,
            size: isActive ? 34 : 30,
          ),
        ],
      ),
    );
  }
}

class DashboardPanelBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = DashboardPanelPathBuilder.build(size);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DashboardPanelClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return DashboardPanelPathBuilder.build(size);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class DashboardPanelPathBuilder {
  static Path build(Size size) {
    const radius = 28.0;
    const notchDepth = 30.0;
    const notchRound = 10.0;
    const notchSideRound = 0.22;

    final bodyBottom = size.height - notchDepth;

    final notchTopLeft = size.width * 0.28;
    final notchBottomLeft = size.width * 0.40;
    final notchBottomRight = size.width * 0.60;
    final notchTopRight = size.width * 0.72;

    final topRight = Offset(notchTopRight, bodyBottom);
    final bottomRight = Offset(notchBottomRight, size.height);
    final bottomLeft = Offset(notchBottomLeft, size.height);
    final topLeft = Offset(notchTopLeft, bodyBottom);

    final topRightExit = Offset.lerp(topRight, bottomRight, notchSideRound)!;

    final bottomRightEntry = Offset.lerp(
      bottomRight,
      topRight,
      notchSideRound,
    )!;

    final bottomLeftExit = Offset.lerp(bottomLeft, topLeft, notchSideRound)!;

    final topLeftEntry = Offset.lerp(topLeft, bottomLeft, notchSideRound)!;

    final path = Path();

    path.moveTo(radius, 0);

    path.lineTo(size.width - radius, 0);

    path.quadraticBezierTo(size.width, 0, size.width, radius);

    path.lineTo(size.width, bodyBottom - radius);

    path.quadraticBezierTo(
      size.width,
      bodyBottom,
      size.width - radius,
      bodyBottom,
    );

    path.lineTo(notchTopRight + notchRound, bodyBottom);

    path.quadraticBezierTo(
      topRight.dx,
      topRight.dy,
      topRightExit.dx,
      topRightExit.dy,
    );

    path.lineTo(bottomRightEntry.dx, bottomRightEntry.dy);

    path.quadraticBezierTo(
      bottomRight.dx,
      bottomRight.dy,
      notchBottomRight - notchRound,
      size.height,
    );

    path.lineTo(notchBottomLeft + notchRound, size.height);

    path.quadraticBezierTo(
      bottomLeft.dx,
      bottomLeft.dy,
      bottomLeftExit.dx,
      bottomLeftExit.dy,
    );

    path.lineTo(topLeftEntry.dx, topLeftEntry.dy);

    path.quadraticBezierTo(
      topLeft.dx,
      topLeft.dy,
      notchTopLeft - notchRound,
      bodyBottom,
    );

    path.lineTo(radius, bodyBottom);

    path.quadraticBezierTo(0, bodyBottom, 0, bodyBottom - radius);

    path.lineTo(0, radius);

    path.quadraticBezierTo(0, 0, radius, 0);

    path.close();

    return path;
  }
}

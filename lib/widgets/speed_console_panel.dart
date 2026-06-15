import 'dart:ui';

import 'package:flutter/material.dart';
import '../bike_data.dart';

class SpeedConsolePanel extends StatelessWidget {
  final BikeData bike;

  const SpeedConsolePanel({super.key, required this.bike});

  @override
  Widget build(BuildContext context) {
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
                color: Colors.black.withValues(alpha: 0.42),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: DashboardPanelClipper(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: CustomPaint(
                  foregroundPainter: DashboardPanelBorderPainter(),
                  child: Container(
                    height: 145,
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818).withValues(alpha: 0.72),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 30),
                      child: Row(
                        children: [
                          Expanded(
                            child: Center(
                              child: _IndicatorIcon(
                                icon: Icons.arrow_back,
                                isActive: bike.leftIndicator,
                              ),
                            ),
                          ),

                          Container(
                            width: 1,
                            height: 56,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),

                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "${bike.speed ?? 0}",
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
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Container(
                            width: 1,
                            height: 56,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),

                          Expanded(
                            child: Center(
                              child: _IndicatorIcon(
                                icon: Icons.arrow_forward,
                                isActive: bike.rightIndicator,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 14,
            child: Icon(
              Icons.warning_amber_rounded,
              color: bike.hazard ? Colors.redAccent : Colors.white24,
              size: 30,
              shadows: bike.hazard
                  ? [
                      Shadow(
                        color: Colors.redAccent.withValues(alpha: 0.75),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _IndicatorIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;

  const _IndicatorIcon({required this.icon, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      color: isActive ? Colors.greenAccent : Colors.white24,
      size: 36,
      shadows: isActive
          ? [
              Shadow(
                color: Colors.greenAccent.withValues(alpha: 0.75),
                blurRadius: 16,
              ),
            ]
          : null,
    );
  }
}

class DashboardPanelBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = DashboardPanelPathBuilder.build(size);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
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
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
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
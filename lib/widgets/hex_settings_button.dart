import 'package:flutter/material.dart';
import 'dart:math';

class HexSettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const HexSettingsButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: CustomPaint(
          painter: _HexSettingsPainter(),
        ),
      ),
    );
  }
}

class _HexSettingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.40;

    final hexPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    final path = Path();

    for (int i = 0; i < 6; i++) {
      final angle = (pi / 3 * i) - (pi / 6);
      final point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    path.close();

    canvas.drawPath(path, hexPaint);
    canvas.drawCircle(center, 3.2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
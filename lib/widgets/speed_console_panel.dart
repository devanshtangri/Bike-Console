import 'package:flutter/material.dart';
import '../bike_data.dart';

class SpeedConsolePanel extends StatelessWidget {
  final BikeData bike;

  const SpeedConsolePanel({
    super.key,
    required this.bike,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: DashboardPanelClipper(),
              child: Container(
                height: 145,
                color: const Color(0xFF181818),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Icon(
                            Icons.arrow_back,
                            color: bike.leftIndicator
                                ? Colors.greenAccent
                                : Colors.white24,
                            size: 36,
                          ),
                        ),
                      ),

                      Container(width: 1, height: 56, color: Colors.white10),

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

                      Container(width: 1, height: 56, color: Colors.white10),

                      Expanded(
                        child: Center(
                          child: Icon(
                            Icons.arrow_forward,
                            color: bike.rightIndicator
                                ? Colors.greenAccent
                                : Colors.white24,
                            size: 36,
                          ),
                        ),
                      ),
                    ],
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
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardPanelClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
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

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
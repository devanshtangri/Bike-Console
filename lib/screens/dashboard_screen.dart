import 'package:flutter/material.dart';
import '../bike_data.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final VoidCallback bikeListener;

  @override
  void initState() {
    super.initState();

    bikeListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    BikeData.instance.addListener(bikeListener);
  }

  @override
  Widget build(BuildContext context) {
    final bike = BikeData.instance;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Bike Console",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(
              height: screenHeight * 0.42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: const GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(28.6139, 77.2090),
                          zoom: 15,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: false,
                      ),
                    ),
                  ),

                  Positioned(
                    left: screenWidth * 0.03,
                    right: screenWidth * 0.03,
                    bottom: 10,
                    child: _speedPanel(bike),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          "TOTAL DISTANCE",
                          "${bike.distance?.toStringAsFixed(2) ?? "0.00"} km",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard("RPM", "${bike.rpm ?? 0}")),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          "AVERAGE SPEED",
                          "${bike.avgSpeed?.toStringAsFixed(1) ?? "0.0"} km/h",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          "MAX SPEED",
                          "${bike.maxSpeed ?? 0} km/h",
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Container(
                    height: 78,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white),

                        const SizedBox(width: 12),

                        const Text(
                          "2:15:02",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const Spacer(),

                        Container(width: 1, height: 40, color: Colors.white10),

                        const SizedBox(width: 20),

                        Container(
                          width: screenWidth * 0.38,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Center(
                            child: Text(
                              "Pause",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedPanel(BikeData bike) {
    return SizedBox(
      height: 180,
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
                height: 175,
                color: const Color(0xFF181818),
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

                    Container(width: 1, height: 60, color: Colors.white10),

                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${bike.speed ?? 0}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 60,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          Transform.translate(
                            offset: const Offset(0, -16),
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

                    Container(width: 1, height: 60, color: Colors.white10),

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

          Positioned(
            bottom: 22,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                shape: BoxShape.circle,
                border: Border.all(
                  color: bike.hazard ? Colors.redAccent : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: bike.hazard ? Colors.redAccent : Colors.white38,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w500,
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
    const radius = 32.0;
    const notchDepth = 40.0;

    final bodyBottom = size.height - notchDepth;

    final notchTopLeft = size.width * 0.22;
    final notchBottomLeft = size.width * 0.34;
    final notchBottomRight = size.width * 0.66;
    final notchTopRight = size.width * 0.78;

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

    const curve = 0;

    path.lineTo(notchTopRight + curve, bodyBottom);

    path.cubicTo(
      notchTopRight,
      bodyBottom,
      notchTopRight,
      bodyBottom,
      notchTopRight - curve,
      bodyBottom + curve,
    );

    path.lineTo(notchBottomRight + curve, size.height - curve);

    path.cubicTo(
      notchBottomRight,
      size.height,
      notchBottomRight,
      size.height,
      notchBottomRight - curve,
      size.height,
    );

    path.lineTo(notchBottomLeft + curve, size.height);

    path.cubicTo(
      notchBottomLeft,
      size.height,
      notchBottomLeft,
      size.height,
      notchBottomLeft - curve,
      size.height - curve,
    );

    path.lineTo(notchTopLeft + curve, bodyBottom + curve);

    path.cubicTo(
      notchTopLeft,
      bodyBottom,
      notchTopLeft,
      bodyBottom,
      notchTopLeft - curve,
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

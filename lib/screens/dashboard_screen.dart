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

    print("Screen width: $screenWidth");

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

                  const SizedBox(height: 12),

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
    return Container(
      height: 145,
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
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
                    const Text(
                      "km/h",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
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
          const SizedBox(height: 12),
          Icon(
            Icons.warning_amber_rounded,
            color: bike.hazard ? Colors.redAccent : Colors.white24,
            size: 34,
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

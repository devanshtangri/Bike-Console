import 'package:flutter/material.dart';
import '../bike_data.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'settings_screen.dart';
import '../widgets/speed_console_panel.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/ride_control_bar.dart';

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
                    child: SpeedConsolePanel(bike: bike),
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
                        child: DashboardStatCard(
                          title: "DISTANCE",
                          value:
                              "${bike.distance?.toStringAsFixed(2) ?? "0.00"} km",
                          icon: Icons.route_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DashboardStatCard(
                          title: "RPM",
                          value: "${bike.rpm ?? 0}",
                          icon: Icons.sync_outlined,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: DashboardStatCard(
                          title: "AVG SPEED",
                          value:
                              "${bike.avgSpeed?.toStringAsFixed(1) ?? "0.0"} km/h",
                          icon: Icons.speed_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DashboardStatCard(
                          title: "MAX SPEED",
                          value: "${bike.maxSpeed ?? 0} km/h",
                          icon: Icons.trending_up_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  RideControlBar(screenWidth: screenWidth),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../bike_data.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'settings_screen.dart';
import '../widgets/speed_console_panel.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/ride_control_bar.dart';
import '../widgets/hex_settings_button.dart';

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

                  HexSettingsButton(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bodyHeight = constraints.maxHeight;

                  const rideBottom = 16.0;
                  const rideHeight = 78.0;
                  const gapRideToStats = 16.0;

                  const statCardHeight = 96.0;
                  const statRowGap = 12.0;
                  const statsHeight = (statCardHeight * 2) + statRowGap;

                  const gapMapToStats = 18.0;
                  const speedPanelHeight = 150.0;

                  final statsBottom = rideBottom + rideHeight + gapRideToStats;

                  final mapHeight =
                      bodyHeight - statsBottom - statsHeight - gapMapToStats;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0,
                        left: 12,
                        right: 12,
                        height: mapHeight,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(28.6139, 77.2090),
                              zoom: 15,
                            ),
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            zoomControlsEnabled: false,
                            padding: const EdgeInsets.only(bottom: 115),
                          ),
                        ),
                      ),

                      Positioned(
                        top: mapHeight - 135,
                        left: 12,
                        right: 12,
                        height: 135,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.0),
                                  Colors.black.withValues(alpha: 0.55),
                                  Colors.black,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        left: screenWidth * 0.03,
                        right: screenWidth * 0.03,
                        top: mapHeight - speedPanelHeight,
                        child: SpeedConsolePanel(bike: bike),
                      ),

                      Positioned(
                        left: screenWidth * 0.04,
                        right: screenWidth * 0.04,
                        bottom: statsBottom,
                        height: statsHeight,
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
                                    icon: Icons.rotate_right_outlined,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: statRowGap),

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
                          ],
                        ),
                      ),

                      Positioned(
                        left: screenWidth * 0.04,
                        right: screenWidth * 0.04,
                        bottom: rideBottom,
                        child: const RideControlBar(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../bike_data.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'settings_screen.dart';
import '../widgets/speed_console_panel.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/ride_control_bar.dart';
import '../widgets/hex_settings_button.dart';
import '../map_styles/dark_map_style.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final VoidCallback bikeListener;

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;

  LatLng? _currentLatLng;
  double _currentHeading = 0;
  bool _hasCenteredOnStartup = false;

  BitmapDescriptor? _currentLocationIcon;
  final List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();

    bikeListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    BikeData.instance.addListener(bikeListener);
    _startLocationTracking();
  }

  @override
  void dispose() {
    BikeData.instance.removeListener(bikeListener);
    _positionSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> _centerOnCurrentLocation() async {
    final hasPermission = await _ensureLocationPermission();

    if (!hasPermission) {
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    final target = LatLng(position.latitude, position.longitude);

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16, bearing: 0, tilt: 0),
      ),
    );
  }

  Future<void> _startLocationTracking() async {
    final hasPermission = await _ensureLocationPermission();

    if (!hasPermission) {
      return;
    }

    _currentLocationIcon = await _createCurrentLocationIcon();

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
          ),
        ).listen((position) async {
          final nextPoint = LatLng(position.latitude, position.longitude);

          setState(() {
            _currentLatLng = nextPoint;

            if (position.heading >= 0) {
              _currentHeading = position.heading;
            }

            if (_routePoints.isEmpty || _routePoints.last != nextPoint) {
              _routePoints.add(nextPoint);
            }
          });

          if (!_hasCenteredOnStartup && _mapController != null) {
            _hasCenteredOnStartup = true;

            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: nextPoint,
                  zoom: 16,
                  bearing: 0,
                  tilt: 0,
                ),
              ),
            );
          }
        });
  }

  Set<Marker> _buildCurrentLocationMarkers() {
    if (_currentLatLng == null) {
      return {};
    }

    return {
      Marker(
        markerId: const MarkerId("current_location"),
        position: _currentLatLng!,
        icon:
            _currentLocationIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
        rotation: _currentHeading,
        flat: true,
        zIndexInt: 10,
      ),
    };
  }

  Set<Polyline> _buildRoutePolylines() {
    if (_routePoints.length < 2) {
      return {};
    }

    return {
      Polyline(
        polylineId: const PolylineId("ride_trail"),
        points: _routePoints,
        color: const Color(0xFF23C48E),
        width: 5,
        zIndex: 5,
        geodesic: true,
      ),
    };
  }

  Future<BitmapDescriptor> _createCurrentLocationIcon() async {
    const size = 48.0;
    const center = Offset(size / 2, size / 2);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final bodyPaint = Paint()
      ..color = const Color(0xFF23C48E)
      ..style = PaintingStyle.fill;

    final pointerPath = Path()
      ..moveTo(center.dx, 6)
      ..cubicTo(
        center.dx - 5,
        center.dy - 2,
        center.dx - 11,
        center.dy + 9,
        center.dx - 14,
        center.dy + 18,
      )
      ..cubicTo(
        center.dx - 6,
        center.dy + 13,
        center.dx + 6,
        center.dy + 13,
        center.dx + 14,
        center.dy + 18,
      )
      ..cubicTo(
        center.dx + 11,
        center.dy + 9,
        center.dx + 5,
        center.dy - 2,
        center.dx,
        6,
      )
      ..close();

    canvas.drawPath(pointerPath, bodyPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    final bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(bytes);
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
                            initialCameraPosition: const CameraPosition(
                              target: LatLng(28.6139, 77.2090),
                              zoom: 15,
                            ),
                            onMapCreated: (controller) async {
                              _mapController = controller;

                              if (_currentLatLng != null &&
                                  !_hasCenteredOnStartup) {
                                _hasCenteredOnStartup = true;

                                await _mapController!.animateCamera(
                                  CameraUpdate.newCameraPosition(
                                    CameraPosition(
                                      target: _currentLatLng!,
                                      zoom: 16,
                                      bearing: 0,
                                      tilt: 0,
                                    ),
                                  ),
                                );
                              }
                            },
                            style: darkMapStyle,
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            compassEnabled: false,
                            rotateGesturesEnabled: false,
                            tiltGesturesEnabled: false,
                            padding: const EdgeInsets.only(bottom: 115),
                            markers: _buildCurrentLocationMarkers(),
                            polylines: _buildRoutePolylines(),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        right: 26,
                        child: GestureDetector(
                          onTap: _centerOnCurrentLocation,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF181818,
                                  ).withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.my_location_rounded,
                                  color: Colors.greenAccent,
                                  size: 25,
                                ),
                              ),
                            ),
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

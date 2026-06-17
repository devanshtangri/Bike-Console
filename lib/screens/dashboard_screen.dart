import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../bike_data.dart';
import '../controllers/map_tracking_controller.dart';
import '../controllers/bike_console_controller.dart';
import '../models/ride_models.dart';
import '../map_styles/dark_map_style.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/hex_settings_button.dart';
import '../widgets/ride_control_bar.dart';
import '../widgets/speed_console_panel.dart';
import 'settings_screen.dart';
import 'sessions_screen.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.bikeConsoleController});

  final BikeConsoleController bikeConsoleController;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final VoidCallback bikeListener;
  late final MapTrackingController _mapTrackingController;
  late final AnimationController _recenterPulseController;
  late final Animation<double> _recenterPulseAnimation;

  int? _countdownValue;
  bool _debugLeftPhysical = false;
  bool _debugRightPhysical = false;
  bool _debugMoving = true;
  Timer? _debugMovingPacketTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    bikeListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    _recenterPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _recenterPulseAnimation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _recenterPulseController,
        curve: Curves.easeInOut,
      ),
    );
    _mapTrackingController = MapTrackingController();
    _mapTrackingController.addListener(_onMapTrackingChanged);
    _mapTrackingController.initialize();

    BikeData.instance.addListener(bikeListener);
    widget.bikeConsoleController.addListener(bikeListener);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    BikeData.instance.removeListener(bikeListener);
    widget.bikeConsoleController.removeListener(bikeListener);

    _mapTrackingController.removeListener(_onMapTrackingChanged);
    _mapTrackingController.dispose();
    _debugMovingPacketTimer?.cancel();
    _recenterPulseController.dispose();

    super.dispose();
  }

  void _onMapTrackingChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startRideWithCountdown() async {
    final rideController = widget.bikeConsoleController.rideSessionController;

    if (!rideController.canStartRide) return;

    rideController.beginCountdown();

    for (final value in [3, 2, 1]) {
      if (!mounted) return;

      setState(() {
        _countdownValue = value;
      });

      await Future.delayed(const Duration(milliseconds: 800));
    }

    if (!mounted) return;

    setState(() {
      _countdownValue = null;
    });

    rideController.finishCountdownAndStartRide();
  }

  void _injectDebugBikeData() {
    HapticFeedback.mediumImpact();
    _debugMoving = true;
    _debugMovingPacketTimer?.cancel();

    _debugLeftPhysical = false;
    _debugRightPhysical = false;

    widget.bikeConsoleController.connectionController.setConnectionState(
      ConsoleConnectionState.connected,
    );

    widget.bikeConsoleController.injectDebugSensorPacket(
      rpm: 90,
      distanceKm: 0.25,
      isMoving: true,
      leftPhysical: _debugLeftPhysical,
      rightPhysical: _debugRightPhysical,
      hazardOutput: false,
      consoleRideActive: true,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Debug packet injected: 90 RPM, no indicators"),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleDebugPhysicalIndicator({required bool leftSide}) {
    HapticFeedback.selectionClick();

    widget.bikeConsoleController.connectionController.setConnectionState(
      ConsoleConnectionState.connected,
    );

    setState(() {
      if (leftSide) {
        _debugLeftPhysical = !_debugLeftPhysical;
      } else {
        _debugRightPhysical = !_debugRightPhysical;
      }
    });

    widget.bikeConsoleController.injectDebugSensorPacket(
      rpm: 90,
      distanceKm: 0.25,
      isMoving: true,
      leftPhysical: _debugLeftPhysical,
      rightPhysical: _debugRightPhysical,
      hazardOutput: false,
      consoleRideActive: true,
    );

    final message = leftSide
        ? "Debug left physical indicator: ${_debugLeftPhysical ? "ON" : "OFF"}"
        : "Debug right physical indicator: ${_debugRightPhysical ? "ON" : "OFF"}";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleDebugMovingPacket() {
    HapticFeedback.selectionClick();

    widget.bikeConsoleController.connectionController.setConnectionState(
      ConsoleConnectionState.connected,
    );

    setState(() {
      _debugMoving = !_debugMoving;
    });

    _debugMovingPacketTimer?.cancel();

    if (_debugMoving) {
      _sendDebugMovingPacket(isMoving: true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Debug motion: moving TRUE"),
          duration: Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    _sendDebugMovingPacket(isMoving: false);

    _debugMovingPacketTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final rideState =
          widget.bikeConsoleController.rideSessionController.state;

      if (rideState.rideState == RideState.stopped) {
        _debugMovingPacketTimer?.cancel();
        return;
      }

      _sendDebugMovingPacket(isMoving: false);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Debug motion: moving FALSE packets started"),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _sendDebugMovingPacket({required bool isMoving}) {
    final rideState = widget.bikeConsoleController.rideSessionController.state;

    widget.bikeConsoleController.injectDebugSensorPacket(
      rpm: isMoving ? 90 : 0,
      distanceKm: rideState.distanceKm > 0 ? rideState.distanceKm : 0.25,
      isMoving: isMoving,
      leftPhysical: _debugLeftPhysical,
      rightPhysical: _debugRightPhysical,
      hazardOutput: rideState.hazardEnabled,
      consoleRideActive: rideState.isRideActive,
    );
  }

  void _injectDebugDisconnect() {
    HapticFeedback.mediumImpact();

    _debugMovingPacketTimer?.cancel();
    _debugMoving = true;

    widget.bikeConsoleController.connectionController.setConnectionState(
      ConsoleConnectionState.disconnected,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Debug disconnect injected"),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatSpeedStat(double value) {
    if (value > 99.9) {
      return "${value.toStringAsFixed(0)} km/h";
    }

    return "${value.toStringAsFixed(1)} km/h";
  }

  String _formatDistanceStat(double value) {
    if (value > 99.99) {
      return "${value.toStringAsFixed(1)} km";
    }

    return "${value.toStringAsFixed(2)} km";
  }

  bool _isBikeDeviceConnected() {
    return widget.bikeConsoleController.connectionController.isConnected;
  }

  Widget _buildDeviceConnectedBadge() {
    final isConnected = _isBikeDeviceConnected();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: isConnected ? _injectDebugDisconnect : null,
      child: AnimatedScale(
        scale: isConnected ? 1 : 0.86,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isConnected ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.memory_rounded,
              color: AppColors.premiumGreen,
              size: 25,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecenterButtonContent() {
    final liteMode =
        widget.bikeConsoleController.displaySettings.liteModeEnabled;
    final recenterEnabled = _mapTrackingController.followModeEnabled;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: liteMode
            ? const Color(0xFF181818)
            : const Color(0xFF181818).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: liteMode ? 0.09 : 0.12),
          width: 1,
        ),
      ),
      child: liteMode
          ? Icon(
              Icons.my_location_rounded,
              color: recenterEnabled ? AppColors.premiumGreen : Colors.white70,
              size: 25,
            )
          : AnimatedBuilder(
              animation: _recenterPulseAnimation,
              builder: (context, child) {
                return Icon(
                  Icons.my_location_rounded,
                  color: recenterEnabled
                      ? AppColors.premiumGreen.withValues(
                          alpha: _recenterPulseAnimation.value,
                        )
                      : Colors.white70,
                  size: 25,
                );
              },
            ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mapTrackingController.markAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideState = widget.bikeConsoleController.rideSessionController.state;
    final isConsoleConnected =
        widget.bikeConsoleController.connectionController.isConnected;
    final screenWidth = MediaQuery.of(context).size.width;
    final liteMode =
        widget.bikeConsoleController.displaySettings.liteModeEnabled;

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
                  GestureDetector(
                    onLongPress: _injectDebugBikeData,
                    child: const Text(
                      "Bike Console",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HeaderSessionsButton(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SessionsScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      HexSettingsButton(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                bikeConsoleController:
                                    widget.bikeConsoleController,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
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
                            onMapCreated: (controller) {
                              _mapTrackingController.attachMapController(
                                controller,
                              );
                            },
                            style: darkMapStyle,
                            onCameraMoveStarted: () {
                              _mapTrackingController.onUserMovedMap();
                            },
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            compassEnabled: false,
                            rotateGesturesEnabled: false,
                            tiltGesturesEnabled: false,
                            padding: const EdgeInsets.only(bottom: 115),
                            markers: _mapTrackingController.markers,
                            polylines: _mapTrackingController.polylines,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        left: 26,
                        child: _buildDeviceConnectedBadge(),
                      ),
                      Positioned(
                        top: 14,
                        right: 26,
                        child: GestureDetector(
                          onTap: _mapTrackingController.recenter,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: liteMode
                                ? _buildRecenterButtonContent()
                                : BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 18,
                                      sigmaY: 18,
                                    ),
                                    child: _buildRecenterButtonContent(),
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
                        child: SpeedConsolePanel(
                          speedKmph: rideState.currentSpeedKmph,
                          hazardEnabled:
                              isConsoleConnected && rideState.hazardEnabled,
                          leftArrowActive:
                              isConsoleConnected && rideState.leftArrowActive,
                          rightArrowActive:
                              isConsoleConnected && rideState.rightArrowActive,
                          controlsEnabled: isConsoleConnected,
                          onHazardTap: widget
                              .bikeConsoleController
                              .rideSessionController
                              .toggleHazard,
                          onLeftArrowLongPress: () {
                            _toggleDebugPhysicalIndicator(leftSide: true);
                          },
                          onRightArrowLongPress: () {
                            _toggleDebugPhysicalIndicator(leftSide: false);
                          },
                          liteMode: liteMode,
                        ),
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
                                    value: _formatDistanceStat(
                                      rideState.distanceKm,
                                    ),
                                    icon: Icons.route_outlined,
                                    liteMode: liteMode,
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: DashboardStatCard(
                                    title: "RPM",
                                    value: rideState.currentRpm.toStringAsFixed(
                                      0,
                                    ),
                                    icon: Icons.rotate_right_outlined,
                                    liteMode: liteMode,
                                    onLongPress: _toggleDebugMovingPacket,
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
                                    value: _formatSpeedStat(
                                      rideState.averageSpeedKmph,
                                    ),
                                    icon: Icons.speed_outlined,
                                    liteMode: liteMode,
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: DashboardStatCard(
                                    title: "MAX SPEED",
                                    value: _formatSpeedStat(
                                      rideState.maxSpeedKmph,
                                    ),
                                    icon: Icons.trending_up_outlined,
                                    liteMode: liteMode,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_countdownValue != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.72),
                              child: Center(
                                child: Transform.translate(
                                  // Small visual correction because large text digits sit slightly
                                  // below optical center due to font metrics.
                                  offset: const Offset(0, -10),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    transitionBuilder: (child, animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale:
                                              Tween<double>(
                                                begin: 0.82,
                                                end: 1.0,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeOutCubic,
                                                ),
                                              ),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Text(
                                      "$_countdownValue",
                                      key: ValueKey(_countdownValue),
                                      textAlign: TextAlign.center,
                                      strutStyle: const StrutStyle(
                                        forceStrutHeight: true,
                                        height: 1,
                                      ),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 120,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.45,
                                            ),
                                            blurRadius: 30,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        left: screenWidth * 0.04,
                        right: screenWidth * 0.04,
                        bottom: rideBottom,
                        child: RideControlBar(
                          rideState: rideState.rideState,
                          canStart: widget
                              .bikeConsoleController
                              .rideSessionController
                              .canStartRide,
                          timerText: widget
                              .bikeConsoleController
                              .rideSessionController
                              .formattedActiveDuration(),
                          onStart: _startRideWithCountdown,
                          onPause: widget
                              .bikeConsoleController
                              .rideSessionController
                              .manualPauseRide,
                          onResume: widget
                              .bikeConsoleController
                              .rideSessionController
                              .resumeRide,
                          onStop: widget
                              .bikeConsoleController
                              .rideSessionController
                              .stopRide,
                        ),
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

class _HeaderSessionsButton extends StatelessWidget {
  const _HeaderSessionsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1.4,
          ),
        ),
        child: Icon(
          Icons.route_rounded,
          color: Colors.white.withValues(alpha: 0.86),
          size: 25,
        ),
      ),
    );
  }
}

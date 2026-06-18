import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../bike_data.dart';
import '../controllers/map_tracking_controller.dart';
import '../controllers/bike_console_controller.dart';
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
  bool _manualReconnectPulse = false;

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

    // Let Flutter render one clean frame with the overlay removed while the
    // control bar is still in its wide green "Starting" state.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 90));

    if (!mounted) return;

    rideController.finishCountdownAndStartRide();
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

  Future<void> _forceConsoleReconnect() async {
    HapticFeedback.selectionClick();

    setState(() {
      _manualReconnectPulse = true;
    });

    await widget.bikeConsoleController.connectionController.reconnectNow();

    if (!mounted) return;

    setState(() {
      _manualReconnectPulse = false;
    });
  }

  void _stopRide() {
    final wasSaved = widget.bikeConsoleController.rideSessionController
        .stopRide();

    if (wasSaved) return;

    _showRideTooShortToast();
  }

  void _showRideTooShortToast() {
    final overlay = Overlay.of(context);

    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        final topOffset = MediaQuery.of(context).padding.top + 91;

        return Positioned(
          top: topOffset,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * -8),
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white.withValues(alpha: 0.72),
                          size: 18,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          "Ride too short — not saved",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) {
        entry.remove();
      }
    });
  }

  Widget _buildDeviceConnectedBadge() {
    final isConnected =
        widget.bikeConsoleController.connectionController.isConnected;

    final shouldPulse = !isConnected && _manualReconnectPulse;
    final shouldShowSlash = !isConnected && !_manualReconnectPulse;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: isConnected ? null : _forceConsoleReconnect,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF181818).withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: AnimatedBuilder(
          animation: _recenterPulseAnimation,
          builder: (context, child) {
            final pulseValue = _recenterPulseAnimation.value;
            final iconAlpha = shouldPulse
                ? 0.42 + ((pulseValue - 0.55) / 0.45 * 0.18)
                : 0.42;

            return Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.memory_rounded,
                  color: isConnected
                      ? AppColors.premiumGreen
                      : Colors.white.withValues(alpha: iconAlpha),
                  size: 25,
                ),

                if (shouldShowSlash)
                  Transform.rotate(
                    angle: -0.72,
                    child: Container(
                      width: 31,
                      height: 2.4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            );
          },
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
    final rideController = widget.bikeConsoleController.rideSessionController;
    final rideState = rideController.state;
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
                  const Text(
                    "Bike Console",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
                              zoom: MapTrackingController.navigationMapZoom,
                              tilt: MapTrackingController.navigationMapTilt,
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
                            rotateGesturesEnabled: true,
                            tiltGesturesEnabled: true,
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
                          hazardEnabled: rideState.hazardEnabled,
                          leftArrowActive:
                              isConsoleConnected && rideState.leftArrowActive,
                          rightArrowActive:
                              isConsoleConnected && rideState.rightArrowActive,
                          controlsEnabled: true,
                          onHazardTap: widget
                              .bikeConsoleController
                              .rideSessionController
                              .toggleHazard,
                          onLeftArrowTap: widget
                              .bikeConsoleController
                              .rideSessionController
                              .toggleAppLeftIndicator,
                          onRightArrowTap: widget
                              .bikeConsoleController
                              .rideSessionController
                              .toggleAppRightIndicator,
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
                          onStop: _stopRide,
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

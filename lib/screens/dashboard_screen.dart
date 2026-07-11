import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../bike_data.dart';
import '../controllers/map_tracking_controller.dart';
import '../controllers/bike_console_controller.dart';
import '../models/ride_route_point.dart';
import '../map_styles/dark_map_style.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/hex_settings_button.dart';
import '../widgets/ride_control_bar.dart';
import '../widgets/speed_console_panel.dart';
import 'settings_screen.dart';
import 'sessions_screen.dart';
import 'scan_for_devices_screen.dart';
import '../services/app_haptics.dart';
import '../services/ride_start_gate_service.dart';
import '../theme/app_colors.dart';

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
  final RideStartGateService _rideStartGateService = const RideStartGateService();
  late final AnimationController _recenterPulseController;
  late final Animation<double> _recenterPulseAnimation;

  static const double _mapDragDisableFollowThresholdPx = 16.0;

  int? _countdownValue;
  bool _manualReconnectPulse = false;
  Offset? _mapPointerDownPosition;
  bool _mapPointerDragConsumed = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    bikeListener = () {
      _syncMapTrailRecordingState();

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
    _mapTrackingController = MapTrackingController(
      onRoutePoint: _handleRoutePoint,
      onGpsPoint: _handleGpsFallbackPoint,
      rideRouteModeProvider: _currentRideRouteMode,
    );

    _syncMapTrailRecordingState();
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

  void _syncMapTrailRecordingState() {
    final rideState = widget.bikeConsoleController.rideSessionController.state;

    _mapTrackingController.setRoutePoints(rideState.routePoints);
    _mapTrackingController.setTrailRecordingEnabled(
      rideState.isRouteRecordingActive,
    );
  }

  RideRouteMode _currentRideRouteMode() {
    final rideState = widget.bikeConsoleController.rideSessionController.state;

    return rideState.isPaused ? RideRouteMode.paused : RideRouteMode.running;
  }

  void _handleRoutePoint(RideRoutePoint point) {
    widget.bikeConsoleController.rideSessionController.handleRoutePoint(point);
  }

  void _handleGpsFallbackPoint(RideRoutePoint point) {
    widget.bikeConsoleController.rideSessionController
        .handleGpsFallbackPoint(point);
  }

  String _blockedStartLabel() {
    final connection = widget.bikeConsoleController.connectionController;

    if (!connection.hasSavedConsole) {
      return "Pair a Console";
    }

    if (!connection.isConnected) {
      return "Connect Console";
    }

    return "Set Up Ride";
  }

  Future<void> _handleSmartStart() async {
    final readiness = await _rideStartGateService.check(
      widget.bikeConsoleController,
    );

    if (!mounted) return;

    if (readiness.canStart) {
      await _startRideWithCountdown();
      return;
    }

    AppHaptics.mediumImpact();

    final action = await _showRideSetupSheet(readiness);
    if (action == null || !mounted) return;

    await _handleRideSetupAction(action);
  }

  Future<void> _handleRideSetupAction(RideStartRequirement requirement) async {
    final opensExternalSettings =
        requirement == RideStartRequirement.locationServices;

    switch (requirement) {
      case RideStartRequirement.locationPermission:
        final openedSettings = await _rideStartGateService
            .requestLocationPermission();
        if (openedSettings) return;
        break;
      case RideStartRequirement.locationServices:
        await _rideStartGateService.openLocationSettings();
        break;
      case RideStartRequirement.notificationPermission:
        await _rideStartGateService.requestNotificationPermission();
        break;
      case RideStartRequirement.bluetoothPermissions:
        await _rideStartGateService.requestBluetoothPermissions();
        break;
      case RideStartRequirement.bluetoothPower:
        await _rideStartGateService.requestBluetoothPower();
        break;
      case RideStartRequirement.pairConsole:
        final BluetoothDevice? selected = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScanForDevicesScreen()),
        );

        if (selected != null) {
          await widget.bikeConsoleController.connectionController
              .pairWithDevice(selected);
        }
        break;
      case RideStartRequirement.connectConsole:
        await widget.bikeConsoleController.connectionController.reconnectNow();
        break;
    }

    if (!mounted) return;

    // Opening Android location settings is outside Flutter's control and may
    // return before the user actually changes anything. Close the sheet and let
    // the user press Start again after returning, instead of trapping the UI in
    // a stale setup sheet or Starting state.
    if (opensExternalSettings) {
      return;
    }

    // Let permission dialogs, Bluetooth state, and BLE callbacks settle before
    // deciding whether to start or show the next missing setup item.
    await Future.delayed(const Duration(milliseconds: 650));

    if (!mounted) return;

    final nextReadiness = await _rideStartGateService.check(
      widget.bikeConsoleController,
    );

    if (!mounted) return;

    if (nextReadiness.canStart) {
      await _startRideWithCountdown();
      return;
    }

    final nextAction = await _showRideSetupSheet(nextReadiness);
    if (nextAction == null || !mounted) return;

    await _handleRideSetupAction(nextAction);
  }

  Future<RideStartRequirement?> _showRideSetupSheet(
    RideStartReadiness readiness,
  ) {
    return showModalBottomSheet<RideStartRequirement>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _RideSetupSheet(readiness: readiness);
      },
    );
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

      AppHaptics.lightImpact();

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

    AppHaptics.mediumImpact();
    rideController.finishCountdownAndStartRide();
  }

  String _formatSpeedStat(double value) {
    if (value > 99.9) {
      return "${value.toStringAsFixed(0)} km/h";
    }

    return "${value.toStringAsFixed(1)} km/h";
  }

  String _formatMaxSpeedStat(double value) {
    return "${value.toStringAsFixed(0)} km/h";
  }

  String _formatDistanceStat(double value) {
    if (value > 99.99) {
      return "${value.toStringAsFixed(1)} km";
    }

    return "${value.toStringAsFixed(2)} km";
  }

  Future<void> _forceConsoleReconnect() async {
    AppHaptics.selectionClick();

    setState(() {
      _manualReconnectPulse = true;
    });

    await widget.bikeConsoleController.connectionController.reconnectNow();

    if (!mounted) return;

    setState(() {
      _manualReconnectPulse = false;
    });
  }

  Future<void> _recenterMap() async {
    AppHaptics.selectionClick();
    await _mapTrackingController.recenter();
  }

  void _handleMapPointerDown(PointerDownEvent event) {
    _mapPointerDownPosition = event.position;
    _mapPointerDragConsumed = false;
  }

  void _handleMapPointerMove(PointerMoveEvent event) {
    final startPosition = _mapPointerDownPosition;

    if (startPosition == null || _mapPointerDragConsumed) {
      return;
    }

    final dragDistance = (event.position - startPosition).distance;

    if (dragDistance < _mapDragDisableFollowThresholdPx) {
      return;
    }

    _mapPointerDragConsumed = true;
    _mapTrackingController.onUserTouchedMap();
  }

  void _handleMapPointerEnd(PointerEvent event) {
    _mapPointerDownPosition = null;
    _mapPointerDragConsumed = false;
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
    final displaySettings = widget.bikeConsoleController.displaySettings;
    final liteMode = displaySettings.liteModeEnabled;
    final threeDimensionalBuildingsEnabled =
        displaySettings.threeDimensionalBuildingsEnabled;

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
                          AppHaptics.selectionClick();
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
                          AppHaptics.selectionClick();
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
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _handleMapPointerDown,
                            onPointerMove: _handleMapPointerMove,
                            onPointerUp: _handleMapPointerEnd,
                            onPointerCancel: _handleMapPointerEnd,
                            child: GoogleMap(
                              key: ValueKey(
                                "dashboard-map-3d-$threeDimensionalBuildingsEnabled",
                              ),
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
                              myLocationEnabled: false,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              compassEnabled: false,
                              buildingsEnabled:
                                  threeDimensionalBuildingsEnabled,
                              rotateGesturesEnabled: true,
                              tiltGesturesEnabled: true,
                              padding: const EdgeInsets.only(bottom: 115),
                              markers: _mapTrackingController.markers,
                              polylines: _mapTrackingController.polylines,
                            ),
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
                          onTap: _recenterMap,
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
                                    value: _formatMaxSpeedStat(
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
                          onStart: _handleSmartStart,
                          onBlockedStart: _handleSmartStart,
                          blockedStartLabel: _blockedStartLabel(),
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

class _RideSetupSheet extends StatelessWidget {
  const _RideSetupSheet({required this.readiness});

  final RideStartReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final missingItems = readiness.missingItems;
    final firstMissing = missingItems.isNotEmpty ? missingItems.first : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.premiumGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.premiumGreen.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        Icons.directions_bike_rounded,
                        color: AppColors.premiumGreen,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Ready to Ride",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            "Finish these one-time setup checks before starting.",
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                for (final item in readiness.items) ...[
                  _RideSetupStepTile(
                    item: item,
                    isPrimaryAction: item == firstMissing,
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: firstMissing == null
                        ? () => Navigator.pop(context)
                        : () => Navigator.pop(context, firstMissing.requirement),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: firstMissing == null
                          ? AppColors.premiumGreen
                          : Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: Text(
                      firstMissing?.actionLabel ?? "Done",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RideSetupStepTile extends StatelessWidget {
  const _RideSetupStepTile({
    required this.item,
    required this.isPrimaryAction,
  });

  final RideStartGateItem item;
  final bool isPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final complete = item.isComplete;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: complete
            ? AppColors.premiumGreen.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: isPrimaryAction ? 0.075 : 0.045),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: complete
              ? AppColors.premiumGreen.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: isPrimaryAction ? 0.16 : 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: complete
                  ? AppColors.premiumGreen
                  : Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.arrow_forward_rounded,
              color: complete ? Colors.black : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: complete
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.92),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12.2,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
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

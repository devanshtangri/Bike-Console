import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../map_styles/dark_map_style.dart';
import '../models/ride_route_point.dart';
import '../models/saved_ride_session.dart';
import '../services/app_haptics.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.session});

  final SavedRideSession session;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  GoogleMapController? _mapController;

  List<RideRoutePoint> get _routePoints => widget.session.routePoints;

  bool get _hasRoute => _routePoints.isNotEmpty;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final dateText = _formatSessionDate(session.endEpochMs);
    final durationText = _formatCompactDuration(session.activeDurationMs);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Ride Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () {
            AppHaptics.selectionClick();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _RouteMapPanel(
              routePoints: _routePoints,
              polylines: _buildPolylines(),
              markers: _buildMarkers(),
              initialCameraPosition: _initialCameraPosition(),
              onMapCreated: _handleMapCreated,
            ),
            const SizedBox(height: 16),
            _RideHeaderCard(
              title: '${session.distanceKm.toStringAsFixed(2)} km ride',
              subtitle: dateText,
              hasRoute: _hasRoute,
              routePointCount: _routePoints.length,
            ),
            const SizedBox(height: 12),
            _MetricGrid(
              durationText: durationText,
              distanceKm: session.distanceKm,
              averageSpeedKmph: session.averageSpeedKmph,
              maxSpeedKmph: session.maxSpeedKmph,
            ),
            const SizedBox(height: 12),
            _RouteLegendCard(hasRoute: _hasRoute),
          ],
        ),
      ),
    );
  }

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _fitRoute(controller);
      }),
    );
  }

  CameraPosition _initialCameraPosition() {
    if (!_hasRoute) {
      return const CameraPosition(
        target: LatLng(28.6139, 77.2090),
        zoom: 11,
      );
    }

    final center = _routeCenter();
    return CameraPosition(target: center, zoom: _routePoints.length == 1 ? 16 : 14);
  }

  LatLng _routeCenter() {
    if (!_hasRoute) return const LatLng(28.6139, 77.2090);

    var minLat = _routePoints.first.latitude;
    var maxLat = _routePoints.first.latitude;
    var minLng = _routePoints.first.longitude;
    var maxLng = _routePoints.first.longitude;

    for (final point in _routePoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  Future<void> _fitRoute(GoogleMapController controller) async {
    if (!_hasRoute) return;

    if (_routePoints.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_routePoints.first.latitude, _routePoints.first.longitude),
          16,
        ),
      );
      return;
    }

    var minLat = _routePoints.first.latitude;
    var maxLat = _routePoints.first.latitude;
    var minLng = _routePoints.first.longitude;
    var maxLng = _routePoints.first.longitude;

    for (final point in _routePoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final latPadding = math.max((maxLat - minLat) * 0.12, 0.0006);
    final lngPadding = math.max((maxLng - minLng) * 0.12, 0.0006);

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - latPadding, minLng - lngPadding),
          northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
        ),
        36,
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    if (!_hasRoute) return const {};

    final first = _routePoints.first;
    final last = _routePoints.last;

    return {
      Marker(
        markerId: const MarkerId('ride-start'),
        position: LatLng(first.latitude, first.longitude),
        infoWindow: const InfoWindow(title: 'Start'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      if (_routePoints.length > 1)
        Marker(
          markerId: const MarkerId('ride-end'),
          position: LatLng(last.latitude, last.longitude),
          infoWindow: const InfoWindow(title: 'Finish'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };
  }

  Set<Polyline> _buildPolylines() {
    if (_routePoints.length < 2) return const {};

    final polylines = <Polyline>{};
    var segmentIndex = 0;
    var currentMode = _routePoints.first.rideMode;
    var currentPoints = <LatLng>[
      LatLng(_routePoints.first.latitude, _routePoints.first.longitude),
    ];

    void flushSegment() {
      if (currentPoints.length < 2) return;

      polylines.add(
        Polyline(
          polylineId: PolylineId('route-segment-$segmentIndex'),
          points: List<LatLng>.from(currentPoints),
          color: _colorForMode(currentMode),
          width: 6,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
      segmentIndex++;
    }

    for (final point in _routePoints.skip(1)) {
      final nextLatLng = LatLng(point.latitude, point.longitude);

      if (point.rideMode != currentMode) {
        flushSegment();
        currentPoints = [currentPoints.last, nextLatLng];
        currentMode = point.rideMode;
      } else {
        currentPoints.add(nextLatLng);
      }
    }

    flushSegment();
    return polylines;
  }

  Color _colorForMode(RideRouteMode mode) {
    return switch (mode) {
      RideRouteMode.running => Colors.greenAccent,
      RideRouteMode.paused => const Color(0xFFFFD166),
    };
  }
}

class _RouteMapPanel extends StatelessWidget {
  const _RouteMapPanel({
    required this.routePoints,
    required this.polylines,
    required this.markers,
    required this.initialCameraPosition,
    required this.onMapCreated,
  });

  final List<RideRoutePoint> routePoints;
  final Set<Polyline> polylines;
  final Set<Marker> markers;
  final CameraPosition initialCameraPosition;
  final ValueChanged<GoogleMapController> onMapCreated;

  bool get _hasRoute => routePoints.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Container(
        height: 360,
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            if (_hasRoute)
              GoogleMap(
                style: darkMapStyle,
                initialCameraPosition: initialCameraPosition,
                mapType: MapType.normal,
                polylines: polylines,
                markers: markers,
                onMapCreated: onMapCreated,
                compassEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
              )
            else
              const _NoRouteMapPlaceholder(),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _MapOverlayBar(routePointCount: routePoints.length),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoRouteMapPlaceholder extends StatelessWidget {
  const _NoRouteMapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101010),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined, color: Colors.white24, size: 46),
            SizedBox(height: 12),
            Text(
              'No route data saved',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Future rides with GPS route points will show here.',
              style: TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapOverlayBar extends StatelessWidget {
  const _MapOverlayBar({required this.routePointCount});

  final int routePointCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              routePointCount > 0
                  ? '$routePointCount route points saved'
                  : 'Route map unavailable',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RideHeaderCard extends StatelessWidget {
  const _RideHeaderCard({
    required this.title,
    required this.subtitle,
    required this.hasRoute,
    required this.routePointCount,
  });

  final String title;
  final String subtitle;
  final bool hasRoute;
  final int routePointCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.22),
              ),
            ),
            child: const Icon(
              Icons.route_rounded,
              color: Colors.greenAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _RouteStatusPill(
            label: hasRoute ? 'Mapped' : 'No Map',
            icon: hasRoute ? Icons.check_rounded : Icons.close_rounded,
            active: hasRoute,
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.durationText,
    required this.distanceKm,
    required this.averageSpeedKmph,
    required this.maxSpeedKmph,
  });

  final String durationText;
  final double distanceKm;
  final double averageSpeedKmph;
  final double maxSpeedKmph;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DetailMetricCard(
                icon: Icons.route_outlined,
                label: 'Distance',
                value: distanceKm.toStringAsFixed(2),
                unit: 'km',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DetailMetricCard(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: durationText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DetailMetricCard(
                icon: Icons.speed_outlined,
                label: 'Avg Speed',
                value: averageSpeedKmph.toStringAsFixed(1),
                unit: 'km/h',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DetailMetricCard(
                icon: Icons.trending_up_rounded,
                label: 'Max Speed',
                value: maxSpeedKmph.toStringAsFixed(1),
                unit: 'km/h',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailMetricCard extends StatelessWidget {
  const _DetailMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.greenAccent.withValues(alpha: 0.80), size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      unit!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteLegendCard extends StatelessWidget {
  const _RouteLegendCard({required this.hasRoute});

  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Route Legend',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _LegendDot(color: Colors.greenAccent),
              SizedBox(width: 8),
              Text(
                'Riding segment',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              SizedBox(width: 18),
              _LegendDot(color: Color(0xFFFFD166)),
              SizedBox(width: 8),
              Text(
                'Paused segment',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ),
          if (!hasRoute) ...[
            const SizedBox(height: 10),
            const Text(
              'This session was saved without route points, so only ride stats are available.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _RouteStatusPill extends StatelessWidget {
  const _RouteStatusPill({
    required this.label,
    required this.icon,
    required this.active,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.greenAccent : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: active ? 0.28 : 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCompactDuration(int durationMs) {
  final totalSeconds = durationMs ~/ 1000;
  final totalMinutes = totalSeconds ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  if (minutes > 0) {
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  return '${seconds}s';
}

String _formatSessionDate(int epochMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);

  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '$day/$month/$year $hour:$minute';
}

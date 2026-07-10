import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride_route_point.dart';
import '../theme/app_colors.dart';

class MapTrackingController extends ChangeNotifier {
  MapTrackingController({
    this.onRoutePoint,
    this.onGpsPoint,
    this.rideRouteModeProvider,
  });

  static const double navigationMapTilt = 45.0;
  static const double navigationMapZoom = 17.45;
  static const double navigationBearingSmoothing = 1.0;
  static const double _minimumReliableHeadingSpeedMps = 0.8;
  static const double _minimumCoordinateBearingDistanceMeters = 4.0;
  static const double _followCameraDistanceThresholdMeters = 1.5;
  static const double _followCameraBearingThresholdDegrees = 1.0;
  // Follow camera easing runs close to display refresh. The previous 80 ms
  // timer looked stepped/jittery even though the GPS data itself was fine.
  static const Duration _followCameraTickInterval = Duration(milliseconds: 16);
  static const double _followCameraTargetLerp = 0.14;
  static const double _followCameraBearingLerp = 0.16;
  static const double _followCameraSettleDistanceMeters = 0.12;
  static const double _followCameraBearingSettleDegrees = 0.35;
  static const double _followCameraSnapDistanceMeters = 180.0;
  static const int _maxRoutePolylineGapMs = 45000;
  static const double _maxRoutePolylineSpeedKmph = 72.0;
  static const double _maxRoutePolylineJumpMeters = 280.0;
  static const double _maxAcceptedRouteAccuracyMeters = 45.0;
  static const double _minRecordedRouteStepMeters = 1.0;
  static const int _maxRouteDuplicateHoldMs = 5000;
  static const double _maxAcceptedRoutePointSpeedKmph = 72.0;
  static const int _isolatedSpikeWindowMs = 4000;
  static const double _isolatedSpikeMinLegMeters = 14.0;
  static const double _isolatedSpikeReturnRadiusMeters = 8.0;

  final void Function(RideRoutePoint point)? onRoutePoint;
  final void Function(RideRoutePoint point)? onGpsPoint;
  final RideRouteMode Function()? rideRouteModeProvider;

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;

  LatLng? _currentLatLng;
  LatLng? _previousLatLngForBearing;
  double _currentHeading = 0;
  double _displayHeading = 0;
  bool _hasReliableHeading = false;
  bool _hasCenteredOnStartup = false;

  bool _followUser = true;
  bool _isProgrammaticCameraMove = false;
  bool _followCameraTickInFlight = false;
  int _ignoreCameraMoveStartedUntilMs = 0;

  LatLng? _lastFollowCameraTarget;
  double? _lastFollowCameraBearing;
  LatLng? _desiredFollowCameraTarget;
  LatLng? _visualFollowCameraTarget;
  double? _desiredFollowCameraBearing;
  double? _visualFollowCameraBearing;

  Timer? _followCameraTimer;

  BitmapDescriptor? _currentLocationIcon;
  List<RideRoutePoint> _routePoints = const [];
  bool _trailRecordingEnabled = false;

  bool _disposed = false;

  bool get followModeEnabled => _followUser;

  Set<Marker> get markers {
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
        anchor: const Offset(0.5, 0.67),
        rotation: _displayHeading,
        flat: true,
        zIndexInt: 10,
      ),
    };
  }

  Set<Polyline> get polylines {
    if (!_trailRecordingEnabled || _routePoints.length < 2) {
      return {};
    }

    final safePoints = _routePoints
        .where((point) => point.isValid)
        .toList(growable: false);

    if (safePoints.length < 2) {
      return {};
    }

    final result = <Polyline>{};
    var segmentIndex = 0;
    var previousPoint = safePoints.first;
    var currentMode = previousPoint.rideMode;
    var currentSegment = <LatLng>[_toLatLng(previousPoint)];

    for (var index = 1; index < safePoints.length; index++) {
      final point = safePoints[index];
      final latLng = _toLatLng(point);
      final shouldBreakLine = _shouldBreakPolyline(previousPoint, point);
      final modeChanged = point.rideMode != currentMode;

      if (shouldBreakLine) {
        if (currentSegment.length >= 2) {
          result.add(
            _buildSegmentPolyline(
              id: 'ride_trail_$segmentIndex',
              mode: currentMode,
              points: currentSegment,
            ),
          );
          segmentIndex++;
        }

        currentMode = point.rideMode;
        currentSegment = [latLng];
        previousPoint = point;
        continue;
      }

      if (modeChanged && currentSegment.length >= 2) {
        result.add(
          _buildSegmentPolyline(
            id: 'ride_trail_$segmentIndex',
            mode: currentMode,
            points: currentSegment,
          ),
        );
        segmentIndex++;
        currentSegment = [_toLatLng(previousPoint), latLng];
        currentMode = point.rideMode;
      } else {
        currentSegment.add(latLng);
        currentMode = point.rideMode;
      }

      previousPoint = point;
    }

    if (currentSegment.length >= 2) {
      result.add(
        _buildSegmentPolyline(
          id: 'ride_trail_$segmentIndex',
          mode: currentMode,
          points: currentSegment,
        ),
      );
    }

    return result;
  }

  Polyline _buildSegmentPolyline({
    required String id,
    required RideRouteMode mode,
    required List<LatLng> points,
  }) {
    return Polyline(
      polylineId: PolylineId(id),
      points: points,
      color: mode == RideRouteMode.paused
          ? AppColors.premiumYellow
          : AppColors.premiumGreen,
      width: 5,
      zIndex: 5,
      geodesic: true,
    );
  }

  LatLng _toLatLng(RideRoutePoint point) {
    return LatLng(point.latitude, point.longitude);
  }

  void setTrailRecordingEnabled(bool enabled) {
    if (_trailRecordingEnabled == enabled) {
      return;
    }

    _trailRecordingEnabled = enabled;
    notifyListeners();
  }

  void setRoutePoints(List<RideRoutePoint> routePoints) {
    final normalizedRoutePoints = _normalizedRoutePoints(routePoints);

    if (_sameRoutePointList(_routePoints, normalizedRoutePoints)) {
      return;
    }

    _routePoints = List<RideRoutePoint>.unmodifiable(normalizedRoutePoints);
    notifyListeners();
  }

  bool _sameRoutePointList(
    List<RideRoutePoint> current,
    List<RideRoutePoint> next,
  ) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    if (current.isEmpty) return true;

    final currentLast = current.last;
    final nextLast = next.last;

    return currentLast.latitude == nextLast.latitude &&
        currentLast.longitude == nextLast.longitude &&
        currentLast.rideMode == nextLast.rideMode &&
        currentLast.timestampMs == nextLast.timestampMs;
  }

  List<RideRoutePoint> _normalizedRoutePoints(
    List<RideRoutePoint> routePoints,
  ) {
    final validPoints = routePoints
        .where((point) => point.isValid)
        .toList(growable: false);

    if (validPoints.length < 2) return validPoints;

    final sortedPoints = [...validPoints]
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    final seen = <String>{};
    final normalized = <RideRoutePoint>[];

    for (final point in sortedPoints) {
      final key = '${point.timestampMs}:'
          '${point.latitude.toStringAsFixed(7)}:'
          '${point.longitude.toStringAsFixed(7)}:'
          '${point.rideMode.name}:'
          '${point.source.name}';

      if (seen.add(key)) {
        normalized.add(point);
      }
    }

    return _removeIsolatedRouteSpikes(normalized);
  }

  List<RideRoutePoint> _removeIsolatedRouteSpikes(
    List<RideRoutePoint> points,
  ) {
    if (points.length < 3) {
      return points;
    }

    final filtered = <RideRoutePoint>[points.first];

    for (var index = 1; index < points.length - 1; index++) {
      final previous = filtered.last;
      final candidate = points[index];
      final next = points[index + 1];

      if (_isIsolatedRouteSpike(previous, candidate, next)) {
        continue;
      }

      filtered.add(candidate);
    }

    filtered.add(points.last);
    return filtered;
  }

  bool _isIsolatedRouteSpike(
    RideRoutePoint previous,
    RideRoutePoint candidate,
    RideRoutePoint next,
  ) {
    if (previous.rideMode != candidate.rideMode ||
        candidate.rideMode != next.rideMode) {
      return false;
    }

    final firstElapsedMs = candidate.timestampMs - previous.timestampMs;
    final secondElapsedMs = next.timestampMs - candidate.timestampMs;
    final totalElapsedMs = next.timestampMs - previous.timestampMs;

    if (firstElapsedMs <= 0 ||
        secondElapsedMs <= 0 ||
        totalElapsedMs > _isolatedSpikeWindowMs) {
      return false;
    }

    final firstLegMeters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      candidate.latitude,
      candidate.longitude,
    );

    final secondLegMeters = Geolocator.distanceBetween(
      candidate.latitude,
      candidate.longitude,
      next.latitude,
      next.longitude,
    );

    final returnDistanceMeters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );

    return firstLegMeters >= _isolatedSpikeMinLegMeters &&
        secondLegMeters >= _isolatedSpikeMinLegMeters &&
        returnDistanceMeters <= _isolatedSpikeReturnRadiusMeters;
  }

  bool _shouldBreakPolyline(RideRoutePoint from, RideRoutePoint to) {
    final distanceMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );

    if (distanceMeters >= _maxRoutePolylineJumpMeters) {
      return true;
    }

    final elapsedMs = to.timestampMs - from.timestampMs;

    if (elapsedMs <= 0) {
      return elapsedMs < 0;
    }

    if (elapsedMs >= _maxRoutePolylineGapMs) {
      return true;
    }

    final impliedSpeedKmph = distanceMeters / (elapsedMs / 1000.0) * 3.6;

    return distanceMeters > 10 && impliedSpeedKmph > _maxRoutePolylineSpeedKmph;
  }

  Future<void> initialize() async {
    await _startLocationTracking();
  }

  Future<void> attachMapController(GoogleMapController controller) async {
    _mapController = controller;

    if (_currentLatLng != null && !_hasCenteredOnStartup) {
      _hasCenteredOnStartup = true;
      _followUser = true;
      await _moveNavigationCameraTo(_currentLatLng!, animated: true);
    }
  }

  void onUserMovedMap() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (_isProgrammaticCameraMove || nowMs < _ignoreCameraMoveStartedUntilMs) {
      return;
    }

    _disableFollowModeFromUserGesture();
  }

  void onUserTouchedMap() {
    _disableFollowModeFromUserGesture();
  }

  void _disableFollowModeFromUserGesture() {
    if (!_followUser) {
      return;
    }

    _followUser = false;
    _stopFollowCameraTimer();
    notifyListeners();
  }

  Future<void> recenter() async {
    await _centerOnCurrentLocation();
  }

  void markAppResumed() {
    // Intentionally empty.
    // Keeping this method only so dashboard_screen.dart can keep calling it.
    // Original GitHub map behavior did not add app-resume segment logic.
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

    _updateHeadingFromPosition(position, target);

    _currentLatLng = target;
    _followUser = true;
    await _moveNavigationCameraTo(target, animated: true);
    notifyListeners();
  }

  Future<void> _moveNavigationCameraTo(
    LatLng target, {
    required bool animated,
  }) async {
    if (_mapController == null) return;

    _stopFollowCameraTimer();

    _isProgrammaticCameraMove = true;
    _lastFollowCameraTarget = target;
    _lastFollowCameraBearing = _currentHeading;
    _desiredFollowCameraTarget = target;
    _desiredFollowCameraBearing = _currentHeading;
    _visualFollowCameraTarget = target;
    _visualFollowCameraBearing = _currentHeading;
    _displayHeading = _currentHeading;

    final cameraUpdate = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: target,
        zoom: navigationMapZoom,
        bearing: _currentHeading,
        tilt: navigationMapTilt,
      ),
    );

    _ignoreProgrammaticCameraMoveStartedFor(
      Duration(milliseconds: animated ? 900 : 260),
    );

    try {
      if (animated) {
        await _mapController!.animateCamera(cameraUpdate);
      } else {
        await _mapController!.moveCamera(cameraUpdate);
      }
    } finally {
      Future.delayed(Duration(milliseconds: animated ? 350 : 120), () {
        if (!_disposed) {
          _isProgrammaticCameraMove = false;
        }
      });
    }
  }

  Future<void> _maybeFollowUser(LatLng nextPoint) async {
    if (!_followUser || _mapController == null) {
      return;
    }

    if (_lastFollowCameraTarget == null) {
      _queueFollowCameraTarget(nextPoint);
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastFollowCameraTarget!.latitude,
      _lastFollowCameraTarget!.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

    final bearingChange = _lastFollowCameraBearing == null
        ? 360.0
        : _bearingDifference(_lastFollowCameraBearing!, _currentHeading).abs();

    if (distance >= _followCameraDistanceThresholdMeters ||
        bearingChange >= _followCameraBearingThresholdDegrees) {
      _queueFollowCameraTarget(nextPoint);
    }
  }

  void _queueFollowCameraTarget(LatLng target) {
    _desiredFollowCameraTarget = target;
    _desiredFollowCameraBearing = _currentHeading;

    _lastFollowCameraTarget = target;
    _lastFollowCameraBearing = _currentHeading;

    _visualFollowCameraTarget ??= target;
    _visualFollowCameraBearing ??= _currentHeading;

    _startFollowCameraTimer();
  }

  void _startFollowCameraTimer() {
    if (_followCameraTimer != null || _disposed) return;

    _followCameraTimer = Timer.periodic(_followCameraTickInterval, (_) {
      _tickFollowCamera();
    });
  }

  void _stopFollowCameraTimer() {
    _followCameraTimer?.cancel();
    _followCameraTimer = null;
  }

  void _ignoreProgrammaticCameraMoveStartedFor(Duration duration) {
    final nextIgnoreUntil =
        DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;

    if (nextIgnoreUntil > _ignoreCameraMoveStartedUntilMs) {
      _ignoreCameraMoveStartedUntilMs = nextIgnoreUntil;
    }
  }

  Future<void> _tickFollowCamera() async {
    if (_followCameraTickInFlight || !_followUser || _mapController == null) {
      return;
    }

    final desiredTarget = _desiredFollowCameraTarget;
    final desiredBearing = _desiredFollowCameraBearing;

    if (desiredTarget == null || desiredBearing == null) {
      _stopFollowCameraTimer();
      return;
    }

    _followCameraTickInFlight = true;
    _isProgrammaticCameraMove = true;

    try {
      final currentTarget = _visualFollowCameraTarget ?? desiredTarget;

      final distanceToDesired = Geolocator.distanceBetween(
        currentTarget.latitude,
        currentTarget.longitude,
        desiredTarget.latitude,
        desiredTarget.longitude,
      );

      final nextTarget =
          distanceToDesired <= _followCameraSettleDistanceMeters ||
              distanceToDesired >= _followCameraSnapDistanceMeters
          ? desiredTarget
          : _lerpLatLng(
              currentTarget,
              desiredTarget,
              _followCameraTargetLerp,
            );

      final currentBearing = _visualFollowCameraBearing ?? desiredBearing;
      final bearingToDesired = _bearingDifference(
        currentBearing,
        desiredBearing,
      );

      final nextBearing = bearingToDesired.abs() <=
              _followCameraBearingSettleDegrees
          ? desiredBearing
          : _normalizeBearing(
              currentBearing + (bearingToDesired * _followCameraBearingLerp),
            );

      _visualFollowCameraTarget = nextTarget;
      _visualFollowCameraBearing = nextBearing;
      _displayHeading = nextBearing;

      _ignoreProgrammaticCameraMoveStartedFor(
        const Duration(milliseconds: 90),
      );

      await _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: nextTarget,
            zoom: navigationMapZoom,
            bearing: nextBearing,
            tilt: navigationMapTilt,
          ),
        ),
      );

      notifyListeners();

      final remainingDistance = Geolocator.distanceBetween(
        nextTarget.latitude,
        nextTarget.longitude,
        desiredTarget.latitude,
        desiredTarget.longitude,
      );

      final remainingBearing = _bearingDifference(
        nextBearing,
        desiredBearing,
      ).abs();

      if (remainingDistance <= _followCameraSettleDistanceMeters &&
          remainingBearing <= _followCameraBearingSettleDegrees) {
        _visualFollowCameraTarget = desiredTarget;
        _visualFollowCameraBearing = desiredBearing;
        _displayHeading = desiredBearing;
        _stopFollowCameraTimer();
      }
    } finally {
      _followCameraTickInFlight = false;

      Future.delayed(const Duration(milliseconds: 40), () {
        if (!_disposed) {
          _isProgrammaticCameraMove = false;
        }
      });
    }
  }

  LatLng _lerpLatLng(LatLng from, LatLng to, double t) {
    return LatLng(
      from.latitude + ((to.latitude - from.latitude) * t),
      from.longitude + ((to.longitude - from.longitude) * t),
    );
  }

  Future<void> _startLocationTracking() async {
    final hasPermission = await _ensureLocationPermission();

    if (!hasPermission) {
      return;
    }

    _currentLocationIcon = await _createCurrentLocationIcon();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      ),
    ).listen((position) async {
      final nextPoint = LatLng(position.latitude, position.longitude);

      _updateHeadingFromPosition(position, nextPoint);
      _currentLatLng = nextPoint;

      if (_trailRecordingEnabled) {
        final routePoint = RideRoutePoint(
          latitude: position.latitude,
          longitude: position.longitude,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          accuracyMeters: position.accuracy,
          gpsSpeedMps: position.speed.isFinite && position.speed > 0
              ? position.speed
              : 0,
          rideMode: rideRouteModeProvider?.call() ?? RideRouteMode.running,
          source: RideRoutePointSource.gps,
        );

        if (routePoint.isValid) {
          // GPS fallback needs every valid position update, including repeated
          // coordinates. Route storage can still apply its stricter filter.
          onGpsPoint?.call(routePoint);

          if (_shouldAppendRoutePoint(routePoint)) {
            _routePoints = [..._routePoints, routePoint];
            onRoutePoint?.call(routePoint);
          }
        }
      }

      if (!_followUser) {
        _displayHeading = _currentHeading;
      }

      notifyListeners();

      if (!_hasCenteredOnStartup && _mapController != null) {
        _hasCenteredOnStartup = true;
        _followUser = true;
        await _moveNavigationCameraTo(nextPoint, animated: true);
        return;
      }

      await _maybeFollowUser(nextPoint);
    });
  }

  bool _shouldAppendRoutePoint(RideRoutePoint point) {
    final accuracyMeters = point.accuracyMeters;

    if (accuracyMeters.isFinite &&
        accuracyMeters > 0 &&
        accuracyMeters > _maxAcceptedRouteAccuracyMeters) {
      return false;
    }

    if (_routePoints.isEmpty) return true;

    final last = _routePoints.last;

    if (last.rideMode != point.rideMode) {
      return true;
    }

    final elapsedMs = point.timestampMs - last.timestampMs;

    if (elapsedMs <= 0) {
      return false;
    }

    final distanceMeters = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      point.latitude,
      point.longitude,
    );

    if (distanceMeters < _minRecordedRouteStepMeters &&
        elapsedMs < _maxRouteDuplicateHoldMs) {
      return false;
    }

    final impliedSpeedKmph = distanceMeters / (elapsedMs / 1000.0) * 3.6;

    if (distanceMeters > 5.0 &&
        impliedSpeedKmph > _maxAcceptedRoutePointSpeedKmph) {
      return false;
    }

    return distanceMeters >= _minRecordedRouteStepMeters ||
        elapsedMs >= _maxRouteDuplicateHoldMs;
  }

  void _updateHeadingFromPosition(Position position, LatLng nextPoint) {
    double? nextHeading;

    final previousPoint = _previousLatLngForBearing;
    final reportedSpeedMps = position.speed.isFinite ? position.speed : -1.0;
    final movingFromReportedSpeed =
        reportedSpeedMps >= _minimumReliableHeadingSpeedMps;

    var movementDistance = 0.0;

    if (previousPoint != null) {
      movementDistance = Geolocator.distanceBetween(
        previousPoint.latitude,
        previousPoint.longitude,
        nextPoint.latitude,
        nextPoint.longitude,
      );
    }

    final movingFromCoordinates =
        movementDistance >= _minimumCoordinateBearingDistanceMeters;
    final shouldUpdateHeading =
        movingFromReportedSpeed || movingFromCoordinates;

    if (shouldUpdateHeading) {
      if (movingFromReportedSpeed &&
          position.heading.isFinite &&
          position.heading >= 0) {
        nextHeading = position.heading;
      } else if (previousPoint != null && movementDistance > 0) {
        nextHeading = _bearingBetween(previousPoint, nextPoint);
      }
    }

    if (nextHeading != null) {
      final normalizedHeading = _normalizeBearing(nextHeading);

      _currentHeading = _hasReliableHeading && navigationBearingSmoothing < 1.0
          ? _smoothBearing(_currentHeading, normalizedHeading)
          : normalizedHeading;

      _hasReliableHeading = true;
    }

    // At rest, no new heading is accepted. The marker therefore keeps the
    // last reliable direction instead of snapping back to north.
    _previousLatLngForBearing = nextPoint;
  }

  double _smoothBearing(double current, double target) {
    final delta = _bearingDifference(current, target);
    return _normalizeBearing(current + (delta * navigationBearingSmoothing));
  }

  double _bearingDifference(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  double _normalizeBearing(double bearing) {
    return (bearing % 360 + 360) % 360;
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final fromLat = _degreesToRadians(from.latitude);
    final fromLng = _degreesToRadians(from.longitude);
    final toLat = _degreesToRadians(to.latitude);
    final toLng = _degreesToRadians(to.longitude);

    final deltaLng = toLng - fromLng;

    final y = math.sin(deltaLng) * math.cos(toLat);
    final x =
        math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);

    return _normalizeBearing(_radiansToDegrees(math.atan2(y, x)));
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  double _radiansToDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }

  Future<BitmapDescriptor> _createCurrentLocationIcon() async {
    const logicalWidth = 30.0;
    const logicalHeight = 45.0;
    const pixelRatio = 4.0;

    final imageWidth = (logicalWidth * pixelRatio).toInt();
    final imageHeight = (logicalHeight * pixelRatio).toInt();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.scale(pixelRatio, pixelRatio);

    final greenPaint = Paint()
      ..color = AppColors.premiumGreen
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;

    final trianglePath = Path()
      ..moveTo(logicalWidth * 0.5, 0)
      ..lineTo(logicalWidth * 0.933, logicalHeight * 0.5)
      ..lineTo(logicalWidth * 0.067, logicalHeight * 0.5)
      ..close();

    final circleCenter = Offset(logicalWidth * 0.5, logicalHeight * 0.667);

    final circleRadius = logicalWidth * 0.5;

    canvas.drawCircle(circleCenter, circleRadius, greenPaint);
    canvas.drawPath(trianglePath, greenPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    final bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(bytes, imagePixelRatio: pixelRatio);
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSubscription?.cancel();
    _stopFollowCameraTimer();
    _mapController?.dispose();
    super.dispose();
  }
}

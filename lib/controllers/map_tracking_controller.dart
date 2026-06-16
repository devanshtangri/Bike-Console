import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_colors.dart';

class MapTrackingController extends ChangeNotifier {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;

  LatLng? _currentLatLng;
  double _currentHeading = 0;
  bool _hasCenteredOnStartup = false;

  bool _followUser = true;
  bool _isProgrammaticCameraMove = false;
  LatLng? _lastFollowCameraTarget;

  BitmapDescriptor? _currentLocationIcon;
  final List<LatLng> _routePoints = [];

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
        rotation: _currentHeading,
        flat: true,
        zIndexInt: 10,
      ),
    };
  }

  Set<Polyline> get polylines {
    if (_routePoints.length < 2) {
      return {};
    }

    return {
      Polyline(
        polylineId: const PolylineId("ride_trail"),
        points: _routePoints,
        color: AppColors.premiumGreen,
        width: 5,
        zIndex: 5,
        geodesic: true,
      ),
    };
  }

  Future<void> initialize() async {
    await _startLocationTracking();
  }

  Future<void> attachMapController(GoogleMapController controller) async {
    _mapController = controller;

    if (_currentLatLng != null && !_hasCenteredOnStartup) {
      _hasCenteredOnStartup = true;
      _followUser = true;
      await _animateMapTo(_currentLatLng!);
    }
  }

  void onUserMovedMap() {
    if (!_isProgrammaticCameraMove) {
      _followUser = false;
      notifyListeners();
    }
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

    _followUser = true;
    await _animateMapTo(target);
    notifyListeners();
  }

  Future<void> _animateMapTo(LatLng target, {double zoom = 16}) async {
    if (_mapController == null) return;

    _isProgrammaticCameraMove = true;
    _lastFollowCameraTarget = target;

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom, bearing: 0, tilt: 0),
        ),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 350), () {
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
      await _animateMapTo(nextPoint);
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastFollowCameraTarget!.latitude,
      _lastFollowCameraTarget!.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

    if (distance >= 18) {
      await _animateMapTo(nextPoint);
    }
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

          _currentLatLng = nextPoint;

          if (position.heading >= 0) {
            _currentHeading = position.heading;
          }

          if (_routePoints.isEmpty || _routePoints.last != nextPoint) {
            _routePoints.add(nextPoint);
          }

          notifyListeners();

          if (!_hasCenteredOnStartup && _mapController != null) {
            _hasCenteredOnStartup = true;
            _followUser = true;
            await _animateMapTo(nextPoint);
            return;
          }

          await _maybeFollowUser(nextPoint);
        });
  }

  Future<BitmapDescriptor> _createCurrentLocationIcon() async {
    const logicalWidth = 24.0;
    const logicalHeight = 36.0;
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
    _mapController?.dispose();
    super.dispose();
  }
}

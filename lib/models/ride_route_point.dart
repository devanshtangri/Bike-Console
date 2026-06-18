enum RideRouteMode { running, paused }

enum RideRoutePointSource { gps }

class RideRoutePoint {
  const RideRoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestampMs,
    required this.accuracyMeters,
    required this.gpsSpeedMps,
    required this.rideMode,
    required this.source,
  });

  final double latitude;
  final double longitude;
  final int timestampMs;
  final double accuracyMeters;
  final double gpsSpeedMps;
  final RideRouteMode rideMode;
  final RideRoutePointSource source;

  bool get isValid {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  RideRoutePoint copyWith({
    double? latitude,
    double? longitude,
    int? timestampMs,
    double? accuracyMeters,
    double? gpsSpeedMps,
    RideRouteMode? rideMode,
    RideRoutePointSource? source,
  }) {
    return RideRoutePoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestampMs: timestampMs ?? this.timestampMs,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      gpsSpeedMps: gpsSpeedMps ?? this.gpsSpeedMps,
      rideMode: rideMode ?? this.rideMode,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,
      'lng': longitude,
      'timestampMs': timestampMs,
      'accuracyMeters': accuracyMeters,
      'gpsSpeedMps': gpsSpeedMps,
      'rideMode': rideMode.name,
      'source': source.name,
    };
  }

  factory RideRoutePoint.fromJson(Map<String, dynamic> json) {
    return RideRoutePoint(
      latitude: _readDouble(json['lat'] ?? json['latitude']),
      longitude: _readDouble(json['lng'] ?? json['longitude']),
      timestampMs: _readInt(json['timestampMs']),
      accuracyMeters: _readDouble(json['accuracyMeters']),
      gpsSpeedMps: _readDouble(json['gpsSpeedMps']),
      rideMode: _readRideMode(json['rideMode']),
      source: _readSource(json['source']),
    );
  }

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static RideRouteMode _readRideMode(dynamic value) {
    return RideRouteMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => RideRouteMode.running,
    );
  }

  static RideRoutePointSource _readSource(dynamic value) {
    return RideRoutePointSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => RideRoutePointSource.gps,
    );
  }
}

import 'ride_route_point.dart';

class SavedRideSession {
  const SavedRideSession({
    required this.id,
    required this.startEpochMs,
    required this.endEpochMs,
    required this.activeDurationMs,
    required this.distanceKm,
    required this.averageSpeedKmph,
    required this.maxSpeedKmph,
    required this.routePoints,
  });

  final String id;
  final int startEpochMs;
  final int endEpochMs;
  final int activeDurationMs;
  final double distanceKm;
  final double averageSpeedKmph;
  final double maxSpeedKmph;
  final List<RideRoutePoint> routePoints;

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "startEpochMs": startEpochMs,
      "endEpochMs": endEpochMs,
      "activeDurationMs": activeDurationMs,
      "distanceKm": distanceKm,
      "averageSpeedKmph": averageSpeedKmph,
      "maxSpeedKmph": maxSpeedKmph,
      "routePoints": routePoints.map((point) => point.toJson()).toList(),
    };
  }

  factory SavedRideSession.fromJson(Map<String, dynamic> json) {
    return SavedRideSession(
      id: json["id"]?.toString() ?? "",
      startEpochMs: _readInt(json["startEpochMs"]),
      endEpochMs: _readInt(json["endEpochMs"]),
      activeDurationMs: _readInt(json["activeDurationMs"]),
      distanceKm: _readDouble(json["distanceKm"]),
      averageSpeedKmph: _readDouble(json["averageSpeedKmph"]),
      maxSpeedKmph: _readDouble(json["maxSpeedKmph"]),
      routePoints: _readRoutePoints(json["routePoints"]),
    );
  }

  static List<RideRoutePoint> _readRoutePoints(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map<String, dynamic>>()
        .map(RideRoutePoint.fromJson)
        .where((point) => point.isValid)
        .toList(growable: false);
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }
}

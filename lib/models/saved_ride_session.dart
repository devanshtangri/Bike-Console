class SavedRideSession {
  const SavedRideSession({
    required this.id,
    required this.startEpochMs,
    required this.endEpochMs,
    required this.activeDurationMs,
    required this.distanceKm,
    required this.averageSpeedKmph,
    required this.maxSpeedKmph,
  });

  final String id;
  final int startEpochMs;
  final int endEpochMs;
  final int activeDurationMs;
  final double distanceKm;
  final double averageSpeedKmph;
  final double maxSpeedKmph;

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "startEpochMs": startEpochMs,
      "endEpochMs": endEpochMs,
      "activeDurationMs": activeDurationMs,
      "distanceKm": distanceKm,
      "averageSpeedKmph": averageSpeedKmph,
      "maxSpeedKmph": maxSpeedKmph,
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
    );
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
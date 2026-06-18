import 'ride_route_point.dart';

enum RideState { stopped, countdown, running, paused }

enum PauseReason { none, manual, auto }

enum ConsoleConnectionState {
  disconnected,
  scanning,
  available,
  connecting,
  connected,
  lostDuringRide,
  reconnecting,
  offline,
}

enum SpeedSource { none, wheel, gpsFallback }

class RideSettings {
  const RideSettings({
    required this.tyreCircumferenceMeters,
    required this.autoPauseEnabled,
    required this.autoPauseSeconds,
  });

  final double tyreCircumferenceMeters;
  final bool autoPauseEnabled;
  final int autoPauseSeconds;

  factory RideSettings.defaults() {
    return const RideSettings(
      tyreCircumferenceMeters: 2.0,
      autoPauseEnabled: true,
      autoPauseSeconds: 10,
    );
  }

  factory RideSettings.fromJson(Map<String, dynamic> json) {
    final circumference = BikeSensorPacket._readDouble(
      json['tyreCircumferenceMeters'],
    );

    return RideSettings(
      tyreCircumferenceMeters: circumference <= 0 ? 2.0 : circumference,
      autoPauseEnabled: json['autoPauseEnabled'] != false,
      autoPauseSeconds: _readPositiveInt(
        json['autoPauseSeconds'],
        fallback: 10,
      ),
    );
  }

  RideSettings copyWith({
    double? tyreCircumferenceMeters,
    bool? autoPauseEnabled,
    int? autoPauseSeconds,
  }) {
    return RideSettings(
      tyreCircumferenceMeters:
          tyreCircumferenceMeters ?? this.tyreCircumferenceMeters,
      autoPauseEnabled: autoPauseEnabled ?? this.autoPauseEnabled,
      autoPauseSeconds: autoPauseSeconds ?? this.autoPauseSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tyreCircumferenceMeters': tyreCircumferenceMeters,
      'autoPauseEnabled': autoPauseEnabled,
      'autoPauseSeconds': autoPauseSeconds,
    };
  }

  static int _readPositiveInt(dynamic value, {required int fallback}) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();

    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) return parsed;
    }

    return fallback;
  }
}

class RideSessionState {
  const RideSessionState({
    required this.rideState,
    required this.pauseReason,
    required this.rideStartEpochMs,
    required this.currentPauseStartEpochMs,
    required this.accumulatedPausedMs,
    required this.distanceKm,
    required this.averageSpeedKmph,
    required this.maxSpeedKmph,
    required this.currentSpeedKmph,
    required this.currentRpm,
    required this.speedSource,
    required this.routePoints,
    required this.autoPauseSuppressedUntilMovement,
    required this.hazardEnabled,
    required this.appLeftIndicator,
    required this.appRightIndicator,
    required this.leftPhysicalIndicator,
    required this.rightPhysicalIndicator,
    required this.leftOutputActive,
    required this.rightOutputActive,
  });

  final RideState rideState;
  final PauseReason pauseReason;

  /// Epoch timestamp in milliseconds when the ride actually started.
  /// This is set after the countdown finishes, not when Start is tapped.
  final int? rideStartEpochMs;

  /// Epoch timestamp in milliseconds when the current pause began.
  /// Null when the ride is not currently paused.
  final int? currentPauseStartEpochMs;

  /// Total completed paused duration in milliseconds.
  /// This does not include the currently ongoing pause.
  final int accumulatedPausedMs;

  /// Workout distance.
  /// ESP32 wheel distance is primary. GPS fallback can be added later.
  final double distanceKm;

  /// Average speed calculated by Flutter:
  /// distance / active ride duration.
  final double averageSpeedKmph;

  /// Max speed calculated by Flutter from displayed speed.
  final double maxSpeedKmph;

  /// Current displayed speed.
  /// Usually calculated from ESP32 RPM and tyre circumference.
  final double currentSpeedKmph;

  /// Current wheel RPM received from ESP32.
  final double currentRpm;

  /// Tells UI whether speed is from wheel, GPS fallback, or none.
  final SpeedSource speedSource;

  /// GPS route points collected during the current ride.
  /// Each point stores whether it belongs to a running or paused segment.
  final List<RideRoutePoint> routePoints;

  /// When true, auto-pause is blocked until fresh movement is detected.
  /// This preserves manual resume after auto-pause across UI recreation.
  final bool autoPauseSuppressedUntilMovement;

  /// Logical app-side hazard state.
  /// This should stay true even if physical indicators temporarily override output.
  final bool hazardEnabled;

  /// Logical app-side turn indicator states.
  /// Physical switches still have higher priority than these.
  final bool appLeftIndicator;
  final bool appRightIndicator;

  /// Physical indicator switch states received from ESP32.
  final bool leftPhysicalIndicator;
  final bool rightPhysicalIndicator;

  /// Actual effective indicator outputs received from ESP32.
  final bool leftOutputActive;
  final bool rightOutputActive;

  factory RideSessionState.initial() {
    return const RideSessionState(
      rideState: RideState.stopped,
      pauseReason: PauseReason.none,
      rideStartEpochMs: null,
      currentPauseStartEpochMs: null,
      accumulatedPausedMs: 0,
      distanceKm: 0,
      averageSpeedKmph: 0,
      maxSpeedKmph: 0,
      currentSpeedKmph: 0,
      currentRpm: 0,
      speedSource: SpeedSource.none,
      routePoints: [],
      autoPauseSuppressedUntilMovement: false,
      hazardEnabled: false,
      appLeftIndicator: false,
      appRightIndicator: false,
      leftPhysicalIndicator: false,
      rightPhysicalIndicator: false,
      leftOutputActive: false,
      rightOutputActive: false,
    );
  }

  bool get isStopped => rideState == RideState.stopped;
  bool get isCountdown => rideState == RideState.countdown;
  bool get isRunning => rideState == RideState.running;
  bool get isPaused => rideState == RideState.paused;
  bool get isRideActive => rideState != RideState.stopped;
  bool get isRouteRecordingActive => isRunning || isPaused;

  bool get physicalIndicatorOverrideActive =>
      leftPhysicalIndicator || rightPhysicalIndicator;

  bool get appIndicatorOverrideActive => appLeftIndicator || appRightIndicator;

  bool get leftArrowActive {
    if (leftPhysicalIndicator) return true;
    if (rightPhysicalIndicator) return false;

    return leftOutputActive;
  }

  bool get rightArrowActive {
    if (leftPhysicalIndicator) return false;
    if (rightPhysicalIndicator) return true;

    return rightOutputActive;
  }

  RideSessionState copyWith({
    RideState? rideState,
    PauseReason? pauseReason,
    int? rideStartEpochMs,
    bool clearRideStartEpochMs = false,
    int? currentPauseStartEpochMs,
    bool clearCurrentPauseStartEpochMs = false,
    int? accumulatedPausedMs,
    double? distanceKm,
    double? averageSpeedKmph,
    double? maxSpeedKmph,
    double? currentSpeedKmph,
    double? currentRpm,
    SpeedSource? speedSource,
    List<RideRoutePoint>? routePoints,
    bool? autoPauseSuppressedUntilMovement,
    bool? hazardEnabled,
    bool? appLeftIndicator,
    bool? appRightIndicator,
    bool? leftPhysicalIndicator,
    bool? rightPhysicalIndicator,
    bool? leftOutputActive,
    bool? rightOutputActive,
  }) {
    return RideSessionState(
      rideState: rideState ?? this.rideState,
      pauseReason: pauseReason ?? this.pauseReason,
      rideStartEpochMs: clearRideStartEpochMs
          ? null
          : rideStartEpochMs ?? this.rideStartEpochMs,
      currentPauseStartEpochMs: clearCurrentPauseStartEpochMs
          ? null
          : currentPauseStartEpochMs ?? this.currentPauseStartEpochMs,
      accumulatedPausedMs: accumulatedPausedMs ?? this.accumulatedPausedMs,
      distanceKm: distanceKm ?? this.distanceKm,
      averageSpeedKmph: averageSpeedKmph ?? this.averageSpeedKmph,
      maxSpeedKmph: maxSpeedKmph ?? this.maxSpeedKmph,
      currentSpeedKmph: currentSpeedKmph ?? this.currentSpeedKmph,
      currentRpm: currentRpm ?? this.currentRpm,
      speedSource: speedSource ?? this.speedSource,
      routePoints: routePoints ?? this.routePoints,
      autoPauseSuppressedUntilMovement:
          autoPauseSuppressedUntilMovement ??
          this.autoPauseSuppressedUntilMovement,
      hazardEnabled: hazardEnabled ?? this.hazardEnabled,
      appLeftIndicator: appLeftIndicator ?? this.appLeftIndicator,
      appRightIndicator: appRightIndicator ?? this.appRightIndicator,
      leftPhysicalIndicator:
          leftPhysicalIndicator ?? this.leftPhysicalIndicator,
      rightPhysicalIndicator:
          rightPhysicalIndicator ?? this.rightPhysicalIndicator,
      leftOutputActive: leftOutputActive ?? this.leftOutputActive,
      rightOutputActive: rightOutputActive ?? this.rightOutputActive,
    );
  }
}

class BikeSensorPacket {
  const BikeSensorPacket({
    required this.rpm,
    required this.distanceKm,
    required this.isMoving,
    required this.leftPhysical,
    required this.rightPhysical,
    required this.leftOutput,
    required this.rightOutput,
    required this.hazardOutput,
    required this.appLeft,
    required this.appRight,
    required this.consoleRideActive,
  });

  /// Wheel RPM measured by ESP32 after one full wheel rotation.
  final double rpm;

  /// Distance accumulated by ESP32 from wheel rotations.
  final double distanceKm;

  /// Movement state decided by ESP32.
  /// Flutter uses this for auto-pause logic.
  final bool isMoving;

  /// Physical left indicator switch state.
  final bool leftPhysical;

  /// Physical right indicator switch state.
  final bool rightPhysical;

  /// Actual effective left indicator output driven by ESP32.
  final bool leftOutput;

  /// Actual effective right indicator output driven by ESP32.
  final bool rightOutput;

  /// Logical hazard state on ESP32 side.
  final bool hazardOutput;

  /// App-side indicator state currently stored on ESP32.
  final bool appLeft;
  final bool appRight;

  /// Whether ESP32 currently believes ride distance counting is active.
  final bool consoleRideActive;

  factory BikeSensorPacket.empty() {
    return const BikeSensorPacket(
      rpm: 0,
      distanceKm: 0,
      isMoving: false,
      leftPhysical: false,
      rightPhysical: false,
      leftOutput: false,
      rightOutput: false,
      hazardOutput: false,
      appLeft: false,
      appRight: false,
      consoleRideActive: false,
    );
  }

  factory BikeSensorPacket.fromJson(Map<String, dynamic> json) {
    return BikeSensorPacket(
      rpm: _readDouble(json['rpm'] ?? json['r']),
      distanceKm: _readDouble(json['distance'] ?? json['d']),
      isMoving: _readBool(json['moving'] ?? json['m']),
      leftPhysical: _readBool(json['leftPhysical'] ?? json['lp']),
      rightPhysical: _readBool(json['rightPhysical'] ?? json['rp']),
      leftOutput: _readBool(json['leftOutput'] ?? json['lo']),
      rightOutput: _readBool(json['rightOutput'] ?? json['ro']),
      hazardOutput: _readBool(json['hazardOutput'] ?? json['hz']),
      appLeft: _readBool(json['appLeft'] ?? json['al']),
      appRight: _readBool(json['appRight'] ?? json['ar']),
      consoleRideActive: _readBool(json['consoleActive'] ?? json['ca']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rpm': rpm,
      'distance': distanceKm,
      'moving': isMoving,
      'leftPhysical': leftPhysical,
      'rightPhysical': rightPhysical,
      'leftOutput': leftOutput,
      'rightOutput': rightOutput,
      'hazardOutput': hazardOutput,
      'appLeft': appLeft,
      'appRight': appRight,
      'consoleActive': consoleRideActive,
    };
  }

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      return normalized == 'true' || normalized == '1';
    }

    return false;
  }
}

enum BikeCommandType {
  sync,
  start,
  stop,
  pause,
  resume,
  hazard,
  setCircumference,
  setDistance,
  indicator,
}

class BikeCommand {
  const BikeCommand({
    required this.type,
    this.rideActive,
    this.paused,
    this.distanceKm,
    this.hazardEnabled,
    this.appLeftIndicator,
    this.appRightIndicator,
    this.tyreCircumferenceMeters,
  });

  final BikeCommandType type;

  /// Whether the ride should be active on ESP32 side.
  /// Used mainly during sync/start/stop.
  final bool? rideActive;

  /// Whether ESP32 should avoid distance counting.
  /// This may be useful if we decide ESP32 should know pause state.
  final bool? paused;

  /// Distance to set or restore on ESP32.
  /// Useful after ESP32 reboot or GPS fallback sync.
  final double? distanceKm;

  /// Logical hazard state from Flutter.
  final bool? hazardEnabled;

  /// Logical app-side indicator states from Flutter.
  final bool? appLeftIndicator;
  final bool? appRightIndicator;

  /// Tyre circumference in meters.
  /// ESP32 needs this for distance accumulation.
  final double? tyreCircumferenceMeters;

  Map<String, dynamic> toJson() {
    return {
      'cmd': type.name,
      if (rideActive != null) 'rideActive': rideActive,
      if (paused != null) 'paused': paused,
      if (distanceKm != null) 'distance': distanceKm,
      if (hazardEnabled != null) 'hazard': hazardEnabled,
      if (appLeftIndicator != null) 'appLeft': appLeftIndicator,
      if (appRightIndicator != null) 'appRight': appRightIndicator,
      if (tyreCircumferenceMeters != null)
        'circumference': tyreCircumferenceMeters,
    };
  }

  factory BikeCommand.sync({
    required bool rideActive,
    required bool paused,
    required double distanceKm,
    required bool hazardEnabled,
    required bool appLeftIndicator,
    required bool appRightIndicator,
    required double tyreCircumferenceMeters,
  }) {
    return BikeCommand(
      type: BikeCommandType.sync,
      rideActive: rideActive,
      paused: paused,
      distanceKm: distanceKm,
      hazardEnabled: hazardEnabled,
      appLeftIndicator: appLeftIndicator,
      appRightIndicator: appRightIndicator,
      tyreCircumferenceMeters: tyreCircumferenceMeters,
    );
  }

  factory BikeCommand.start({
    required double tyreCircumferenceMeters,
    double distanceKm = 0,
  }) {
    return BikeCommand(
      type: BikeCommandType.start,
      rideActive: true,
      paused: false,
      distanceKm: distanceKm,
      tyreCircumferenceMeters: tyreCircumferenceMeters,
    );
  }

  factory BikeCommand.stop() {
    return const BikeCommand(
      type: BikeCommandType.stop,
      rideActive: false,
      paused: false,
      distanceKm: 0,
    );
  }

  factory BikeCommand.pause() {
    return const BikeCommand(type: BikeCommandType.pause, paused: true);
  }

  factory BikeCommand.resume() {
    return const BikeCommand(type: BikeCommandType.resume, paused: false);
  }

  factory BikeCommand.hazard(bool value) {
    return BikeCommand(type: BikeCommandType.hazard, hazardEnabled: value);
  }

  factory BikeCommand.indicator({
    required bool appLeftIndicator,
    required bool appRightIndicator,
  }) {
    return BikeCommand(
      type: BikeCommandType.indicator,
      appLeftIndicator: appLeftIndicator,
      appRightIndicator: appRightIndicator,
    );
  }

  factory BikeCommand.setCircumference(double value) {
    return BikeCommand(
      type: BikeCommandType.setCircumference,
      tyreCircumferenceMeters: value,
    );
  }

  factory BikeCommand.setDistance(double value) {
    return BikeCommand(type: BikeCommandType.setDistance, distanceKm: value);
  }
}

class PersistedRideSnapshot {
  const PersistedRideSnapshot({
    required this.rideState,
    required this.pauseReason,
    required this.rideStartEpochMs,
    required this.currentPauseStartEpochMs,
    required this.accumulatedPausedMs,
    required this.distanceKm,
    required this.averageSpeedKmph,
    required this.maxSpeedKmph,
    required this.routePoints,
    required this.autoPauseSuppressedUntilMovement,
    required this.hazardEnabled,
    required this.appLeftIndicator,
    required this.appRightIndicator,
  });

  final RideState rideState;
  final PauseReason pauseReason;
  final int? rideStartEpochMs;
  final int? currentPauseStartEpochMs;
  final int accumulatedPausedMs;
  final double distanceKm;
  final double averageSpeedKmph;
  final double maxSpeedKmph;
  final List<RideRoutePoint> routePoints;
  final bool autoPauseSuppressedUntilMovement;
  final bool hazardEnabled;
  final bool appLeftIndicator;
  final bool appRightIndicator;

  factory PersistedRideSnapshot.fromSessionState(RideSessionState state) {
    return PersistedRideSnapshot(
      rideState: state.rideState,
      pauseReason: state.pauseReason,
      rideStartEpochMs: state.rideStartEpochMs,
      currentPauseStartEpochMs: state.currentPauseStartEpochMs,
      accumulatedPausedMs: state.accumulatedPausedMs,
      distanceKm: state.distanceKm,
      averageSpeedKmph: state.averageSpeedKmph,
      maxSpeedKmph: state.maxSpeedKmph,
      routePoints: state.routePoints,
      autoPauseSuppressedUntilMovement:
          state.autoPauseSuppressedUntilMovement,
      hazardEnabled: state.hazardEnabled,
      appLeftIndicator: state.appLeftIndicator,
      appRightIndicator: state.appRightIndicator,
    );
  }

  factory PersistedRideSnapshot.fromJson(Map<String, dynamic> json) {
    return PersistedRideSnapshot(
      rideState: _readRideState(json['rideState']),
      pauseReason: _readPauseReason(json['pauseReason']),
      rideStartEpochMs: _readNullableInt(json['rideStartEpochMs']),
      currentPauseStartEpochMs: _readNullableInt(
        json['currentPauseStartEpochMs'],
      ),
      accumulatedPausedMs: _readInt(json['accumulatedPausedMs']),
      distanceKm: BikeSensorPacket._readDouble(json['distanceKm']),
      averageSpeedKmph: BikeSensorPacket._readDouble(json['averageSpeedKmph']),
      maxSpeedKmph: BikeSensorPacket._readDouble(json['maxSpeedKmph']),
      routePoints: _readRoutePoints(json['routePoints']),
      autoPauseSuppressedUntilMovement:
          json['autoPauseSuppressedUntilMovement'] == true,
      hazardEnabled: json['hazardEnabled'] == true,
      appLeftIndicator: json['appLeftIndicator'] == true,
      appRightIndicator: json['appRightIndicator'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rideState': rideState.name,
      'pauseReason': pauseReason.name,
      'rideStartEpochMs': rideStartEpochMs,
      'currentPauseStartEpochMs': currentPauseStartEpochMs,
      'accumulatedPausedMs': accumulatedPausedMs,
      'distanceKm': distanceKm,
      'averageSpeedKmph': averageSpeedKmph,
      'maxSpeedKmph': maxSpeedKmph,
      'routePoints': routePoints.map((point) => point.toJson()).toList(),
      'autoPauseSuppressedUntilMovement': autoPauseSuppressedUntilMovement,
      'hazardEnabled': hazardEnabled,
      'appLeftIndicator': appLeftIndicator,
      'appRightIndicator': appRightIndicator,
    };
  }

  RideSessionState toSessionState() {
    return RideSessionState.initial().copyWith(
      rideState: rideState,
      pauseReason: pauseReason,
      rideStartEpochMs: rideStartEpochMs,
      currentPauseStartEpochMs: currentPauseStartEpochMs,
      accumulatedPausedMs: accumulatedPausedMs,
      distanceKm: distanceKm,
      averageSpeedKmph: averageSpeedKmph,
      maxSpeedKmph: maxSpeedKmph,
      routePoints: routePoints,
      autoPauseSuppressedUntilMovement: autoPauseSuppressedUntilMovement,
      hazardEnabled: hazardEnabled,
      appLeftIndicator: appLeftIndicator,
      appRightIndicator: appRightIndicator,
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

  static RideState _readRideState(dynamic value) {
    return RideState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => RideState.stopped,
    );
  }

  static PauseReason _readPauseReason(dynamic value) {
    return PauseReason.values.firstWhere(
      (reason) => reason.name == value,
      orElse: () => PauseReason.none,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    return _readInt(value);
  }
}

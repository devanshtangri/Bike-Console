import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/ride_models.dart';

class BikeConnectionController extends ChangeNotifier {
  BikeConnectionController();

  ConsoleConnectionState _connectionState = ConsoleConnectionState.disconnected;

  BikeSensorPacket _lastPacket = BikeSensorPacket.empty();
  void Function(BikeSensorPacket packet)? onPacket;
  void Function(ConsoleConnectionState state)? onConnectionStateChanged;

  ConsoleConnectionState get connectionState => _connectionState;
  BikeSensorPacket get lastPacket => _lastPacket;

  bool get isConnected => _connectionState == ConsoleConnectionState.connected;

  /// This will later be connected to the real BLE write characteristic.
  /// For now, it only prepares the command as JSON.
  String encodeCommand(BikeCommand command) {
    return jsonEncode(command.toJson());
  }

  /// Temporary public method for testing incoming ESP32 JSON packets.
  /// Later this will be called from the BLE notification listener.
  void handleIncomingJson(String raw) {
    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      _lastPacket = BikeSensorPacket.fromJson(decoded);

      onPacket?.call(_lastPacket);

      notifyListeners();
    } catch (_) {
      return;
    }
  }

  void setConnectionState(ConsoleConnectionState value) {
    if (_connectionState == value) return;

    _connectionState = value;

    if (!isConnected) {
      _lastPacket = BikeSensorPacket.empty();
    }

    onConnectionStateChanged?.call(_connectionState);

    notifyListeners();
  }

  /// Later this will write to ESP32 over BLE.
  void sendCommand(BikeCommand command) {
    final encoded = encodeCommand(command);

    // Placeholder for BLE write.
    debugPrint('BikeCommand -> $encoded');
  }
}

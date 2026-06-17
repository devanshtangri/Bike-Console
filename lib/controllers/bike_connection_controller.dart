import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ride_models.dart';

class BikeConnectionController extends ChangeNotifier {
  BikeConnectionController();

  static final Guid _serviceUuid = Guid('7a8d0001-4f7a-4e6f-9a0b-1f2e3d4c5b6a');

  static final Guid _sensorNotifyUuid = Guid(
    '7a8d0002-4f7a-4e6f-9a0b-1f2e3d4c5b6a',
  );

  static final Guid _commandWriteUuid = Guid(
    '7a8d0003-4f7a-4e6f-9a0b-1f2e3d4c5b6a',
  );

  static const String _deviceName = 'Bike Console';

  static const String _savedDeviceIdKey = 'bike_device_id';
  static const String _savedDeviceNameKey = 'bike_device_name';

  ConsoleConnectionState _connectionState = ConsoleConnectionState.disconnected;
  BikeSensorPacket _lastPacket = BikeSensorPacket.empty();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _sensorNotifyCharacteristic;
  BluetoothCharacteristic? _commandWriteCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  Timer? _rssiTimer;
  Timer? _reconnectTimer;

  int? _latestRssi;
  int _connectionGeneration = 0;

  bool _isDisposed = false;
  bool _manualDisconnect = false;
  bool _isConnecting = false;
  bool _autoReconnectEnabled = false;
  bool _hadConnectedOnce = false;

  String? _savedDeviceId;
  String? _savedDeviceName;

  void Function(BikeSensorPacket packet)? onPacket;
  void Function(ConsoleConnectionState state)? onConnectionStateChanged;

  ConsoleConnectionState get connectionState => _connectionState;
  BikeSensorPacket get lastPacket => _lastPacket;

  bool get isConnected => _connectionState == ConsoleConnectionState.connected;

  String? get savedDeviceId => _savedDeviceId;
  String? get savedDeviceName => _savedDeviceName;

  String? get connectedDeviceName => _device?.platformName;
  String? get connectedDeviceId => _device?.remoteId.str;
  int? get latestRssi => _latestRssi;

  bool get hasSavedConsole => _savedDeviceId != null;

  String? get connectedDeviceDisplayName {
    final name = _device?.platformName.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    return _device?.remoteId.str;
  }

  String? get consoleDisplayName {
    return connectedDeviceDisplayName ?? _savedDeviceName;
  }

  Future<void> initialize() async {
    await _loadSavedConsole();

    if (_savedDeviceId == null) {
      setConnectionState(ConsoleConnectionState.disconnected);
      return;
    }

    _manualDisconnect = false;
    _autoReconnectEnabled = true;

    await connectToBikeConsole();
  }

  Future<void> _loadSavedConsole() async {
    final prefs = await SharedPreferences.getInstance();

    _savedDeviceId = prefs.getString(_savedDeviceIdKey);
    _savedDeviceName = prefs.getString(_savedDeviceNameKey);
  }

  Future<void> _saveConsole(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();

    final name = device.platformName.trim().isNotEmpty
        ? device.platformName.trim()
        : _deviceName;

    _savedDeviceId = device.remoteId.str;
    _savedDeviceName = name;

    await prefs.setString(_savedDeviceIdKey, _savedDeviceId!);
    await prefs.setString(_savedDeviceNameKey, _savedDeviceName!);
  }

  Future<void> pairWithDevice(BluetoothDevice device) async {
    _manualDisconnect = false;
    _autoReconnectEnabled = true;

    setConnectionState(ConsoleConnectionState.available);

    await _connectToDevice(device, saveDevice: true);
  }

  Future<void> forgetConsole() async {
    _connectionGeneration++;

    _manualDisconnect = true;
    _autoReconnectEnabled = false;
    _hadConnectedOnce = false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await FlutterBluePlus.stopScan();

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    await _notifySubscription?.cancel();
    _notifySubscription = null;

    _stopRssiUpdates();

    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;

    try {
      await _sensorNotifyCharacteristic?.setNotifyValue(false);
    } catch (_) {
      // Ignore cleanup errors.
    }

    try {
      await _device?.disconnect();
    } catch (_) {
      // Ignore cleanup errors.
    }

    _device = null;
    _sensorNotifyCharacteristic = null;
    _commandWriteCharacteristic = null;

    _savedDeviceId = null;
    _savedDeviceName = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedDeviceIdKey);
    await prefs.remove(_savedDeviceNameKey);

    setConnectionState(ConsoleConnectionState.disconnected);
    notifyListeners();
  }

  Future<void> connectToBikeConsole() async {
    if (_isDisposed || _isConnecting || isConnected) return;

    final generation = ++_connectionGeneration;

    _manualDisconnect = false;
    _isConnecting = true;

    setConnectionState(ConsoleConnectionState.scanning);

    try {
      final device = await _scanForConsole(
        generation: generation,
        timeout: const Duration(seconds: 5),
      );

      if (_isDisposed ||
          _manualDisconnect ||
          generation != _connectionGeneration) {
        return;
      }

      if (device == null) {
        setConnectionState(ConsoleConnectionState.offline);
        _scheduleReconnect(fromOffline: true);
        return;
      }

      setConnectionState(ConsoleConnectionState.available);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      if (_isDisposed ||
          _manualDisconnect ||
          generation != _connectionGeneration) {
        return;
      }

      setConnectionState(ConsoleConnectionState.connecting);

      await _connectToDevice(device);
    } catch (error) {
      debugPrint('Bike BLE connect failed: $error');

      if (!_manualDisconnect && _autoReconnectEnabled && !_isDisposed) {
        setConnectionState(ConsoleConnectionState.offline);
        _scheduleReconnect(fromOffline: true);
      }
    } finally {
      _isConnecting = false;
    }
  }

  Future<BluetoothDevice?> _scanForConsole({
    required int generation,
    required Duration timeout,
  }) async {
    await FlutterBluePlus.stopScan();

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    final completer = Completer<BluetoothDevice?>();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (_isDisposed ||
          _manualDisconnect ||
          generation != _connectionGeneration) {
        return;
      }

      for (final result in results) {
        if (_isMatchingConsole(result)) {
          if (!completer.isCompleted) {
            completer.complete(result.device);
          }
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: timeout);

    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }
  }

  bool _isMatchingConsole(ScanResult result) {
    final deviceId = result.device.remoteId.str;
    final platformName = result.device.platformName.trim();
    final advName = result.advertisementData.advName.trim();

    final nameMatches = platformName == _deviceName || advName == _deviceName;

    final serviceMatches = result.advertisementData.serviceUuids.any(
      (uuid) =>
          uuid.toString().toLowerCase() ==
          _serviceUuid.toString().toLowerCase(),
    );

    final savedIdMatches = _savedDeviceId != null && deviceId == _savedDeviceId;

    return savedIdMatches || nameMatches || serviceMatches;
  }

  Future<void> _connectToDevice(
    BluetoothDevice device, {
    bool saveDevice = false,
  }) async {
    _device = device;

    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = device.connectionState.listen((state) {
      if (_isDisposed || _manualDisconnect) return;

      if (state == BluetoothConnectionState.disconnected) {
        _sensorNotifyCharacteristic = null;
        _commandWriteCharacteristic = null;
        _stopRssiUpdates();

        if (_connectionState == ConsoleConnectionState.connected) {
          setConnectionState(ConsoleConnectionState.lostDuringRide);

          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (_isDisposed || _manualDisconnect || isConnected) return;
            setConnectionState(ConsoleConnectionState.reconnecting);
            _scheduleReconnect(fromOffline: false);
          });
        }
      }
    });

    await device.connect(
      timeout: const Duration(seconds: 12),
      autoConnect: false,
      license: License.nonprofit,
    );

    try {
      await device.requestMtu(185);
    } catch (error) {
      debugPrint('MTU request failed, continuing anyway: $error');
    }

    final services = await device.discoverServices();

    BluetoothCharacteristic? notifyCharacteristic;
    BluetoothCharacteristic? writeCharacteristic;

    for (final service in services) {
      if (service.uuid != _serviceUuid) continue;

      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _sensorNotifyUuid) {
          notifyCharacteristic = characteristic;
        } else if (characteristic.uuid == _commandWriteUuid) {
          writeCharacteristic = characteristic;
        }
      }
    }

    if (notifyCharacteristic == null || writeCharacteristic == null) {
      throw StateError('Bike BLE characteristics not found');
    }

    _sensorNotifyCharacteristic = notifyCharacteristic;
    _commandWriteCharacteristic = writeCharacteristic;

    await _notifySubscription?.cancel();
    _notifySubscription = notifyCharacteristic.onValueReceived.listen((value) {
      final raw = utf8.decode(value, allowMalformed: true).trim();
      if (raw.isEmpty) return;

      handleIncomingJson(raw);
    });

    await notifyCharacteristic.setNotifyValue(true);

    if (saveDevice || _savedDeviceId == null) {
      await _saveConsole(device);
    }

    _hadConnectedOnce = true;

    setConnectionState(ConsoleConnectionState.connected);
    _startRssiUpdates();

    debugPrint('Bike BLE connected: ${device.platformName} ${device.remoteId}');
  }

  void _scheduleReconnect({required bool fromOffline}) {
    if (_isDisposed || _manualDisconnect || !_autoReconnectEnabled) return;

    _reconnectTimer?.cancel();

    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      if (_isDisposed || _manualDisconnect || isConnected || _isConnecting) {
        return;
      }

      if (!fromOffline && _hadConnectedOnce) {
        setConnectionState(ConsoleConnectionState.reconnecting);
      }

      await connectToBikeConsole();
    });
  }

  void _startRssiUpdates() {
    _rssiTimer?.cancel();

    _readRssiOnce();

    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _readRssiOnce();
    });
  }

  Future<void> _readRssiOnce() async {
    if (_isDisposed || !isConnected) return;

    final device = _device;
    if (device == null) return;

    try {
      final rssi = await device.readRssi();

      if (_latestRssi == rssi) return;

      _latestRssi = rssi;
      notifyListeners();
    } catch (error) {
      debugPrint('RSSI read failed: $error');
    }
  }

  void _stopRssiUpdates({bool clear = true}) {
    _rssiTimer?.cancel();
    _rssiTimer = null;

    if (clear && _latestRssi != null) {
      _latestRssi = null;

      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  String encodeCommand(BikeCommand command) {
    return jsonEncode(command.toJson());
  }

  void handleIncomingJson(String raw) {
    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      _lastPacket = BikeSensorPacket.fromJson(decoded);

      onPacket?.call(_lastPacket);

      notifyListeners();
    } catch (error) {
      debugPrint('Bike packet parse failed: $error | raw=$raw');
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

  Future<void> sendCommand(BikeCommand command) async {
    final encoded = encodeCommand(command);

    debugPrint('BikeCommand -> $encoded');

    final characteristic = _commandWriteCharacteristic;

    if (!isConnected || characteristic == null) {
      debugPrint('BikeCommand skipped because BLE is not connected');
      return;
    }

    try {
      await characteristic.write(utf8.encode(encoded), withoutResponse: true);
    } catch (error) {
      debugPrint('BikeCommand write failed: $error');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoReconnectEnabled = false;
    _manualDisconnect = true;

    _reconnectTimer?.cancel();

    FlutterBluePlus.stopScan();

    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _notifySubscription?.cancel();

    _stopRssiUpdates(clear: false);

    try {
      _sensorNotifyCharacteristic?.setNotifyValue(false);
    } catch (_) {
      // Ignore dispose cleanup errors.
    }

    try {
      _device?.disconnect();
    } catch (_) {
      // Ignore dispose cleanup errors.
    }

    super.dispose();
  }
}

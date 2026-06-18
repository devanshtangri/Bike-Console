from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    full = ROOT / path
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Patch failed for {label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# RideControlBar: restore proper blocked console UX and prevent sticky Starting.
# ---------------------------------------------------------------------------
ride_bar_path = "lib/widgets/ride_control_bar.dart"
ride_bar = read(ride_bar_path)

ride_bar = replace_once(
    ride_bar,
    "    required this.onStop,\n    this.onBlockedStart,\n  });",
    "    required this.onStop,\n    this.onBlockedStart,\n    this.blockedStartLabel = \"Pair a Console\",\n  });",
    "RideControlBar constructor blockedStartLabel",
)

ride_bar = replace_once(
    ride_bar,
    "  final VoidCallback onStop;\n  final VoidCallback? onBlockedStart;\n",
    "  final VoidCallback onStop;\n  final VoidCallback? onBlockedStart;\n  final String blockedStartLabel;\n",
    "RideControlBar blockedStartLabel field",
)

ride_bar = replace_once(
    ride_bar,
    "  VoidCallback get onStop => widget.onStop;\n  VoidCallback? get onBlockedStart => widget.onBlockedStart;\n",
    "  VoidCallback get onStop => widget.onStop;\n  VoidCallback? get onBlockedStart => widget.onBlockedStart;\n  String get blockedStartLabel => widget.blockedStartLabel;\n",
    "RideControlBar blockedStartLabel getter",
)

ride_bar = replace_once(
    ride_bar,
    '''  void _handleStartTap() {
    if (_startVisualPrimed) return;

    setState(() {
      _startVisualPrimed = true;
    });

    _startPrimeTimer?.cancel();
    _startPrimeTimer = Timer(const Duration(milliseconds: 210), () {
      if (!mounted) return;
      onStart();
    });
  }''',
    '''  void _handleStartTap() {
    if (_startVisualPrimed) return;

    setState(() {
      _startVisualPrimed = true;
    });

    _startPrimeTimer?.cancel();
    _startPrimeTimer = Timer(const Duration(milliseconds: 210), () {
      if (!mounted) return;
      onStart();

      // Smart Start may open a setup/permission sheet instead of beginning the
      // countdown. In that case the ride state stays stopped, so reset the
      // temporary visual prime instead of leaving the button stuck on Starting.
      Future.delayed(const Duration(milliseconds: 520), () {
        if (!mounted) return;
        if (rideState == RideState.stopped && _startVisualPrimed) {
          setState(() {
            _startVisualPrimed = false;
          });
        }
      });
    });
  }''',
    "RideControlBar start visual reset",
)

ride_bar = ride_bar.replace('''    final label = isBlockedStart
        ? "Set Up Ride"''', '''    final label = isBlockedStart
        ? blockedStartLabel''', 1)

write(ride_bar_path, ride_bar)


# ---------------------------------------------------------------------------
# Dashboard: blocked console button should be red again, with a contextual label.
# Setup actions should not recursively trap the button/sheet state.
# ---------------------------------------------------------------------------
dashboard_path = "lib/screens/dashboard_screen.dart"
dashboard = read(dashboard_path)

# Add helper before _handleSmartStart.
dashboard = replace_once(
    dashboard,
    "  Future<void> _handleSmartStart() async {",
    '''  String _blockedStartLabel() {
    final connection = widget.bikeConsoleController.connectionController;

    if (!connection.hasSavedConsole) {
      return "Pair a Console";
    }

    if (!connection.isConnected) {
      return "Connect Console";
    }

    return "Set Up Ride";
  }

  Future<void> _handleSmartStart() async {''',
    "dashboard blocked start label helper",
)

old_handle_action = '''  Future<void> _handleRideSetupAction(RideStartRequirement requirement) async {
    switch (requirement) {
      case RideStartRequirement.locationPermission:
        await _rideStartGateService.requestLocationPermission();
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

    // Let permission dialogs, Bluetooth state, and BLE callbacks settle before
    // deciding whether to start or show the next missing setup item.
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final nextReadiness = await _rideStartGateService.check(
      widget.bikeConsoleController,
    );

    if (!mounted) return;

    if (nextReadiness.canStart) {
      await _startRideWithCountdown();
      return;
    }

    await _showRideSetupSheet(nextReadiness);
  }'''

new_handle_action = '''  Future<void> _handleRideSetupAction(RideStartRequirement requirement) async {
    final opensExternalSettings =
        requirement == RideStartRequirement.locationServices;

    switch (requirement) {
      case RideStartRequirement.locationPermission:
        await _rideStartGateService.requestLocationPermission();
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
  }'''

dashboard = replace_once(
    dashboard,
    old_handle_action,
    new_handle_action,
    "dashboard setup action loop/reset",
)

# Restore strict start button blocking for missing console.
dashboard = replace_once(
    dashboard,
    '''                          canStart: rideState.rideState == RideState.stopped,
''',
    '''                          canStart: widget
                              .bikeConsoleController
                              .rideSessionController
                              .canStartRide,
''',
    "dashboard strict RideControlBar canStart",
)

# Add contextual blocked label to RideControlBar call.
dashboard = replace_once(
    dashboard,
    '''                          onStart: _handleSmartStart,
                          onBlockedStart: _handleSmartStart,
                          onPause: widget
''',
    '''                          onStart: _handleSmartStart,
                          onBlockedStart: _handleSmartStart,
                          blockedStartLabel: _blockedStartLabel(),
                          onPause: widget
''',
    "dashboard RideControlBar blockedStartLabel arg",
)

write(dashboard_path, dashboard)

print("Batch 6A Smart Start hotfix applied.")

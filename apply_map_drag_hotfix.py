from pathlib import Path

ROOT = Path.cwd()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Patch failed for {label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)

controller_path = ROOT / "lib" / "controllers" / "map_tracking_controller.dart"
dashboard_path = ROOT / "lib" / "screens" / "dashboard_screen.dart"

controller = controller_path.read_text(encoding="utf-8")
dashboard = dashboard_path.read_text(encoding="utf-8")

old_controller = '''  void onUserMovedMap() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (_isProgrammaticCameraMove || nowMs < _ignoreCameraMoveStartedUntilMs) {
      return;
    }

    if (!_followUser) {
      return;
    }

    _followUser = false;
    _stopFollowCameraTimer();
    notifyListeners();
  }
'''

new_controller = '''  void onUserMovedMap() {
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
'''
controller = replace_once(controller, old_controller, new_controller, "forced map-touch follow disable")

old_dashboard = '''                          child: GoogleMap(
                            initialCameraPosition: const CameraPosition(
                              target: LatLng(28.6139, 77.2090),
                              zoom: MapTrackingController.navigationMapZoom,
                              tilt: MapTrackingController.navigationMapTilt,
                            ),
                            onMapCreated: (controller) {
                              _mapTrackingController.attachMapController(
                                controller,
                              );
                            },
                            style: darkMapStyle,
                            onCameraMoveStarted: () {
                              _mapTrackingController.onUserMovedMap();
                            },
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            compassEnabled: false,
                            rotateGesturesEnabled: true,
                            tiltGesturesEnabled: true,
                            padding: const EdgeInsets.only(bottom: 115),
                            markers: _mapTrackingController.markers,
                            polylines: _mapTrackingController.polylines,
                          ),
'''

new_dashboard = '''                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) {
                              _mapTrackingController.onUserTouchedMap();
                            },
                            child: GoogleMap(
                              initialCameraPosition: const CameraPosition(
                                target: LatLng(28.6139, 77.2090),
                                zoom: MapTrackingController.navigationMapZoom,
                                tilt: MapTrackingController.navigationMapTilt,
                              ),
                              onMapCreated: (controller) {
                                _mapTrackingController.attachMapController(
                                  controller,
                                );
                              },
                              style: darkMapStyle,
                              onCameraMoveStarted: () {
                                _mapTrackingController.onUserMovedMap();
                              },
                              myLocationEnabled: false,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              compassEnabled: false,
                              rotateGesturesEnabled: true,
                              tiltGesturesEnabled: true,
                              padding: const EdgeInsets.only(bottom: 115),
                              markers: _mapTrackingController.markers,
                              polylines: _mapTrackingController.polylines,
                            ),
                          ),
'''
dashboard = replace_once(dashboard, old_dashboard, new_dashboard, "dashboard map touch listener")

controller_path.write_text(controller, encoding="utf-8")
dashboard_path.write_text(dashboard, encoding="utf-8")

print("Map drag hotfix applied.")

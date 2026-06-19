from pathlib import Path

ROOT = Path.cwd()

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Patch failed for {label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)

dashboard_path = ROOT / "lib" / "screens" / "dashboard_screen.dart"
dashboard = dashboard_path.read_text(encoding="utf-8")

# Pointer event types are used by the threshold handlers below.
if "import 'package:flutter/gestures.dart';" not in dashboard:
    dashboard = replace_once(
        dashboard,
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/gestures.dart';\nimport 'package:flutter/material.dart';\n",
        "gestures import",
    )

old_fields = '''  int? _countdownValue;
  bool _manualReconnectPulse = false;
'''
new_fields = '''  static const double _mapDragDisableFollowThresholdPx = 8.0;

  int? _countdownValue;
  bool _manualReconnectPulse = false;
  Offset? _mapPointerDownPosition;
  bool _mapPointerDragConsumed = false;
'''
dashboard = replace_once(dashboard, old_fields, new_fields, "map pointer tracking fields")

old_methods_anchor = '''  Future<void> _recenterMap() async {
    AppHaptics.selectionClick();
    await _mapTrackingController.recenter();
  }
'''
new_methods = '''  Future<void> _recenterMap() async {
    AppHaptics.selectionClick();
    await _mapTrackingController.recenter();
  }

  void _handleMapPointerDown(PointerDownEvent event) {
    _mapPointerDownPosition = event.position;
    _mapPointerDragConsumed = false;
  }

  void _handleMapPointerMove(PointerMoveEvent event) {
    final startPosition = _mapPointerDownPosition;

    if (startPosition == null || _mapPointerDragConsumed) {
      return;
    }

    final dragDistance = (event.position - startPosition).distance;

    if (dragDistance < _mapDragDisableFollowThresholdPx) {
      return;
    }

    _mapPointerDragConsumed = true;
    _mapTrackingController.onUserTouchedMap();
  }

  void _handleMapPointerEnd(PointerEvent event) {
    _mapPointerDownPosition = null;
    _mapPointerDragConsumed = false;
  }
'''
dashboard = replace_once(dashboard, old_methods_anchor, new_methods, "map drag threshold handlers")

old_listener = '''                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) {
                              _mapTrackingController.onUserTouchedMap();
                            },
                            child: GoogleMap(
'''
new_listener = '''                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _handleMapPointerDown,
                            onPointerMove: _handleMapPointerMove,
                            onPointerUp: _handleMapPointerEnd,
                            onPointerCancel: _handleMapPointerEnd,
                            child: GoogleMap(
'''
dashboard = replace_once(dashboard, old_listener, new_listener, "map listener threshold behavior")

dashboard_path.write_text(dashboard, encoding="utf-8")

print("Map drag threshold hotfix applied.")

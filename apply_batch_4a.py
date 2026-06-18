from pathlib import Path

path = Path('lib/screens/dashboard_screen.dart')
text = path.read_text(encoding='utf-8')
original = text

old = '''      setState(() {
        _countdownValue = value;
      });

      await Future.delayed(const Duration(milliseconds: 800));
'''
new = '''      setState(() {
        _countdownValue = value;
      });

      AppHaptics.lightImpact();

      await Future.delayed(const Duration(milliseconds: 800));
'''
if old not in text:
    raise SystemExit('Could not find countdown setState block to add haptics.')
text = text.replace(old, new, 1)

old = '''  String _formatSpeedStat(double value) {
    if (value > 99.9) {
      return "${value.toStringAsFixed(0)} km/h";
    }

    return "${value.toStringAsFixed(1)} km/h";
  }

  String _formatDistanceStat(double value) {
'''
new = '''  String _formatSpeedStat(double value) {
    if (value > 99.9) {
      return "${value.toStringAsFixed(0)} km/h";
    }

    return "${value.toStringAsFixed(1)} km/h";
  }

  String _formatMaxSpeedStat(double value) {
    return "${value.toStringAsFixed(0)} km/h";
  }

  String _formatDistanceStat(double value) {
'''
if old not in text:
    raise SystemExit('Could not find speed formatter block to add max speed formatter.')
text = text.replace(old, new, 1)

old = '''                                    value: _formatSpeedStat(
                                      rideState.maxSpeedKmph,
                                    ),
'''
new = '''                                    value: _formatMaxSpeedStat(
                                      rideState.maxSpeedKmph,
                                    ),
'''
if old not in text:
    raise SystemExit('Could not find MAX SPEED card formatter usage.')
text = text.replace(old, new, 1)

if text == original:
    raise SystemExit('No changes were made.')

path.write_text(text, encoding='utf-8')
print('Batch 4A applied successfully: countdown haptics + max speed integer formatting.')

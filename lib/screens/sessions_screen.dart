import 'package:flutter/material.dart';

import '../models/saved_ride_session.dart';
import '../services/app_haptics.dart';
import '../services/ride_history_service.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final RideHistoryService _rideHistoryService = RideHistoryService();

  bool _loading = true;
  bool _selectionModeEnabled = false;

  final Set<String> _selectedSessionIds = {};
  List<SavedRideSession> _sessions = [];

  bool get _hasSessions => _sessions.isNotEmpty;

  bool get _hasSelection => _selectedSessionIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await _rideHistoryService.loadSessions();

    if (!mounted) return;

    setState(() {
      _sessions = sessions;
      _loading = false;
      _selectedSessionIds.removeWhere(
        (id) => !_sessions.any((session) => session.id == id),
      );

      if (_sessions.isEmpty) {
        _selectionModeEnabled = false;
        _selectedSessionIds.clear();
      }
    });
  }

  void _toggleSelectionMode() {
    if (!_hasSessions) return;

    AppHaptics.selectionClick();

    setState(() {
      _selectionModeEnabled = !_selectionModeEnabled;

      if (!_selectionModeEnabled) {
        _selectedSessionIds.clear();
      }
    });
  }

  void _selectAll() {
    if (!_hasSessions) return;

    AppHaptics.selectionClick();

    setState(() {
      _selectionModeEnabled = true;
      _selectedSessionIds
        ..clear()
        ..addAll(_sessions.map((session) => session.id));
    });
  }

  Future<void> _confirmDeleteSelected() async {
    if (!_hasSelection) return;

    AppHaptics.mediumImpact();

    final selectedCount = _selectedSessionIds.length;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121212),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          title: Text(
            selectedCount == 1
                ? "Delete this session?"
                : "Delete $selectedCount sessions?",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            "This cannot be undone.",
            style: TextStyle(color: Colors.white54, height: 1.35),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            TextButton(
              onPressed: () {
                AppHaptics.selectionClick();
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () {
                AppHaptics.mediumImpact();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                "Delete",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) return;

    await _deleteSelected();
  }

  Future<void> _deleteSelected() async {
    if (!_hasSelection) return;

    final deletedCount = _selectedSessionIds.length;
    final idsToDelete = Set<String>.from(_selectedSessionIds);

    await _rideHistoryService.deleteSessionsByIds(idsToDelete);

    if (!mounted) return;

    setState(() {
      _sessions = _sessions
          .where((session) => !idsToDelete.contains(session.id))
          .toList();

      _selectedSessionIds.clear();
      _selectionModeEnabled = _sessions.isNotEmpty;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deletedCount == 1
              ? "Deleted 1 saved session"
              : "Deleted $deletedCount saved sessions",
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _showSessionDetails(SavedRideSession session) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      isScrollControlled: true,
      builder: (_) => _SessionDetailsSheet(session: session),
    );
  }

  _SessionSummary _buildSummary() {
    if (_sessions.isEmpty) {
      return const _SessionSummary(
        totalDistanceKm: 0,
        averageDistanceKm: 0,
        averageDurationMs: 0,
        averageAverageSpeedKmph: 0,
      );
    }

    final totalDistanceKm = _sessions.fold<double>(
      0,
      (sum, session) => sum + session.distanceKm,
    );

    final totalDurationMs = _sessions.fold<int>(
      0,
      (sum, session) => sum + session.activeDurationMs,
    );

    final totalAverageSpeed = _sessions.fold<double>(
      0,
      (sum, session) => sum + session.averageSpeedKmph,
    );

    return _SessionSummary(
      totalDistanceKm: totalDistanceKm,
      averageDistanceKm: totalDistanceKm / _sessions.length,
      averageDurationMs: totalDurationMs ~/ _sessions.length,
      averageAverageSpeedKmph: totalAverageSpeed / _sessions.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedSessionIds.length;
    final summary = _buildSummary();
    final showSessionControls = !_loading && _hasSessions;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _selectionModeEnabled ? "$selectedCount selected" : "Ride Sessions",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: showSessionControls ? _toggleSelectionMode : null,
            child: Text(
              _selectionModeEnabled ? "Cancel" : "Select",
              style: TextStyle(
                color: showSessionControls ? Colors.greenAccent : Colors.white24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (showSessionControls) ...[
              _SessionToolbar(
                hasSessions: _hasSessions,
                hasSelection: _hasSelection,
                onSelectAll: _selectAll,
                onDeleteSelected: _confirmDeleteSelected,
              ),
              _SessionSummaryPanel(
                totalDistanceKm: summary.totalDistanceKm,
                averageDistanceKm: summary.averageDistanceKm,
                averageDurationText: _formatCompactDuration(
                  summary.averageDurationMs,
                ),
                averageAverageSpeedKmph: summary.averageAverageSpeedKmph,
              ),
            ],
            Expanded(
              child: _loading
                  ? const _LoadingSessionsState()
                  : _hasSessions
                  ? RefreshIndicator(
                      color: Colors.greenAccent,
                      backgroundColor: const Color(0xFF121212),
                      onRefresh: _loadSessions,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        itemCount: _sessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final selected = _selectedSessionIds.contains(
                            session.id,
                          );

                          return _SessionCard(
                            session: session,
                            selectionModeEnabled: _selectionModeEnabled,
                            selected: selected,
                            onTap: () {
                              AppHaptics.selectionClick();

                              if (!_selectionModeEnabled) {
                                _showSessionDetails(session);
                                return;
                              }

                              setState(() {
                                if (selected) {
                                  _selectedSessionIds.remove(session.id);
                                } else {
                                  _selectedSessionIds.add(session.id);
                                }
                              });
                            },
                            onLongPress: () {
                              AppHaptics.mediumImpact();
                              setState(() {
                                _selectionModeEnabled = true;
                                _selectedSessionIds.add(session.id);
                              });
                            },
                          );
                        },
                      ),
                    )
                  : const _EmptySessionsState(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.hasSessions,
    required this.hasSelection,
    required this.onSelectAll,
    required this.onDeleteSelected,
  });

  final bool hasSessions;
  final bool hasSelection;
  final VoidCallback onSelectAll;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToolbarButton(
              icon: Icons.done_all_rounded,
              label: "Select All",
              enabled: hasSessions,
              color: Colors.greenAccent,
              onTap: onSelectAll,
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          Expanded(
            child: _ToolbarButton(
              icon: Icons.delete_outline_rounded,
              label: "Delete Selected",
              enabled: hasSelection,
              color: Colors.redAccent,
              onTap: onDeleteSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionSummaryPanel extends StatelessWidget {
  const _SessionSummaryPanel({
    required this.totalDistanceKm,
    required this.averageDistanceKm,
    required this.averageDurationText,
    required this.averageAverageSpeedKmph,
  });

  final double totalDistanceKm;
  final double averageDistanceKm;
  final String averageDurationText;
  final double averageAverageSpeedKmph;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryMetricTile(
                  label: "TOTAL DISTANCE",
                  value: "${totalDistanceKm.toStringAsFixed(2)} km",
                  icon: Icons.route_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryMetricTile(
                  label: "AVG DISTANCE",
                  value: "${averageDistanceKm.toStringAsFixed(2)} km",
                  icon: Icons.timeline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryMetricTile(
                  label: "AVG DURATION",
                  value: averageDurationText,
                  icon: Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryMetricTile(
                  label: "AVG SPEED",
                  value: "${averageAverageSpeedKmph.toStringAsFixed(1)} km/h",
                  icon: Icons.speed_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  const _SummaryMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: Colors.greenAccent.withValues(alpha: 0.82),
            size: 18,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : Colors.white24;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: effectiveColor, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white24,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingSessionsState extends StatelessWidget {
  const _LoadingSessionsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: Colors.greenAccent,
        strokeWidth: 2.4,
      ),
    );
  }
}

class _EmptySessionsState extends StatelessWidget {
  const _EmptySessionsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.route_rounded,
                color: Colors.white38,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No saved sessions yet",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Completed rides will appear here with distance, duration, and speed stats.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.selectionModeEnabled,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final SavedRideSession session;
  final bool selectionModeEnabled;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final dateText = _formatSessionDate(session.endEpochMs);
    final durationText = _formatCompactDuration(session.activeDurationMs);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? Colors.greenAccent.withValues(alpha: 0.80)
                : Colors.white.withValues(alpha: 0.10),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${session.distanceKm.toStringAsFixed(2)} km ride",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selectionModeEnabled)
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? Colors.greenAccent : Colors.white24,
                    size: 24,
                  )
                else
                  const Icon(
                    Icons.expand_more_rounded,
                    color: Colors.white24,
                    size: 24,
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              dateText,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _SessionCardMetric(
                    icon: Icons.timer_outlined,
                    label: "Duration",
                    value: durationText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SessionCardMetric(
                    icon: Icons.speed_outlined,
                    label: "Avg Speed",
                    value: session.averageSpeedKmph.toStringAsFixed(1),
                    unit: "km/h",
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SessionCardMetric(
                    icon: Icons.trending_up_rounded,
                    label: "Max Speed",
                    value: session.maxSpeedKmph.toStringAsFixed(1),
                    unit: "km/h",
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCardMetric extends StatelessWidget {
  const _SessionCardMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: Colors.greenAccent.withValues(alpha: 0.75),
            size: 15,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit!,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 8.8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionDetailsSheet extends StatelessWidget {
  const _SessionDetailsSheet({required this.session});

  final SavedRideSession session;

  @override
  Widget build(BuildContext context) {
    final dateText = _formatSessionDate(session.endEpochMs);
    final durationText = _formatCompactDuration(session.activeDurationMs);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.20),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${session.distanceKm.toStringAsFixed(2)} km ride",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DetailInfoRow(
              icon: Icons.route_outlined,
              label: "Distance",
              value: "${session.distanceKm.toStringAsFixed(2)} km",
            ),
            _DetailInfoRow(
              icon: Icons.timer_outlined,
              label: "Active Duration",
              value: durationText,
            ),
            _DetailInfoRow(
              icon: Icons.speed_outlined,
              label: "Average Speed",
              value: "${session.averageSpeedKmph.toStringAsFixed(1)} km/h",
            ),
            _DetailInfoRow(
              icon: Icons.trending_up_rounded,
              label: "Max Speed",
              value: "${session.maxSpeedKmph.toStringAsFixed(1)} km/h",
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.greenAccent.withValues(alpha: 0.78),
            size: 19,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionSummary {
  const _SessionSummary({
    required this.totalDistanceKm,
    required this.averageDistanceKm,
    required this.averageDurationMs,
    required this.averageAverageSpeedKmph,
  });

  final double totalDistanceKm;
  final double averageDistanceKm;
  final int averageDurationMs;
  final double averageAverageSpeedKmph;
}

String _formatCompactDuration(int durationMs) {
  final totalSeconds = durationMs ~/ 1000;
  final totalMinutes = totalSeconds ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return "${hours}h ${minutes.toString().padLeft(2, "0")}m";
  }

  if (minutes > 0) {
    return "${minutes}m";
  }

  return "${seconds}s";
}

String _formatSessionDate(int epochMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);

  final day = date.day.toString().padLeft(2, "0");
  final month = date.month.toString().padLeft(2, "0");
  final year = date.year.toString();

  final hour = date.hour.toString().padLeft(2, "0");
  final minute = date.minute.toString().padLeft(2, "0");

  return "$day/$month/$year $hour:$minute";
}

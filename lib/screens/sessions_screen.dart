import 'package:flutter/material.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool _selectionModeEnabled = false;
  final Set<String> _selectedSessionIds = {};

  // Temporary empty list. Later this will come from RideHistoryService.
  final List<_SessionPreview> _sessions = const [];

  bool get _hasSessions => _sessions.isNotEmpty;

  bool get _hasSelection => _selectedSessionIds.isNotEmpty;

  void _toggleSelectionMode() {
    if (!_hasSessions) return;

    setState(() {
      _selectionModeEnabled = !_selectionModeEnabled;

      if (!_selectionModeEnabled) {
        _selectedSessionIds.clear();
      }
    });
  }

  void _selectAll() {
    if (!_hasSessions) return;

    setState(() {
      _selectionModeEnabled = true;
      _selectedSessionIds
        ..clear()
        ..addAll(_sessions.map((session) => session.id));
    });
  }

  void _deleteSelected() {
    if (!_hasSelection) return;

    // This will be wired once real saved sessions exist.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Saved session deletion will be added with ride history storage.",
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedSessionIds.length;

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
            onPressed: _hasSessions ? _toggleSelectionMode : null,
            child: Text(
              _selectionModeEnabled ? "Cancel" : "Select",
              style: TextStyle(
                color: _hasSessions ? Colors.greenAccent : Colors.white24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SessionToolbar(
              hasSessions: _hasSessions,
              hasSelection: _hasSelection,
              onSelectAll: _selectAll,
              onDeleteSelected: _deleteSelected,
            ),
            const _SessionSummaryPanel(
              totalDistanceKm: 0,
              averageDistanceKm: 0,
              averageDurationText: "0m",
              averageAverageSpeedKmph: 0,
            ),
            Expanded(
              child: _hasSessions
                  ? ListView.separated(
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
                            if (!_selectionModeEnabled) {
                              // Detail screen comes later.
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
                            setState(() {
                              _selectionModeEnabled = true;
                              _selectedSessionIds.add(session.id);
                            });
                          },
                        );
                      },
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
              "Completed rides will appear here with distance, duration, speed stats, and route details once ride history storage is added.",
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

  final _SessionPreview session;
  final bool selectionModeEnabled;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.map_outlined,
                color: Colors.white30,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    session.subtitle,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
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
                Icons.chevron_right_rounded,
                color: Colors.white24,
                size: 26,
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionPreview {
  const _SessionPreview({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}

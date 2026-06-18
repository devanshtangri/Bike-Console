import 'dart:async';

import 'package:flutter/material.dart';
import '../models/ride_models.dart';
import '../services/app_haptics.dart';
import '../theme/app_colors.dart';

class RideControlBar extends StatefulWidget {
  const RideControlBar({
    super.key,
    required this.rideState,
    required this.canStart,
    required this.timerText,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.onBlockedStart,
    this.blockedStartLabel = "Pair a Console",
  });

  final RideState rideState;
  final bool canStart;
  final String timerText;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback? onBlockedStart;
  final String blockedStartLabel;

  @override
  State<RideControlBar> createState() => _RideControlBarState();
}

class _RideControlBarState extends State<RideControlBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blockedTapController;
  late final Animation<double> _blockedTapAnimation;

  Timer? _startPrimeTimer;
  bool _startVisualPrimed = false;

  RideState get rideState => widget.rideState;
  bool get canStart => widget.canStart;
  String get timerText => widget.timerText;
  VoidCallback get onStart => widget.onStart;
  VoidCallback get onPause => widget.onPause;
  VoidCallback get onResume => widget.onResume;
  VoidCallback get onStop => widget.onStop;
  VoidCallback? get onBlockedStart => widget.onBlockedStart;
  String get blockedStartLabel => widget.blockedStartLabel;

  bool get _isStopped => rideState == RideState.stopped;
  bool get _isRunning => rideState == RideState.running;
  bool get _isPaused => rideState == RideState.paused;
  bool get _isCountdown => rideState == RideState.countdown;
  bool get _isVisuallyStarting => _isCountdown || _startVisualPrimed;
  bool get _showActiveRideLayout => _isRunning || _isPaused;

  @override
  void initState() {
    super.initState();

    _blockedTapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _blockedTapAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -9), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -9, end: 9), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 9, end: -6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(
            parent: _blockedTapController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

  @override
  void didUpdateWidget(covariant RideControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.rideState != RideState.stopped && _startVisualPrimed) {
      _startVisualPrimed = false;
      _startPrimeTimer?.cancel();
      _startPrimeTimer = null;
    }
  }

  @override
  void dispose() {
    _startPrimeTimer?.cancel();
    _blockedTapController.dispose();
    super.dispose();
  }

  void _handleBlockedStartTap() {
    AppHaptics.mediumImpact();

    final handler = onBlockedStart;
    if (handler != null) {
      handler();
      return;
    }

    _blockedTapController.forward(from: 0);
  }

  void _handleStartTap() {
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
  }

  Future<void> _showStopConfirmation(BuildContext context) async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF181818),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text("End Ride?", style: TextStyle(color: Colors.white)),
          content: const Text(
            "Are you sure you want to stop and finish this ride?",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AppHaptics.selectionClick();
                Navigator.pop(context, false);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () {
                AppHaptics.mediumImpact();
                Navigator.pop(context, true);
              },
              child: const Text(
                "Stop",
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (shouldStop == true) {
      onStop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: _rideControlContent(context),
      ),
    );
  }

  Widget _rideControlContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        final timerWidth = totalWidth * 0.42;
        const gapWidth = 12.0;

        return Row(
          children: [
            ClipRect(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 620),
                curve: Curves.easeInOutCubic,
                width: _showActiveRideLayout ? timerWidth : 0,
                child: AnimatedOpacity(
                  opacity: _showActiveRideLayout ? 1 : 0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white),
                        const SizedBox(width: 12),
                        Text(
                          timerText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            AnimatedContainer(
              duration: const Duration(milliseconds: 620),
              curve: Curves.easeInOutCubic,
              width: _showActiveRideLayout ? gapWidth : 0,
            ),

            Expanded(
              child: SizedBox(height: 54, child: _rideActionButton(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _rideActionButton(BuildContext context) {
    final isStart = _isStopped;
    final isPaused = _isPaused;
    final isBlockedStart = isStart && !canStart;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: isBlockedStart
              ? Colors.redAccent
              : isPaused || isStart || _isVisuallyStarting
              ? AppColors.premiumGreen
              : const Color(0xFFFFC928),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isCountdown || _startVisualPrimed
                    ? null
                    : () {
                        if (isBlockedStart) {
                          _handleBlockedStartTap();
                          return;
                        }

                        if (_isStopped) {
                          _handleStartTap();
                        } else if (_isRunning) {
                          AppHaptics.selectionClick();
                          onPause();
                        } else if (_isPaused) {
                          AppHaptics.selectionClick();
                          onResume();
                        }
                      },
                child: AnimatedBuilder(
                  animation: _blockedTapAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                        isBlockedStart ? _blockedTapAnimation.value : 0,
                        0,
                      ),
                      child: child,
                    );
                  },
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 620),
                    curve: Curves.easeInOutCubic,
                    padding: EdgeInsets.only(
                      left: isPaused ? 8 : 0,
                      right: isPaused ? 70 : 0,
                    ),
                    child: Center(
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            reverseDuration: const Duration(milliseconds: 200),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [...previousChildren, ?currentChild],
                              );
                            },
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: _rideActionContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              top: 11,
              bottom: 11,
              right: 58,
              child: AnimatedOpacity(
                opacity: isPaused ? 1 : 0,
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeInOutCubic,
                child: Container(width: 1, color: Colors.black26),
              ),
            ),

            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 58,
              child: IgnorePointer(
                ignoring: !isPaused,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    AppHaptics.mediumImpact();
                    _showStopConfirmation(context);
                  },
                  child: AnimatedOpacity(
                    opacity: isPaused ? 1 : 0,
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeInOutCubic,
                    child: Center(
                      child: AnimatedScale(
                        scale: isPaused ? 1 : 0.82,
                        duration: const Duration(milliseconds: 560),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.stop_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideActionContent() {
    final isStart = _isStopped;
    final isPaused = _isPaused;
    final isBlockedStart = isStart && !canStart;
    final isStarting = _isVisuallyStarting;

    final IconData? icon = isStarting
        ? null
        : isBlockedStart
        ? Icons.memory_rounded
        : isStart || isPaused
        ? Icons.play_arrow_rounded
        : Icons.pause_rounded;

    final label = isBlockedStart
        ? blockedStartLabel
        : isStarting
        ? "Starting"
        : isStart
        ? "Start"
        : isPaused
        ? "Resume"
        : "Pause";

    return Row(
      key: ValueKey(label),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.black, size: isStart ? 28 : 24),
          SizedBox(width: isStart ? 8 : 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: Colors.black,
            fontSize: isBlockedStart
                ? 18
                : isStart || isStarting
                ? 21
                : 20,
            fontWeight: isStart || isStarting
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

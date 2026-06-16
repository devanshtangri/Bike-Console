import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum RideControlState { stopped, running, paused }

class RideControlBar extends StatefulWidget {
  const RideControlBar({super.key});

  @override
  State<RideControlBar> createState() => _RideControlBarState();
}

class _RideControlBarState extends State<RideControlBar> {
  RideControlState _rideState = RideControlState.stopped;

  bool get _isStopped => _rideState == RideControlState.stopped;
  bool get _isPaused => _rideState == RideControlState.paused;

  Future<void> _showStopConfirmation() async {
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
                Navigator.pop(context, false);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () {
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
      setState(() {
        _rideState = RideControlState.stopped;
      });

      // Later: reset ride data / save ride / navigate to summary.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF181818).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Align(
            alignment: Alignment.center,
            child: _rideControlContent(),
          ),
        ),
      ),
    );
  }

  Widget _rideControlContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        final timerWidth = totalWidth * 0.46;
        const gapWidth = 12.0;

        return Row(
          children: [
            ClipRect(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 620),
                curve: Curves.easeInOutCubic,
                width: _isStopped ? 0 : timerWidth,
                child: AnimatedOpacity(
                  opacity: _isStopped ? 0 : 1,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          "2:15:02",
                          style: TextStyle(
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
              width: _isStopped ? 0 : gapWidth,
            ),

            Expanded(
              child: ClipRect(
                child: SizedBox(
                  height: 54,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    reverseDuration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _isPaused ? _pausedControls() : _primaryRideButton(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _primaryRideButton() {
    final isStart = _isStopped;

    return GestureDetector(
      key: ValueKey(isStart ? "start_button" : "pause_button"),
      onTap: () {
        setState(() {
          _rideState = isStart
              ? RideControlState.running
              : RideControlState.paused;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isStart ? AppColors.premiumGreen : const Color(0xFFFFC928),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.96,
                        end: 1.0,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Row(
                  key: ValueKey(isStart ? "start_content" : "pause_content"),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isStart ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: Colors.black,
                      size: isStart ? 28 : 24,
                    ),
                    SizedBox(width: isStart ? 8 : 6),
                    Text(
                      isStart ? "Start" : "Pause",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: isStart ? 21 : 20,
                        fontWeight: isStart ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pausedControls() {
    return AnimatedContainer(
      key: const ValueKey("paused_controls"),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.premiumGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _rideState = RideControlState.running;
                });
              },
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                    SizedBox(width: 4),
                    Text(
                      "Resume",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          AnimatedOpacity(
            opacity: _isPaused ? 1 : 0,
            duration: const Duration(milliseconds: 420),
            child: Container(width: 1, height: 32, color: Colors.black26),
          ),

          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: _showStopConfirmation,
              child: Center(
                child: AnimatedScale(
                  scale: _isPaused ? 1 : 0.85,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
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
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class RideControlBar extends StatefulWidget {
  final double screenWidth;

  const RideControlBar({super.key, required this.screenWidth});

  @override
  State<RideControlBar> createState() => _RideControlBarState();
}

class _RideControlBarState extends State<RideControlBar> {
  bool isPaused = false;

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
        isPaused = false;
      });

      // Later: reset ride data / save ride / navigate to summary.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white),

          const SizedBox(width: 12),

          const Text(
            "2:15:02",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          const SizedBox(width: 16),

          SizedBox(
            width: widget.screenWidth * 0.45,
            height: 54,
            child: isPaused ? _pausedControls() : _pauseButton(),
          ),
        ],
      ),
    );
  }

  Widget _pauseButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          isPaused = true;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFC928),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pause_rounded, color: Colors.black, size: 24),
              SizedBox(width: 6),
              Text(
                "Pause",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pausedControls() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.greenAccent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isPaused = false;
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

          Container(width: 1, height: 32, color: Colors.black26),

          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: _showStopConfirmation,
              child: const Center(
                child: Icon(Icons.stop_rounded, color: Colors.red, size: 27),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

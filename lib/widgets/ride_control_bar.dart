import 'package:flutter/material.dart';

class RideControlBar extends StatelessWidget {
  final double screenWidth;

  const RideControlBar({
    super.key,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.timer_outlined,
            color: Colors.white,
          ),

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

          Container(
            width: 1,
            height: 40,
            color: Colors.white10,
          ),

          const SizedBox(width: 20),

          Container(
            width: screenWidth * 0.38,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Center(
              child: Text(
                "Pause",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
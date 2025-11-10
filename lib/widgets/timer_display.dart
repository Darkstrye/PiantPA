import 'dart:ui';
import 'package:flutter/material.dart';

class TimerDisplay extends StatelessWidget {
  final Duration duration;
  final String title;
  final Color? accentColor;

  const TimerDisplay({
    super.key,
    required this.duration,
    this.title = 'Elapsed Time',
    this.accentColor,
  });

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Color titleColor = accentColor ?? Colors.blue.shade900;
    final Color backgroundColor =
        accentColor != null ? accentColor!.withOpacity(0.1) : Colors.blue.shade50;
    final Color borderColor =
        accentColor != null ? accentColor!.withOpacity(0.3) : Colors.blue.shade200;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatDuration(duration),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: titleColor,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}


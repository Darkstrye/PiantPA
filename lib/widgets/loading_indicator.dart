import 'package:flutter/material.dart';

/// A styled loading indicator with optional message text.
/// Can be used as a full-screen overlay or inline widget.
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final Color? color;
  final double size;
  final double strokeWidth;

  const LoadingIndicator({
    super.key,
    this.message,
    this.color,
    this.size = 48.0,
    this.strokeWidth = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    final indicatorColor = color ?? Theme.of(context).colorScheme.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// A full-screen loading overlay that can be shown on top of content.
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;
  final Color? barrierColor;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.barrierColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: barrierColor ?? Colors.black.withOpacity(0.3),
            child: LoadingIndicator(
              message: message,
              color: Colors.white,
            ),
          ),
      ],
    );
  }
}



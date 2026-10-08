import 'package:flutter/material.dart';

/// Quick, modern floating pill toast to replace long, heavy bottom snackbars.
/// Displays centered, compact, and automatically dismisses in ~1.5 seconds.
class QuickAlert {
  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor ?? const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        elevation: 3,
        margin: const EdgeInsets.only(bottom: 24, left: 36, right: 36),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  static void success(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: const Color(0xFF059669),
      icon: Icons.check_circle_rounded,
      duration: const Duration(milliseconds: 1600),
    );
  }

  static void error(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: const Color(0xFFDC2626),
      icon: Icons.error_outline_rounded,
      duration: const Duration(milliseconds: 1800),
    );
  }

  static void info(BuildContext context, String message) {
    show(
      context,
      message,
      backgroundColor: const Color(0xFF1E293B),
      icon: Icons.info_outline_rounded,
      duration: const Duration(milliseconds: 1500),
    );
  }
}

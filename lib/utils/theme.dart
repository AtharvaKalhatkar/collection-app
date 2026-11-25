import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Executive Corporate Palette
  static const Color primary = Color(0xFF0F172A); // Slate 900
  static const Color primaryLight = Color(0xFF1E293B); // Slate 800
  static const Color secondary = Color(0xFF0284C7); // Sky Blue 600
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF64748B); // Slate 500
  static const Color success = Color(0xFF10B981); // Emerald 500

  // Financial Status & Payment Mode Colors
  static const Color cashColor = Color(0xFF059669); // Emerald 600
  static const Color upiColor = Color(0xFF2563EB); // Royal Blue 600
  static const Color chequeColor = Color(0xFFD97706); // Amber 600
  static const Color netBankingColor = Color(0xFF7C3AED); // Purple 600
  static const Color balanceDueColor = Color(0xFFDC2626); // Red 600
  static const Color error = balanceDueColor;
  static const Color partialBadgeColor = Color(0xFFB45309); // Dark Amber

  // Corporate Colors for Both Distributor Firms
  static const Color purvaPrimary = Color(0xFF1E3A8A); // Royal Navy Blue
  static const Color purvaLight = Color(0xFFEFF6FF); // Blue 50
  static const Color purvaBorder = Color(0xFF93C5FD); // Blue 300
  static const Color purvaText = Color(0xFF1D4ED8); // Blue 700

  static const Color manasPrimary = Color(0xFF0F766E); // Deep Forest Teal
  static const Color manasLight = Color(0xFFF0FDFA); // Teal 50
  static const Color manasBorder = Color(0xFF5EEAD4); // Teal 300
  static const Color manasText = Color(0xFF0F766E); // Teal 700

  static Color getBusinessColor(String business) {
    if (business.toLowerCase().contains('purva')) {
      return purvaPrimary;
    } else if (business.toLowerCase().contains('manas')) {
      return manasPrimary;
    }
    return primary;
  }

  static Color getBusinessLightColor(String business) {
    if (business.toLowerCase().contains('purva')) {
      return purvaLight;
    } else if (business.toLowerCase().contains('manas')) {
      return manasLight;
    }
    return const Color(0xFFF1F5F9);
  }

  static Color getBusinessBorderColor(String business) {
    if (business.toLowerCase().contains('purva')) {
      return purvaBorder;
    } else if (business.toLowerCase().contains('manas')) {
      return manasBorder;
    }
    return border;
  }

  static Color getBusinessTextColor(String business) {
    if (business.toLowerCase().contains('purva')) {
      return purvaText;
    } else if (business.toLowerCase().contains('manas')) {
      return manasText;
    }
    return primary;
  }

  static const Color navyHeader = Color(0xFF0F172A);
  static const Color subtleSurface = Color(0xFFF1F5F9);

  /// Clean tabular numeric style so all currency figures align across rows and cards.
  static TextStyle tabularAmount({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w700,
    Color color = textPrimary,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border, width: 1)),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        iconTheme: IconThemeData(color: primary, size: 22),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: primary,
          letterSpacing: -0.2,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: primary.withValues(alpha: 0.08),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 22);
          }
          return const IconThemeData(color: textSecondary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: primary,
            );
          }
          return const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: border,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: secondary, width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

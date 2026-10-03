import 'package:flutter/material.dart';

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
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.15,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: secondary, width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'providers/collection_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/main_navigation_shell.dart';
import 'screens/login_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait on mobile devices for stable handheld experience
  if (!kIsWeb) {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {}
  }

  // Set system UI chrome for seamless Android status and navigation bars
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  try {
    await SupabaseService().init();
  } catch (e) {
    debugPrint('Supabase startup notice: $e');
  }
  runApp(const DailyCollectionApp());
}

class DailyCollectionApp extends StatelessWidget {
  const DailyCollectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CollectionProvider()),
      ],
      child: MaterialApp(
        title: 'Daily Collection',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          final windowMediaQuery = MediaQuery.of(context);
          // Clamp text scale factor between 0.85 and 1.15 to ensure
          // device accessibility scaling does not cause RenderFlex overflows
          final clampedScaler = windowMediaQuery.textScaler.clamp(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.15,
          );

          final double screenWidth = windowMediaQuery.size.width;
          // Responsive layout:
          // If screen is wider than 520px (tablet, desktop browser, wide display),
          // frame the app inside a clean mobile container (maxWidth: 480px) centered
          // on a dark backdrop, giving an authentic smartphone experience everywhere.
          // On actual mobile phones (screenWidth <= 520px), fill 100% of the display.
          final bool isWideScreen = screenWidth > 520;
          final double effectiveWidth = isWideScreen ? 480.0 : screenWidth;

          final effectiveMediaQuery = windowMediaQuery.copyWith(
            size: Size(effectiveWidth, windowMediaQuery.size.height),
            textScaler: clampedScaler,
          );

          final Widget appWidget = MediaQuery(
            data: effectiveMediaQuery,
            child: child ?? const SizedBox.shrink(),
          );

          if (isWideScreen) {
            return Container(
              color: const Color(0xFF0F172A),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 30,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRect(child: appWidget),
                  ),
                ),
              ),
            );
          }

          return appWidget;
        },
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isLoading) {
              return const Scaffold(
                backgroundColor: Color(0xFF0F172A),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
            }
            if (auth.isAuthenticated) {
              return const MainNavigationShell();
            }
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}

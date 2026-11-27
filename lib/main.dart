import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'providers/collection_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/main_navigation_shell.dart';
import 'screens/login_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        ChangeNotifierProxyProvider<AuthProvider, CollectionProvider>(
          create: (_) => CollectionProvider(),
          update: (_, auth, collection) {
            final provider = collection ?? CollectionProvider();
            provider.onUsersSynced = auth.applySyncedUsers;
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Purva Enterprises',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          final windowMediaQuery = MediaQuery.of(context);
          // Clamp text scale factor between 0.85 and 1.15 so accessibility scaling
          // remains legible without breaking compact rows or overflowing controls.
          final clampedScaler = windowMediaQuery.textScaler.clamp(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.15,
          );

          return MediaQuery(
            data: windowMediaQuery.copyWith(textScaler: clampedScaler),
            child: child ?? const SizedBox.shrink(),
          );
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

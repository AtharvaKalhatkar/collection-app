import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBEU16HqUbTZRGeIxRNg8LjBuDTWluJKTk',
    appId: '1:978582714167:web:ab1d2afbb26336b8730cb2',
    messagingSenderId: '978582714167',
    projectId: 'collection-app-50703',
    authDomain: 'collection-app-50703.firebaseapp.com',
    storageBucket: 'collection-app-50703.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBEU16HqUbTZRGeIxRNg8LjBuDTWluJKTk',
    appId: '1:978582714167:android:collection_app_android',
    messagingSenderId: '978582714167',
    projectId: 'collection-app-50703',
    storageBucket: 'collection-app-50703.firebasestorage.app',
  );
}

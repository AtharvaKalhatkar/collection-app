import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/collection_model.dart';
import '../models/shop_model.dart';
import '../models/route_model.dart';

class FirebaseConfig {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? storageBucket;
  final String? authDomain;
  final String? measurementId;

  const FirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.storageBucket,
    this.authDomain,
    this.measurementId,
  });

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'appId': appId,
        'messagingSenderId': messagingSenderId,
        'projectId': projectId,
        'storageBucket': storageBucket,
        'authDomain': authDomain,
        'measurementId': measurementId,
      };

  factory FirebaseConfig.fromJson(Map<String, dynamic> json) => FirebaseConfig(
        apiKey: json['apiKey'] as String? ?? '',
        appId: json['appId'] as String? ?? '',
        messagingSenderId: json['messagingSenderId'] as String? ?? '',
        projectId: json['projectId'] as String? ?? '',
        storageBucket: json['storageBucket'] as String?,
        authDomain: json['authDomain'] as String?,
        measurementId: json['measurementId'] as String?,
      );

  bool get isValid => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  FirebaseOptions toFirebaseOptions() => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId.isEmpty ? '978582714167' : messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket,
        authDomain: authDomain,
        measurementId: measurementId,
      );
}

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  static const String _keyFirebaseConfig = 'firebase_config_v1';
  static const String _keyFirebaseEnabled = 'firebase_enabled_v1';

  static const FirebaseConfig defaultConfig = FirebaseConfig(
    apiKey: 'AIzaSyBEU16HqUbTZRGeIxRNg8LjBuDTWluJKTk',
    authDomain: 'collection-app-50703.firebaseapp.com',
    projectId: 'collection-app-50703',
    storageBucket: 'collection-app-50703.firebasestorage.app',
    messagingSenderId: '978582714167',
    appId: '1:978582714167:web:ab1d2afbb26336b8730cb2',
    measurementId: 'G-0YTCRYR2KN',
  );

  bool _isInitialized = false;
  bool _isEnabled = false;
  FirebaseConfig? _config;
  String? _lastError;

  bool get isInitialized => _isInitialized || Firebase.apps.isNotEmpty;
  bool get isEnabled => _isEnabled;
  FirebaseConfig? get config => _config ?? defaultConfig;
  String? get lastError => _lastError;

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }
  FirebaseStorage? get _storage {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseStorage.instance;
      }
    } catch (_) {}
    return null;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_keyFirebaseEnabled) ?? true;
      final rawConfig = prefs.getString(_keyFirebaseConfig);

      if (rawConfig != null && rawConfig.isNotEmpty) {
        _config = FirebaseConfig.fromJson(jsonDecode(rawConfig) as Map<String, dynamic>);
      } else {
        _config = defaultConfig;
      }

      if (_isEnabled && _config != null && _config!.isValid) {
        await _connectFirebase(_config!);
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Firebase init error: $e');
    }
  }

  Future<bool> connectWithConfig(FirebaseConfig config) async {
    try {
      final success = await _connectFirebase(config);
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyFirebaseConfig, jsonEncode(config.toJson()));
        await prefs.setBool(_keyFirebaseEnabled, true);
        _config = config;
        _isEnabled = true;
      }
      return success;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<bool> _connectFirebase(FirebaseConfig config) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: config.toFirebaseOptions());
      }
      _isInitialized = true;
      _lastError = null;
      return true;
    } catch (e) {
      _isInitialized = false;
      _lastError = e.toString();
      debugPrint('Error connecting to Firebase: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFirebaseEnabled, false);
    _isEnabled = false;
    _isInitialized = false;
  }

  // --- Image Upload to Firebase Storage ---
  Future<String?> uploadInvoiceImage({
    required String collectionId,
    required Uint8List imageBytes,
  }) async {
    if (!_isInitialized || _storage == null) return null;

    try {
      final ref = _storage!.ref().child('invoices/$collectionId.jpg');
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final uploadTask = await ref.putData(imageBytes, metadata);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage upload failed: $e');
      return null;
    }
  }

  // --- Collection Sync to Cloud Firestore ---
  Future<bool> saveCollection(CollectionModel collection) async {
    if (!_isInitialized || _firestore == null) return false;

    try {
      final data = collection.toJson();
      // Save directly to Firestore (supports compressed photoBase64 on free Spark plan)
      await _firestore!.collection('collections').doc(collection.id).set(data);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving collection to Firestore: $e');
      return false;
    }
  }

  Future<List<CollectionModel>> fetchCollections() async {
    if (!_isInitialized || _firestore == null) return [];

    try {
      final snapshot = await _firestore!
          .collection('collections')
          .orderBy('collectedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => CollectionModel.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint('Error fetching collections from Firestore: $e');
      return [];
    }
  }

  // --- Shop Sync to Cloud Firestore ---
  Future<bool> saveShop(ShopModel shop) async {
    if (!_isInitialized || _firestore == null) return false;

    try {
      await _firestore!.collection('shops').doc(shop.id).set(shop.toJson());
      return true;
    } catch (e) {
      debugPrint('Error saving shop to Firestore: $e');
      return false;
    }
  }

  Future<List<ShopModel>> fetchShops() async {
    if (!_isInitialized || _firestore == null) return [];

    try {
      final snapshot = await _firestore!.collection('shops').get();
      return snapshot.docs.map((doc) => ShopModel.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint('Error fetching shops from Firestore: $e');
      return [];
    }
  }

  // --- Route Sync to Cloud Firestore ---
  Future<bool> saveRoute(RouteModel route) async {
    if (!_isInitialized || _firestore == null) return false;

    try {
      await _firestore!.collection('routes').doc(route.id).set(route.toJson());
      return true;
    } catch (e) {
      debugPrint('Error saving route to Firestore: $e');
      return false;
    }
  }

  Future<List<RouteModel>> fetchRoutes() async {
    if (!_isInitialized || _firestore == null) return [];

    try {
      final snapshot = await _firestore!.collection('routes').get();
      return snapshot.docs.map((doc) => RouteModel.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint('Error fetching routes from Firestore: $e');
      return [];
    }
  }

  // --- Deletion Sync to Cloud Firestore ---
  Future<bool> deleteCollection(String id) async {
    final fs = _firestore;
    if (fs == null) return false;
    try {
      await fs.collection('collections').doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting collection from Firestore: $e');
      return false;
    }
  }

  Future<bool> deleteShop(String id) async {
    final fs = _firestore;
    if (fs == null) return false;
    try {
      await fs.collection('shops').doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting shop from Firestore: $e');
      return false;
    }
  }

  Future<bool> deleteRoute(String id) async {
    final fs = _firestore;
    if (fs == null) return false;
    try {
      await fs.collection('routes').doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting route from Firestore: $e');
      return false;
    }
  }
}
